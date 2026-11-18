local M = {}
local compat = require("compat")
local views = {}
local active

function M.register(name, view)
    assert(type(name) == "string" and name ~= "", "Panel view name is required")
    assert(type(view) == "table" and type(view.title) == "string" and type(view.on_show) == "function"
        and type(view.on_change) == "function" and type(view.on_open) == "function",
        "Panel view requires title, on_show, on_change and on_open")
    assert(not views[name], "Panel view is already registered: " .. name)
    views[name] = view
end

function M.current()
    return active and not active.closed and active.view_name or nil
end

function M.is_active(state)
    return active == state and not state.closed and vim.api.nvim_buf_is_valid(state.input_buffer)
        and vim.api.nvim_win_is_valid(state.input_window)
end

function M.close(state)
    state = state or active
    if not state or state.closed then
        return
    end
    state.closed = true
    if active == state then
        active = nil
    end
    if state.view.on_close then
        state.view.on_close(state)
    end
    vim.cmd.stopinsert()
    for _, window in ipairs({ state.input_window, state.extension_window, state.exclude_window,
        state.results_window, state.preview_window }) do
        if window and vim.api.nvim_win_is_valid(window) then
            vim.api.nvim_win_close(window, true)
        end
    end
    for _, buffer in ipairs({ state.input_buffer, state.extension_buffer, state.exclude_buffer,
        state.results_buffer, state.preview_buffer }) do
        if buffer and vim.api.nvim_buf_is_valid(buffer) then
            vim.api.nvim_buf_delete(buffer, { force = true })
        end
    end
    if vim.api.nvim_win_is_valid(state.origin) then
        vim.api.nvim_set_current_win(state.origin)
    end
end

local function create_windows(state)
    local width = math.min(vim.o.columns - 4, math.floor(vim.o.columns * 0.9))
    local height = math.floor((vim.o.lines - vim.o.cmdheight) * 0.8)
    local row = math.floor((vim.o.lines - vim.o.cmdheight - height) / 2)
    local column = math.floor((vim.o.columns - width - 2) / 2)
    local results_width = width
    local results_height = height - 11
    local preview_config
    if height >= 16 then
        if width >= 90 then
            results_width = math.floor((width - 2) / 2)
            preview_config = {
                row = row + 9, col = column + results_width + 2,
                width = width - results_width - 2, height = results_height,
            }
        else
            results_height = math.max(1, math.floor((height - 13) / 2))
            preview_config = {
                row = row + results_height + 11, col = column,
                width = width, height = height - results_height - 13,
            }
        end
    end
    state.results_window = vim.api.nvim_open_win(state.results_buffer, false, {
        relative = "editor", row = row + 9, col = column, width = results_width, height = results_height,
        border = "single", style = "minimal", title = " Results ",
    })
    compat.set_window_local(state.results_window, "cursorline", false)
    compat.set_window_local(state.results_window, "wrap", false)
    compat.set_window_local(state.results_window, "signcolumn", "no")
    if preview_config then
        preview_config.relative = "editor"
        preview_config.border = "single"
        preview_config.style = "minimal"
        preview_config.title = " Preview "
        preview_config.focusable = false
        state.preview_window = vim.api.nvim_open_win(state.preview_buffer, false, preview_config)
        compat.set_window_local(state.preview_window, "wrap", false)
        compat.set_window_local(state.preview_window, "signcolumn", "no")
        compat.set_window_local(state.preview_window, "number", true)
    end
    state.input_window = vim.api.nvim_open_win(state.input_buffer, true, {
        relative = "editor", row = row, col = column, width = width, height = 1,
        border = "single", style = "minimal", title = " " .. state.view.title .. ": " .. state.root .. " ",
    })
    compat.set_window_local(state.input_window, "wrap", false)
    compat.set_window_local(state.input_window, "signcolumn", "no")
    state.extension_window = vim.api.nvim_open_win(state.extension_buffer, false, {
        relative = "editor", row = row + 3, col = column, width = width, height = 1,
        border = "single", style = "minimal", title = " Extensions (php,js) ",
    })
    state.exclude_window = vim.api.nvim_open_win(state.exclude_buffer, false, {
        relative = "editor", row = row + 6, col = column, width = width, height = 1,
        border = "single", style = "minimal", title = " Exclude (*.json,node_modules/) ",
    })
    for _, window in ipairs({ state.extension_window, state.exclude_window }) do
        compat.set_window_local(window, "wrap", false)
        compat.set_window_local(window, "signcolumn", "no")
    end
end

