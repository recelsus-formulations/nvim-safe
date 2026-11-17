local M = {}

local function close_window(window)
    if vim.api.nvim_win_is_valid(window) then
        vim.api.nvim_win_close(window, true)
    end
end

local function open_hover_split(hover_window, source_buffer, split_command)
    if not vim.api.nvim_win_is_valid(hover_window) then
        return
    end

    local hover_buffer = vim.api.nvim_win_get_buf(hover_window)
    local lines = vim.api.nvim_buf_get_lines(hover_buffer, 0, -1, false)
    local cursor = vim.api.nvim_win_get_cursor(hover_window)
    local filetype = vim.bo[hover_buffer].filetype
    local split_buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(split_buffer, 0, -1, false, lines)
    vim.bo[split_buffer].filetype = filetype
    vim.bo[split_buffer].modifiable = false

    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if window ~= hover_window and vim.api.nvim_win_get_buf(window) == source_buffer then
            vim.api.nvim_set_current_win(window)
            break
        end
    end
    close_window(hover_window)
    vim.cmd(split_command)
    vim.api.nvim_win_set_buf(0, split_buffer)
    vim.api.nvim_win_set_cursor(0, cursor)
end

local function configure_hover_window(window)
    if not vim.api.nvim_win_is_valid(window) then
        return
    end
    local ok, source_buffer = pcall(vim.api.nvim_win_get_var, window, "textDocument/hover")
    if not ok or not vim.api.nvim_buf_is_valid(source_buffer) then
        return
    end

    local hover_buffer = vim.api.nvim_win_get_buf(window)
    vim.keymap.set("n", "<Esc>", function()
        close_window(window)
    end, { buffer = hover_buffer, silent = true, desc = "lsp: close hover" })
    vim.keymap.set("n", "<C-v>", function()
        open_hover_split(window, source_buffer, "vsplit")
    end, { buffer = hover_buffer, silent = true, desc = "lsp: hover vertical split" })
    vim.keymap.set("n", "<C-x>", function()
        open_hover_split(window, source_buffer, "split")
    end, { buffer = hover_buffer, silent = true, desc = "lsp: hover horizontal split" })
    vim.api.nvim_set_current_win(window)
end

local function show_hover()
    local diagnostic_buffer, diagnostic_window = vim.diagnostic.open_float({
        scope = "line",
        border = "rounded",
        focusable = true,
        max_width = 120,
        max_height = 30,
        title = " LSP Diagnostics ",
        title_pos = "center",
    })
    if diagnostic_window then
        vim.keymap.set("n", "<Esc>", function()
            close_window(diagnostic_window)
        end, { buffer = diagnostic_buffer, silent = true, desc = "lsp: close diagnostics" })
        vim.api.nvim_set_current_win(diagnostic_window)
        return
    end

    vim.lsp.buf.hover({
        border = "rounded",
        focusable = true,
        max_width = 120,
        max_height = 30,
        title = " LSP Hover ",
        title_pos = "center",
    })
end

function M.setup()
    local group = vim.api.nvim_create_augroup("user_lsp_hover", { clear = true })
    vim.api.nvim_create_autocmd("WinNew", {
        group = group,
        callback = function()
            local window = vim.api.nvim_get_current_win()
            vim.schedule(function()
                configure_hover_window(window)
            end)
        end,
    })
    vim.api.nvim_create_autocmd("LspAttach", {
        group = group,
        callback = function(args)
            vim.keymap.set("n", "K", show_hover, {
                buffer = args.buf,
                silent = true,
                desc = "lsp: hover",
            })
        end,
    })
    vim.keymap.set("n", "<leader>le", vim.diagnostic.open_float, {
        silent = true,
        desc = "lsp: diag float",
    })
    vim.keymap.set("n", "[d", function()
        vim.diagnostic.jump({ count = -1, float = true })
    end, { silent = true, desc = "lsp: prev diag" })
    vim.keymap.set("n", "]d", function()
        vim.diagnostic.jump({ count = 1, float = true })
    end, { silent = true, desc = "lsp: next diag" })
end

return M
