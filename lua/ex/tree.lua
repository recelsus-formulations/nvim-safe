local M = {}
local states = {}
local tree_width = 30

local function report_error(message)
    vim.notify(tostring(message), vim.log.levels.ERROR, { title = "File tree" })
end

local function is_valid_window(window)
    return window ~= nil and vim.api.nvim_win_is_valid(window)
end

local function get_state()
    local tabpage = vim.api.nvim_get_current_tabpage()
    if not states[tabpage] then
        states[tabpage] = { root = vim.fn.getcwd(), expanded = {}, entries = {} }
    end
    return states[tabpage]
end

local function selected_entry(state)
    if not is_valid_window(state.window) then
        return nil
    end
    return state.entries[vim.api.nvim_win_get_cursor(state.window)[1]]
end

local function render(state, selected_path)
    if not state.buffer or not vim.api.nvim_buf_is_valid(state.buffer) then
        return
    end
    local previous = selected_entry(state)
    selected_path = selected_path or (previous and previous.path)
    local entries = { { path = state.root, directory = true } }
    local lines = { state.root }
    local function append_directory(path, depth)
        local scanner, scan_error = vim.uv.fs_scandir(path)
        if not scanner then
            report_error(scan_error)
            return
        end
        local children = {}
        while true do
            local name, kind = vim.uv.fs_scandir_next(scanner)
            if not name then
                break
            end
            local child_path = vim.fs.joinpath(path, name)
            local stat = kind == "link" and vim.uv.fs_stat(child_path) or nil
            table.insert(children, {
                path = child_path,
                name = name,
                directory = kind == "directory" or (stat and stat.type == "directory") or false,
            })
        end
        table.sort(children, function(left, right)
            if left.directory ~= right.directory then
                return left.directory
            end
            return left.name < right.name
        end)
        for _, entry in ipairs(children) do
            table.insert(entries, entry)
            local marker = entry.directory and (state.expanded[entry.path] and "- " or "+ ") or "  "
            table.insert(lines, string.rep("  ", depth) .. marker .. entry.name)
            if entry.directory and state.expanded[entry.path] then
                append_directory(entry.path, depth + 1)
            end
        end
    end
    append_directory(state.root, 0)
    state.entries = entries
    vim.bo[state.buffer].modifiable = true
    vim.api.nvim_buf_set_lines(state.buffer, 0, -1, false, lines)
    vim.bo[state.buffer].modifiable = false
    if is_valid_window(state.window) then
        for index, entry in ipairs(entries) do
            if entry.path == selected_path then
                vim.api.nvim_win_set_cursor(state.window, { index, 0 })
                break
            end
        end
    end
end

local function usable_windows(state)
    local windows = {}
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local buffer = vim.api.nvim_win_get_buf(window)
        local config = vim.api.nvim_win_get_config(window)
        if window ~= state.window and config.relative == "" and config.focusable ~= false
            and vim.bo[buffer].buftype == "" and not vim.wo[window].winfixbuf
        then
            table.insert(windows, window)
        end
    end
    return windows
end

local function pick_window(windows)
    if #windows <= 1 then
        return windows[1]
    end
    local labels = "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890"
    if #windows > #labels then
        report_error("Too many windows to select")
        return nil
    end
    local saved = {}
    local laststatus = vim.o.laststatus
    vim.o.laststatus = 2
    for index, window in ipairs(windows) do
        saved[window] = vim.wo[window].statusline
        vim.wo[window].statusline = "%=" .. labels:sub(index, index) .. "%="
    end
    vim.cmd.redraw()
    local ok, key = pcall(vim.fn.getcharstr)
    for window, statusline in pairs(saved) do
        if is_valid_window(window) then
            vim.wo[window].statusline = statusline
        end
    end
    vim.o.laststatus = laststatus
    if ok then
        for index, window in ipairs(windows) do
            if key:upper() == labels:sub(index, index) and is_valid_window(window) then
                return window
            end
        end
    end
end