local function set_keymaps(state)
    local input_windows = { state.input_window, state.extension_window, state.exclude_window, state.results_window }
    for _, buffer in ipairs({ state.input_buffer, state.extension_buffer, state.exclude_buffer, state.results_buffer }) do
        local function map(modes, key, callback, description)
            vim.keymap.set(modes, key, callback, { buffer = buffer, silent = true, desc = description })
        end
        map({ "i", "n" }, "<CR>", function() state.view.on_open(state) end, "panel: open")
        map({ "i", "n" }, "<C-v>", function() state.view.on_open(state, "vertical") end, "panel: vertical split")
        map({ "i", "n" }, "<C-x>", function() state.view.on_open(state, "horizontal") end,
            "panel: horizontal split")
        for key, direction in pairs({ ["<C-n>"] = 1, ["<Down>"] = 1,
            ["<C-p>"] = -1, ["<Up>"] = -1 }) do
            map({ "i", "n" }, key, function()
                if state.view.on_move then state.view.on_move(state, direction) end
            end, "panel: move selection")
        end
        for _, key in ipairs({ "<C-d>", "<C-u>" }) do
            map({ "i", "n" }, key, function()
                if state.preview_window and vim.api.nvim_win_is_valid(state.preview_window) then
                    vim.api.nvim_win_call(state.preview_window, function()
                        vim.cmd("normal! " .. vim.api.nvim_replace_termcodes(key, true, false, true))
                    end)
                end
            end, "panel: scroll preview")
        end
        map({ "i", "n" }, "<C-c>", function() M.close(state) end, "panel: close")
        map({ "n", "x" }, "<C-w>", "<Nop>", "panel: keep focus")
        map({ "i", "n" }, "<Tab>", function()
            vim.cmd.stopinsert()
            local current = vim.api.nvim_get_current_win()
            local next_index = 1
            for index, window in ipairs(input_windows) do
                if current == window then
                    next_index = index % #input_windows + 1
                    break
                end
            end
            vim.api.nvim_set_current_win(input_windows[next_index])
        end, "panel: switch input/results")
        map({ "i", "n" }, "<C-q>", function()
            if state.view.on_quickfix then state.view.on_quickfix(state) end
        end, "panel: send results to quickfix")
    end
end

local function set_autocmds(state)
    local group = vim.api.nvim_create_augroup("ex_panel_session", { clear = true })
    for _, buffer in ipairs({ state.input_buffer, state.extension_buffer, state.exclude_buffer }) do
        vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
            group = group, buffer = buffer, callback = function() state.view.on_change(state) end,
        })
    end
    vim.api.nvim_create_autocmd("WinEnter", {
        group = group,
        callback = function()
            local window = vim.api.nvim_get_current_win()
            if window ~= state.input_window and window ~= state.extension_window
                and window ~= state.exclude_window
            then
                return
            end
            vim.schedule(function()
                if M.is_active(state) and vim.api.nvim_get_current_win() == window then
                    vim.cmd.startinsert()
                end
            end)
        end,
    })
    vim.api.nvim_create_autocmd("CursorMoved", {
        group = group, buffer = state.results_buffer,
        callback = function()
            if M.is_active(state) and state.view.on_select then
                state.view.on_select(state)
            end
        end,
    })
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        callback = function(options)
            local window = tonumber(options.match)
            if not state.closed and (window == state.input_window or window == state.extension_window
                or window == state.exclude_window or window == state.results_window
                or window == state.preview_window)
            then
                vim.schedule(function() M.close(state) end)
            end
        end,
    })
    vim.api.nvim_create_autocmd("VimResized", { group = group, callback = function() M.close(state) end })
end

function M.show(name)
    local view = assert(views[name], "Unknown panel view: " .. tostring(name))
    if active and M.is_active(active) then
        if active.view_name ~= name then
            if active.view.on_close then
                active.view.on_close(active)
            end
            active.view = view
            active.view_name = name
            active.entries = {}
            active.selection = 1
            active.preview_entry = nil
            active.preview_cache = nil
            active.pattern_text = nil
            for _, buffer in ipairs({ active.input_buffer, active.extension_buffer, active.exclude_buffer }) do
                vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "" })
            end
            for _, buffer in ipairs({ active.results_buffer, active.preview_buffer }) do
                vim.bo[buffer].modifiable = true
                vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "" })
                vim.api.nvim_buf_clear_namespace(buffer, -1, 0, -1)
            end
            vim.api.nvim_win_set_config(active.input_window, {
                title = " " .. view.title .. ": " .. active.root .. " ",
            })
            view.on_show(active)
        end
        vim.api.nvim_set_current_win(active.input_window)
        vim.cmd.startinsert()
        return active
    end
    if active then
        M.close(active)
    end
    if vim.o.columns < 35 or vim.o.lines - vim.o.cmdheight < 15 then
        vim.notify("Screen is too small for panel", vim.log.levels.WARN)
        return
    end
    local state = {
        view = view, view_name = name, origin = vim.api.nvim_get_current_win(), root = vim.fn.getcwd(),
        entries = {}, selection = 1, revision = 0,
        input_buffer = vim.api.nvim_create_buf(false, true),
        extension_buffer = vim.api.nvim_create_buf(false, true),
        exclude_buffer = vim.api.nvim_create_buf(false, true),
        results_buffer = vim.api.nvim_create_buf(false, true),
        preview_buffer = vim.api.nvim_create_buf(false, true),
    }
    for _, buffer in ipairs({ state.input_buffer, state.extension_buffer, state.exclude_buffer,
        state.results_buffer, state.preview_buffer }) do
        vim.bo[buffer].bufhidden = "hide"
        vim.bo[buffer].swapfile = false
    end
    vim.bo[state.input_buffer].filetype = "ex_find_input"
    vim.bo[state.extension_buffer].filetype = "ex_find_input"
    vim.bo[state.exclude_buffer].filetype = "ex_find_input"
    vim.bo[state.results_buffer].filetype = "ex_find_results"
    vim.bo[state.preview_buffer].filetype = "ex_find_preview"
    create_windows(state)
    active = state
    set_keymaps(state)
    set_autocmds(state)
    view.on_show(state)
    vim.cmd.startinsert()
    return state
end

function M.setup()
    vim.api.nvim_create_user_command("SearchPanel", function(options)
        M.show(options.args)
    end, {
        nargs = 1,
        complete = function()
            local names = vim.tbl_keys(views)
            table.sort(names)
            return names
        end,
    })
end

return M
