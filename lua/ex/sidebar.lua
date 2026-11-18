local M = {}
local compat = require("compat")
local views = {}
local view_order = {}
local states = {}
local sidebar_width = 30
local title_namespace = vim.api.nvim_create_namespace("ex_sidebar_titles")

local function tab_state(tabpage)
    tabpage = tabpage or vim.api.nvim_get_current_tabpage()
    if not states[tabpage] then
        states[tabpage] = { window = nil, active_view = nil, last_view = nil,
            buffers = {}, views = {}, source_window = nil }
    end
    return states[tabpage]
end

local function valid_window(window)
    return window and vim.api.nvim_win_is_valid(window)
end

local function close_preview(state)
    local window = state.preview_window
    local buffer = state.preview_buffer
    state.preview_window = nil
    state.preview_buffer = nil
    if valid_window(window) then
        vim.api.nvim_win_close(window, true)
    end
    if buffer and vim.api.nvim_buf_is_valid(buffer) then
        vim.api.nvim_buf_delete(buffer, { force = true })
    end
end

function M.refresh_preview()
    local state = tab_state()
    local window = state.window
    if not valid_window(window) or vim.api.nvim_get_current_win() ~= window then
        close_preview(state)
        return
    end
    local buffer = vim.api.nvim_win_get_buf(window)
    local cursor = vim.api.nvim_win_get_cursor(window)
    local line = vim.api.nvim_buf_get_lines(buffer, cursor[1] - 1, cursor[1], false)[1] or ""
    local view = vim.api.nvim_win_call(window, vim.fn.winsaveview)
    local info = vim.fn.getwininfo(window)[1]
    local width = vim.api.nvim_win_get_width(window) - (info and info.textoff or 0)
    if line == "" or ((view.leftcol or 0) == 0 and vim.fn.strdisplaywidth(line) <= width) then
        close_preview(state)
        return
    end
    close_preview(state)
    local position = vim.api.nvim_win_get_position(window)
    local right_column = position[2] + vim.api.nvim_win_get_width(window) + 1
    local available_right = vim.o.columns - right_column - 2
    local column = available_right >= 24 and right_column or 1
    local float_width = math.max(1, math.min(80, available_right >= 24 and available_right or vim.o.columns - 4))
    local max_height = math.max(1, vim.o.lines - vim.o.cmdheight - 4)
    local float_height = math.min(max_height, math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / float_width)))
    local cursor_row = position[1] + vim.api.nvim_win_call(window, vim.fn.winline) - 1
    local row = math.max(0, math.min(cursor_row, vim.o.lines - vim.o.cmdheight - float_height - 2))
    local preview_buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(preview_buffer, 0, -1, false, { line })
    vim.bo[preview_buffer].modifiable = false
    vim.bo[preview_buffer].bufhidden = "wipe"
    local preview_window = vim.api.nvim_open_win(preview_buffer, false, {
        relative = "editor", row = row, col = column,
        width = float_width, height = float_height, border = "rounded",
        style = "minimal", focusable = false,
    })
    vim.wo[preview_window].wrap = true
    state.preview_buffer = preview_buffer
    state.preview_window = preview_window
end

local function schedule_preview(state)
    state.preview_generation = (state.preview_generation or 0) + 1
    local generation = state.preview_generation
    vim.defer_fn(function()
        if states[vim.api.nvim_get_current_tabpage()] == state
            and state.preview_generation == generation
        then
            M.refresh_preview()
        end
    end, 100)
end

local function save_view(state)
    if valid_window(state.window) and state.active_view then
        state.views[state.active_view] = vim.api.nvim_win_call(state.window, vim.fn.winsaveview)
    end
end