local function open_entry(state, mode)
    local entry = selected_entry(state)
    if not entry then
        return
    end
    if entry.directory then
        if entry.path ~= state.root then
            state.expanded[entry.path] = not state.expanded[entry.path]
            render(state)
        end
        return
    end
    local windows = usable_windows(state)
    local target
    for _, window in ipairs(windows) do
        if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(window)) == entry.path then
            if mode ~= "preview" then
                vim.api.nvim_set_current_win(window)
                vim.bo[vim.api.nvim_win_get_buf(window)].bufhidden = ""
            end
            return
        end
    end
    if #windows > 0 then
        target = pick_window(windows)
        if not target then
            return
        end
    end
    local was_loaded = false
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_get_name(buffer) == entry.path and vim.api.nvim_buf_is_loaded(buffer) then
            was_loaded = true
            break
        end
    end
    local ok, open_error = pcall(function()
        if target then
            vim.api.nvim_set_current_win(target)
            local buffer = vim.api.nvim_win_get_buf(target)
            if mode == "edit" or mode == "preview" then
                if not vim.o.hidden and vim.bo[buffer].modified then
                    vim.cmd("belowright vsplit")
                end
            else
                vim.cmd(mode == "vertical" and "belowright vsplit" or "belowright split")
            end
        else
            vim.api.nvim_set_current_win(state.window)
            vim.cmd("belowright vsplit")
        end
        vim.api.nvim_cmd({ cmd = "edit", args = { entry.path } }, {})
        local buffer = vim.api.nvim_get_current_buf()
        if mode == "preview" and not was_loaded then
            vim.bo[buffer].bufhidden = "delete"
            vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
                buffer = buffer,
                once = true,
                callback = function()
                    vim.bo[buffer].bufhidden = ""
                end,
            })
        elseif mode ~= "preview" then
            vim.bo[buffer].bufhidden = ""
        end
    end)
    if is_valid_window(state.window) then
        vim.api.nvim_win_set_width(state.window, tree_width)
        if mode == "preview" or not ok then
            vim.api.nvim_set_current_win(state.window)
        end
    end
    if not ok then
        report_error(open_error)
    end
end

