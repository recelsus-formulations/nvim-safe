local M = {}
local terminals = {
    horizontal = { views = {} },
    float = { views = {} },
}

local function is_valid_window(window)
    return window ~= nil and vim.api.nvim_win_is_valid(window)
end

local function float_config()
    local available_height = math.max(1, vim.o.lines - vim.o.cmdheight - 2)
    local width = math.min(120, math.max(1, vim.o.columns - 2))
    local height = math.min(30, available_height)
    return {
        relative = "editor",
        width = width,
        height = height,
        row = math.max(0, math.floor((available_height - height) / 2)),
        col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
        border = "single",
        style = "minimal",
    }
end

local function restore_focus(view)
    if is_valid_window(view.origin)
        and vim.api.nvim_win_get_tabpage(view.origin) == vim.api.nvim_get_current_tabpage()
    then
        vim.api.nvim_set_current_win(view.origin)
    end
end

local function hide_view(view, direction)
    if not is_valid_window(view.window) then
        return
    end
    if direction == "horizontal" then
        view.height = vim.api.nvim_win_get_height(view.window)
        local ordinary_count = 0
        for _, window in ipairs(vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(view.window))) do
            if vim.api.nvim_win_get_config(window).relative == "" then
                ordinary_count = ordinary_count + 1
            end
        end
        if ordinary_count == 1 then
            vim.api.nvim_win_call(view.window, function()
                vim.cmd("aboveleft new")
            end)
        end
    end
    vim.api.nvim_win_close(view.window, true)
    view.window = nil
end

local function finish_terminal(terminal, buffer, direction)
    if terminal.buffer ~= buffer then
        return
    end
    terminal.buffer = nil
    local current_window = vim.api.nvim_get_current_win()
    local current_view
    for _, view in pairs(terminal.views) do
        if view.window == current_window then
            current_view = view
        end
        hide_view(view, direction)
    end
    if vim.api.nvim_buf_is_valid(buffer) then
        vim.api.nvim_buf_delete(buffer, { force = true })
    end
    if current_view then
        restore_focus(current_view)
    end
end

function M.toggle(direction)
    direction = direction or "horizontal"
    local terminal = terminals[direction]
    if not terminal then
        error("Unsupported terminal direction: " .. tostring(direction))
    end
    local tabpage = vim.api.nvim_get_current_tabpage()
    local view = terminal.views[tabpage] or {}
    terminal.views[tabpage] = view
    if is_valid_window(view.window) and vim.api.nvim_win_get_buf(view.window) ~= terminal.buffer then
        view.window = nil
    end
    if is_valid_window(view.window) then
        vim.cmd.stopinsert()
        hide_view(view, direction)
        restore_focus(view)
        return
    end
    view.origin = vim.api.nvim_get_current_win()
    local new_buffer = not terminal.buffer or not vim.api.nvim_buf_is_valid(terminal.buffer)
    if new_buffer then
        terminal.buffer = vim.api.nvim_create_buf(false, true)
        vim.bo[terminal.buffer].bufhidden = "hide"
        vim.bo[terminal.buffer].swapfile = false
    end
    if direction == "float" then
        view.window = vim.api.nvim_open_win(terminal.buffer, true, float_config())
    else
        local height = view.height or math.max(1, math.floor(vim.o.lines * 0.3))
        height = math.min(height, math.max(1, vim.o.lines - vim.o.cmdheight - 3))
        vim.cmd("botright " .. height .. "new")
        view.window = vim.api.nvim_get_current_win()
        local temporary_buffer = vim.api.nvim_get_current_buf()
        vim.api.nvim_win_set_buf(view.window, terminal.buffer)
        if temporary_buffer ~= terminal.buffer and vim.api.nvim_buf_is_valid(temporary_buffer) then
            vim.api.nvim_buf_delete(temporary_buffer, { force = false })
        end
    end
    vim.wo[view.window][0].number = false
    vim.wo[view.window][0].relativenumber = false
    vim.wo[view.window][0].signcolumn = "no"
    vim.wo[view.window][0].foldcolumn = "0"
    if new_buffer then
        local buffer = terminal.buffer
        local started, job = pcall(vim.fn.jobstart, vim.fn.split(vim.o.shell), {
            term = true,
            cwd = vim.fn.getcwd(),
            on_exit = function()
                vim.schedule(function()
                    finish_terminal(terminal, buffer, direction)
                end)
            end,
        })
        if not started or job <= 0 then
            finish_terminal(terminal, buffer, direction)
            vim.notify("Could not start terminal shell: " .. tostring(job), vim.log.levels.ERROR)
            return
        end
        vim.bo[buffer].filetype = "ex_terminal"
    end
    vim.cmd.startinsert()
end

function M.setup()
    vim.keymap.set({ "n", "i", "t" }, "<C-t>", function()
        M.toggle("horizontal")
    end, { desc = "terminal: toggle horizontal" })
    vim.keymap.set("n", "<leader>tf", function()
        M.toggle("float")
    end, { desc = "terminal: toggle float" })
    vim.keymap.set("t", "<Esc>", "<C-\\><C-n>", { desc = "terminal: normal mode" })
    vim.api.nvim_create_user_command("ToggleTerm", function(options)
        local direction = options.args == "" and "horizontal" or options.args
        if not terminals[direction] then
            vim.notify("Usage: ToggleTerm [horizontal|float]", vim.log.levels.ERROR)
            return
        end
        M.toggle(direction)
    end, {
        nargs = "?",
        complete = function() return { "horizontal", "float" } end,
    })
    local group = vim.api.nvim_create_augroup("ex_toggleterm", { clear = true })
    vim.api.nvim_create_autocmd("VimResized", {
        group = group,
        callback = function()
            for _, view in pairs(terminals.float.views) do
                if is_valid_window(view.window) then
                    vim.api.nvim_win_set_config(view.window, float_config())
                end
            end
        end,
    })
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        callback = function(options)
            local closed_window = tonumber(options.match)
            for direction, terminal in pairs(terminals) do
                for _, view in pairs(terminal.views) do
                    if view.window == closed_window then
                        if direction == "horizontal" and is_valid_window(closed_window) then
                            view.height = vim.api.nvim_win_get_height(closed_window)
                        end
                        view.window = nil
                    end
                end
            end
        end,
    })
    vim.api.nvim_create_autocmd("TabClosed", {
        group = group,
        callback = function()
            for _, terminal in pairs(terminals) do
                for tabpage in pairs(terminal.views) do
                    if not vim.api.nvim_tabpage_is_valid(tabpage) then
                        terminal.views[tabpage] = nil
                    end
                end
            end
        end,
    })
end

return M
