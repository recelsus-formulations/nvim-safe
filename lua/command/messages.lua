local M = {}
local compat = require("compat")
local buffer_name = "ex://messages"

local function message_lines()
    local output = vim.fn.execute("messages")
    local lines = vim.split(output, "\n", { plain = true, trimempty = true })
    return #lines > 0 and lines or { "No messages" }
end

local function copy_lines(lines)
    vim.fn.setreg("+", lines, "V")
end

local function refresh(buffer)
    vim.bo[buffer].modifiable = true
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, message_lines())
    vim.bo[buffer].modifiable = false
end

local function get_buffer()
    local buffer = vim.fn.bufnr(buffer_name)
    if buffer ~= -1 and vim.api.nvim_buf_is_valid(buffer) then
        return buffer
    end
    buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buffer, buffer_name)
    vim.bo[buffer].bufhidden = "hide"
    vim.bo[buffer].swapfile = false
    vim.bo[buffer].filetype = "ex_messages"
    vim.keymap.set("n", "y", function()
        copy_lines({ vim.api.nvim_get_current_line() })
    end, { buffer = buffer, silent = true, desc = "messages: copy line" })
    vim.keymap.set("n", "Y", function()
        copy_lines(vim.api.nvim_buf_get_lines(buffer, 0, -1, false))
    end, { buffer = buffer, silent = true, desc = "messages: copy all" })
    vim.keymap.set("n", "R", function()
        refresh(buffer)
    end, { buffer = buffer, silent = true, desc = "messages: refresh" })
    vim.keymap.set("n", "q", "<Cmd>close<CR>", {
        buffer = buffer, silent = true, desc = "messages: close",
    })
    return buffer
end

function M.open()
    local buffer = get_buffer()
    refresh(buffer)
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_buf(window) == buffer then
            vim.api.nvim_set_current_win(window)
            return
        end
    end
    vim.cmd("botright split")
    vim.api.nvim_win_set_buf(0, buffer)
    compat.set_window_local(0, "number", false)
    compat.set_window_local(0, "relativenumber", false)
    compat.set_window_local(0, "signcolumn", "no")
    compat.set_window_local(0, "wrap", true)
end

function M.setup()
    vim.api.nvim_create_user_command("Messages", M.open, {
        desc = "Show copyable message history",
    })
end

return M