function M.register(name, view)
    assert(type(name) == "string" and name ~= "", "Sidebar view name is required")
    assert(type(view) == "table" and type(view.create) == "function", "Sidebar view requires create()")
    assert(not views[name], "Sidebar view already registered: " .. name)
    views[name] = view
    view_order[#view_order + 1] = name
end

function M.get_window(tabpage)
    local window = tab_state(tabpage).window
    return valid_window(window) and window or nil
end

function M.current(tabpage)
    local state = tab_state(tabpage)
    return valid_window(state.window) and state.active_view or nil
end

function M.source_window()
    local window = tab_state().source_window
    return valid_window(window) and window or nil
end

function M.restore_width()
    local window = M.get_window()
    if window then
        vim.api.nvim_win_set_width(window, sidebar_width)
    end
end

function M.highlight_title(buffer, group, end_column)
    vim.api.nvim_buf_clear_namespace(buffer, title_namespace, 0, 1)
    if end_column > 0 then
        vim.api.nvim_buf_set_extmark(buffer, title_namespace, 0, 0, {
            end_col = end_column, hl_group = group, priority = 150,
        })
    end
end

function M.editor_windows()
    local state = tab_state()
    local windows = {}
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local buffer = vim.api.nvim_win_get_buf(window)
        local config = vim.api.nvim_win_get_config(window)
        if window ~= state.window and config.relative == "" and config.focusable ~= false
            and vim.bo[buffer].buftype == "" and not compat.is_winfixbuf(window)
        then
            windows[#windows + 1] = window
        end
    end
    return windows
end

function M.pick_editor_window(windows)
    windows = windows or M.editor_windows()
    if #windows <= 1 then
        return windows[1]
    end
    local labels = "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890"
    if #windows > #labels then
        vim.notify("Too many windows to select", vim.log.levels.ERROR, { title = "Sidebar" })
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
        if valid_window(window) then
            vim.wo[window].statusline = statusline
        end
    end
    vim.o.laststatus = laststatus
    if ok then
        for index, window in ipairs(windows) do
            if key:upper() == labels:sub(index, index) and valid_window(window) then
                return window
            end
        end
    end
end

function M.show(name, context)
    local view = assert(views[name], "Unknown sidebar view: " .. tostring(name))
    local state = tab_state()
    close_preview(state)
    local current_window = vim.api.nvim_get_current_win()
    if current_window ~= state.window and vim.api.nvim_win_get_config(current_window).relative == "" then
        state.source_window = current_window
    end
    if not valid_window(state.window) then
        vim.cmd("topleft " .. sidebar_width .. "vsplit")
        state.window = vim.api.nvim_get_current_win()
    else
        save_view(state)
        vim.api.nvim_set_current_win(state.window)
    end
    local buffer = state.buffers[name]
    if not buffer or not vim.api.nvim_buf_is_valid(buffer) then
        buffer = view.create(context)
        assert(type(buffer) == "number" and vim.api.nvim_buf_is_valid(buffer), "Sidebar view returned an invalid buffer")
        state.buffers[name] = buffer
    end
    vim.keymap.set("n", "<C-n>", function() M.cycle(1) end,
        { buffer = buffer, silent = true, desc = "sidebar: next view" })
    vim.keymap.set("n", "<C-p>", function() M.cycle(-1) end,
        { buffer = buffer, silent = true, desc = "sidebar: previous view" })
    vim.api.nvim_win_set_buf(state.window, buffer)
    state.active_view = name
    vim.wo[state.window].winfixwidth = true
    M.restore_width()
    for option, value in pairs({ number = false, relativenumber = false, signcolumn = "no",
        foldcolumn = "0", wrap = false, cursorline = true }) do
        compat.set_window_local(state.window, option, value)
    end
    if view.refresh then
        view.refresh(context)
    end
    if state.views[name] then
        pcall(vim.api.nvim_win_call, state.window, function()
            vim.fn.winrestview(state.views[name])
        end)
    end
    schedule_preview(state)
    return state.window
end

function M.close()
    local state = tab_state()
    close_preview(state)
    if not valid_window(state.window) then
        state.window = nil
        state.active_view = nil
        return
    end
    save_view(state)
    state.last_view = state.active_view
    if #vim.api.nvim_tabpage_list_wins(0) == 1 then
        vim.api.nvim_set_current_win(state.window)
        vim.cmd("belowright vnew")
    end
    local window = state.window
    state.window = nil
    state.active_view = nil
    vim.api.nvim_win_close(window, true)
end

function M.toggle(name, context)
    if name == nil then
        if M.current() then
            M.close()
        else
            M.show(tab_state().last_view or view_order[1], { restore = true })
        end
        return
    end
    if M.current() == name then
        M.close()
    else
        M.show(name, context)
    end
end

function M.cycle(direction)
    local current = M.current()
    if not current or #view_order < 2 then
        return
    end
    for index, name in ipairs(view_order) do
        if name == current then
            local next_index = (index - 1 + direction) % #view_order + 1
            M.show(view_order[next_index], { restore = true })
            return
        end
    end
end

function M.setup()
    vim.keymap.set("n", "<C-e>", function() M.toggle() end, { desc = "sidebar: toggle" })
    local group = vim.api.nvim_create_augroup("ex_sidebar", { clear = true })
    local function set_title_highlights()
        vim.api.nvim_set_hl(0, "ExSidebarFileTitle", {
            fg = "#87cefa", bg = "#263a4b", bold = true, default = true,
        })
        vim.api.nvim_set_hl(0, "ExSidebarSymbolTitle", {
            fg = "#d5a6f0", bg = "#3a2d48", bold = true, default = true,
        })
        vim.api.nvim_set_hl(0, "ExSidebarDiagnosticTitle", {
            fg = "#f3c27a", bg = "#49392a", bold = true, default = true,
        })
    end
    set_title_highlights()
    vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_title_highlights })
    vim.api.nvim_create_autocmd({ "CursorMoved", "WinEnter", "WinScrolled" }, {
        group = group,
        callback = function() schedule_preview(tab_state()) end,
    })
    vim.api.nvim_create_autocmd("WinLeave", {
        group = group,
        callback = function()
            local state = tab_state()
            if vim.api.nvim_get_current_win() == state.window then
                close_preview(state)
            end
        end,
    })
    vim.api.nvim_create_autocmd("VimResized", {
        group = group,
        callback = function() schedule_preview(tab_state()) end,
    })
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        callback = function(options)
            local closed = tonumber(options.match)
            for _, state in pairs(states) do
                if state.window == closed then
                    close_preview(state)
                    state.last_view = state.active_view
                    state.window = nil
                    state.active_view = nil
                end
            end
        end,
    })
    vim.api.nvim_create_autocmd("TabClosed", {
        group = group,
        callback = function()
            for tabpage, state in pairs(states) do
                if not vim.api.nvim_tabpage_is_valid(tabpage) then
                    close_preview(state)
                    for name, buffer in pairs(state.buffers) do
                        if views[name].dispose then
                            views[name].dispose({ tabpage = tabpage, buffer = buffer })
                        end
                        if vim.api.nvim_buf_is_valid(buffer) then
                            vim.api.nvim_buf_delete(buffer, { force = true })
                        end
                    end
                    states[tabpage] = nil
                end
            end
        end,
    })
end

return M
