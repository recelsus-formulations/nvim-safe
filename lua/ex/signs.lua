local M = {}
local namespace = vim.api.nvim_create_namespace("ex_signs")
local states = {}
local timer
local stopping = false
local maximum_bytes = 1024 * 1024
local signs = {
    add = { text = "+", group = "ExGitAdd" },
    change = { text = "│", group = "ExGitChange" },
    delete = { text = "_", group = "ExGitDelete" },
    topdelete = { text = "‾", group = "ExGitDelete" },
    changedelete = { text = "~", group = "ExGitChange" },
}

local function is_current(buffer, state)
    return not stopping and states[buffer] == state and vim.api.nvim_buf_is_valid(buffer)
        and vim.api.nvim_buf_is_loaded(buffer) and vim.bo[buffer].buftype == ""
        and vim.api.nvim_buf_get_name(buffer) == state.path
end

local function clear_signs(buffer)
    if vim.api.nvim_buf_is_valid(buffer) then
        vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
    end
end

local function render(buffer, state)
    if not is_current(buffer, state) then
        return
    end
    clear_signs(buffer)
    if not state.base or vim.bo[buffer].binary or vim.api.nvim_buf_line_count(buffer) > 20000 then
        return
    end
    local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
    local text = table.concat(lines, "\n")
    if vim.bo[buffer].endofline then
        text = text .. "\n"
    end
    if #text > maximum_bytes then
        return
    end
    local base = state.base
    if vim.bo[buffer].fileformat == "dos" then
        base = base:gsub("\r\n", "\n")
    end
    if vim.bo[buffer].bomb and base:sub(1, 3) == "\239\187\191" then
        base = base:sub(4)
    end
    local hunks = vim.text.diff(base, text, { result_type = "indices", algorithm = "histogram" })
    local positions = {}
    for _, hunk in ipairs(hunks) do
        local removed, start_line, added = hunk[2], hunk[3], hunk[4]
        if added == 0 then
            positions[math.max(1, start_line)] = start_line == 0 and "topdelete" or "delete"
        else
            local changed = math.min(removed, added)
            for offset = 0, added - 1 do
                positions[start_line + offset] = offset < changed and "change" or "add"
            end
            if removed > added then
                positions[start_line + added - 1] = "changedelete"
            end
        end
    end
    for row, kind in pairs(positions) do
        local sign = signs[kind]
        vim.api.nvim_buf_set_extmark(buffer, namespace, math.min(row, #lines) - 1, 0, {
            sign_text = sign.text,
            sign_hl_group = sign.group,
            number_hl_group = sign.group,
            priority = 6,
        })
    end
end

local function refresh(buffer)
    if stopping or not vim.api.nvim_buf_is_loaded(buffer) or vim.bo[buffer].buftype ~= "" then
        return
    end
    local path = vim.api.nvim_buf_get_name(buffer)
    if path == "" then
        return
    end
    local state = states[buffer]
    if not state or state.path ~= path then
        state = { path = path, revision = 0 }
        states[buffer] = state
        clear_signs(buffer)
    end
    if state.process then
        return
    end
    local directory = vim.fs.dirname(path)
    local directory_stat = vim.uv.fs_stat(directory)
    if not directory_stat or directory_stat.type ~= "directory" then
        state.base = nil
        state.object = nil
        clear_signs(buffer)
        return
    end
    local function run(arguments, callback)
        local command = { "git", "--no-optional-locks", "--literal-pathspecs", "-C", directory }
        vim.list_extend(command, arguments)
        state.process = vim.system(command, {}, vim.schedule_wrap(function(result)
            if not is_current(buffer, state) then
                return
            end
            state.process = nil
            callback(result)
        end))
    end
    run({ "ls-files", "--stage", "-z", "--", vim.fs.basename(path) }, function(result)
        local mode, object = result.stdout:match("^(%d+) (%x+) 0\t")
        if result.code ~= 0 or (mode ~= "100644" and mode ~= "100755") then
            state.base = nil
            state.object = nil
            clear_signs(buffer)
            return
        end
        if state.object == object then
            render(buffer, state)
            return
        end
        run({ "cat-file", "-s", object }, function(size_result)
            local size = tonumber(size_result.stdout)
            if size_result.code ~= 0 or not size or size > maximum_bytes then
                state.base = nil
                state.object = nil
                clear_signs(buffer)
                return
            end
            run({ "cat-file", "blob", object }, function(blob_result)
                state.object = object
                state.base = blob_result.code == 0 and not blob_result.stdout:find("\0", 1, true)
                    and blob_result.stdout or nil
                render(buffer, state)
            end)
        end)
    end)
end

local function refresh_visible()
    local seen = {}
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local buffer = vim.api.nvim_win_get_buf(window)
        if not seen[buffer] then
            seen[buffer] = true
            refresh(buffer)
        end
    end
end

function M.setup()
    if vim.fn.executable("git") ~= 1 then
        vim.notify("Git signs disabled: git executable not found", vim.log.levels.WARN)
        return
    end
    stopping = false
    vim.opt.signcolumn = "yes"
    local function set_highlights()
        vim.api.nvim_set_hl(0, "ExGitAdd", { fg = "#98c379", default = true })
        vim.api.nvim_set_hl(0, "ExGitChange", { fg = "#e5c07b", default = true })
        vim.api.nvim_set_hl(0, "ExGitDelete", { fg = "#e06c75", default = true })
    end
    set_highlights()
    local group = vim.api.nvim_create_augroup("ex_signs", { clear = true })
    vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_highlights })
    vim.api.nvim_create_autocmd({ "BufReadPost", "BufWinEnter", "BufWritePost", "BufFilePost" }, {
        group = group,
        callback = function(options) refresh(options.buf) end,
    })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
        group = group,
        callback = function(options)
            local state = states[options.buf]
            if not state then
                refresh(options.buf)
                return
            end
            state.revision = state.revision + 1
            local revision = state.revision
            vim.defer_fn(function()
                if is_current(options.buf, state) and revision == state.revision then
                    render(options.buf, state)
                end
            end, 150)
        end,
    })
    vim.api.nvim_create_autocmd({ "FocusGained", "TabEnter" }, { group = group, callback = refresh_visible })
    vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
        group = group,
        callback = function(options)
            local state = states[options.buf]
            states[options.buf] = nil
            if state and state.process then
                pcall(state.process.kill, state.process, 15)
            end
        end,
    })
    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = function()
            stopping = true
            if timer then
                vim.fn.timer_stop(timer)
                timer = nil
            end
            for _, state in pairs(states) do
                if state.process then
                    pcall(state.process.kill, state.process, 15)
                end
            end
        end,
    })
    if timer then
        vim.fn.timer_stop(timer)
    end
    timer = vim.fn.timer_start(1000, refresh_visible, { ["repeat"] = -1 })
    refresh_visible()
end

return M