local function matching_buffers(path)
    local buffers = {}
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        local name = vim.api.nvim_buf_get_name(buffer)
        if name == path or name:sub(1, #path + 1) == path .. "/" then
            table.insert(buffers, buffer)
        end
    end
    return buffers
end

local function create_entry(state)
    local entry = selected_entry(state)
    local directory = entry and (entry.directory and entry.path or vim.fs.dirname(entry.path)) or state.root
    vim.ui.input({ prompt = "Create (trailing / for directory): ", default = directory .. "/" }, function(path)
        if not path or path == "" then
            return
        end
        local is_directory = path:sub(-1) == "/"
        path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("/+$", "")
        local ok, create_error = pcall(function()
            if vim.uv.fs_lstat(path) then
                error("Path already exists: " .. path)
            end
            vim.fn.mkdir(is_directory and path or vim.fs.dirname(path), "p")
            if not is_directory then
                local descriptor, file_error = vim.uv.fs_open(path, "wx", 420)
                if not descriptor then
                    error(file_error)
                end
                vim.uv.fs_close(descriptor)
            end
        end)
        if not ok then
            report_error(create_error)
        end
        state.expanded[directory] = true
        render(state, path)
    end)
end

local function delete_entry(state)
    local entry = selected_entry(state)
    if not entry or entry.path == state.root then
        return
    end
    local buffers = matching_buffers(entry.path)
    for _, buffer in ipairs(buffers) do
        if vim.bo[buffer].modified then
            report_error("Save or discard changes before deleting: " .. vim.api.nvim_buf_get_name(buffer))
            return
        end
    end
    vim.ui.select({ "Cancel", "Delete" }, { prompt = "Delete " .. entry.path .. "?" }, function(choice)
        if choice ~= "Delete" then
            return
        end
        for _, buffer in ipairs(matching_buffers(entry.path)) do
            if vim.bo[buffer].modified then
                report_error("File has unsaved changes")
                return
            end
        end
        local stat = vim.uv.fs_lstat(entry.path)
        local flags = stat and stat.type == "directory" and "rf" or ""
        if vim.fn.delete(entry.path, flags) ~= 0 then
            report_error("Could not delete: " .. entry.path)
            return
        end
        for _, buffer in ipairs(buffers) do
            if vim.api.nvim_buf_is_valid(buffer) then
                vim.api.nvim_buf_delete(buffer, { force = false })
            end
        end
        render(state)
    end)
end

local function rename_entry(state)
    local entry = selected_entry(state)
    if not entry or entry.path == state.root then
        return
    end
    vim.ui.input({ prompt = "Rename: ", default = entry.path }, function(path)
        if not path or path == "" then
            return
        end
        path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("/+$", "")
        if path == entry.path then
            return
        end
        if vim.uv.fs_lstat(path) then
            report_error("Path already exists: " .. path)
            return
        end
        for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
            local name = vim.api.nvim_buf_get_name(buffer)
            if name == path or name:sub(1, #path + 1) == path .. "/" then
                report_error("Destination has an existing buffer: " .. name)
                return
            end
        end
        local renamed, rename_error = vim.uv.fs_rename(entry.path, path)
        if not renamed then
            report_error(rename_error)
            return
        end
        for _, buffer in ipairs(matching_buffers(entry.path)) do
            local suffix = vim.api.nvim_buf_get_name(buffer):sub(#entry.path + 1)
            vim.api.nvim_buf_set_name(buffer, path .. suffix)
        end
        local expanded = {}
        for directory, value in pairs(state.expanded) do
            if directory == entry.path or directory:sub(1, #entry.path + 1) == entry.path .. "/" then
                directory = path .. directory:sub(#entry.path + 1)
            end
            expanded[directory] = value
        end
        state.expanded = expanded
        render(state, path)
    end)
end

local function open_tree(state)
    if is_valid_window(state.window) and vim.api.nvim_win_get_buf(state.window) == state.buffer then
        vim.api.nvim_set_current_win(state.window)
        render(state)
        return
    end
    if not state.buffer or not vim.api.nvim_buf_is_valid(state.buffer) then
        state.buffer = vim.api.nvim_create_buf(false, true)
        vim.bo[state.buffer].bufhidden = "hide"
        vim.bo[state.buffer].filetype = "revim_tree"
        vim.bo[state.buffer].swapfile = false
        local function map(key, callback, description)
            vim.keymap.set("n", key, callback, { buffer = state.buffer, silent = true, desc = description })
        end
        for key, mode in pairs({ ["<CR>"] = "edit", ["<Tab>"] = "preview", ["<C-v>"] = "vertical",
            ["<C-x>"] = "horizontal" }) do
            map(key, function() open_entry(state, mode) end, "tree: " .. mode)
        end
        map("a", function() create_entry(state) end, "tree: create")
        map("d", function() delete_entry(state) end, "tree: delete")
        map("r", function() rename_entry(state) end, "tree: rename")
        map("R", function() render(state) end, "tree: refresh")
        map("q", M.toggle, "tree: close")
    end
    vim.cmd("topleft " .. tree_width .. "vsplit")
    state.window = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.window, state.buffer)
    vim.wo[state.window].winfixwidth = true
    vim.wo[state.window][0].number = false
    vim.wo[state.window][0].relativenumber = false
    vim.wo[state.window][0].signcolumn = "no"
    vim.wo[state.window][0].foldcolumn = "0"
    vim.wo[state.window][0].wrap = false
    vim.wo[state.window][0].cursorline = true
    render(state)
end

function M.toggle()
    local state = get_state()
    if is_valid_window(state.window) and vim.api.nvim_win_get_buf(state.window) == state.buffer then
        if #vim.api.nvim_tabpage_list_wins(0) == 1 then
            vim.cmd("belowright vnew")
        end
        vim.api.nvim_win_close(state.window, true)
        return
    end
    open_tree(state)
end

local function open_directory(buffer, window, path)
    if not is_valid_window(window) or not vim.api.nvim_buf_is_valid(buffer)
        or vim.api.nvim_win_get_buf(window) ~= buffer or vim.bo[buffer].modified
        or vim.fs.normalize(vim.api.nvim_buf_get_name(buffer)) ~= path or vim.fn.isdirectory(path) ~= 1
    then
        return
    end
    local origin = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(window)
    local state = get_state()
    if state.root ~= path then
        state.root = path
        state.expanded = {}
    end
    if state.window == window and state.buffer and vim.api.nvim_buf_is_valid(state.buffer) then
        vim.api.nvim_win_set_buf(window, state.buffer)
    else
        local previous = vim.fn.bufnr("#")
        local previous_path = previous > 0 and vim.api.nvim_buf_get_name(previous) or ""
        if previous <= 0 or not vim.api.nvim_buf_is_valid(previous) or vim.bo[previous].buftype ~= ""
            or vim.fn.isdirectory(previous_path) == 1
        then
            previous = vim.api.nvim_create_buf(true, false)
        end
        vim.api.nvim_win_set_buf(window, previous)
    end
    open_tree(state)
    if #vim.fn.win_findbuf(buffer) == 0 then
        vim.api.nvim_buf_delete(buffer, { force = false })
    end
    if origin ~= window and is_valid_window(origin) then
        vim.api.nvim_set_current_win(origin)
    end
end

function M.setup()
    vim.g.loaded_netrw = 1
    vim.g.loaded_netrwPlugin = 1
    vim.keymap.set("n", "<C-e>", M.toggle, { desc = "tree: toggle" })
    vim.api.nvim_create_user_command("Ex", M.toggle, {})
    local group = vim.api.nvim_create_augroup("revim_file_tree", { clear = true })
    vim.api.nvim_create_autocmd("BufEnter", {
        group = group,
        callback = function(options)
            local window = vim.api.nvim_get_current_win()
            local path = vim.api.nvim_buf_get_name(options.buf)
            if vim.api.nvim_win_get_config(window).relative ~= "" or vim.fn.isdirectory(path) ~= 1 then
                return
            end
            path = vim.fs.normalize(path)
            vim.schedule(function() open_directory(options.buf, window, path) end)
        end,
    })
    vim.api.nvim_create_autocmd("TabClosed", {
        group = group,
        callback = function()
            for tabpage, state in pairs(states) do
                if not vim.api.nvim_tabpage_is_valid(tabpage) then
                    if state.buffer and vim.api.nvim_buf_is_valid(state.buffer) then
                        vim.api.nvim_buf_delete(state.buffer, { force = true })
                    end
                    states[tabpage] = nil
                end
            end
        end,
    })
end

return M
