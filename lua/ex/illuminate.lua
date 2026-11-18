local M = {}
local active
local generation = 0
local keyword = vim.regex([[\k]])

local function clear_match()
    if active and vim.api.nvim_win_is_valid(active.window) then
        pcall(vim.fn.matchdelete, active.id, active.window)
    end
    active = nil
end

local function current_word()
    if vim.bo.buftype ~= "" then
        return nil
    end
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()
    local character = vim.fn.strcharpart(line:sub(cursor[2] + 1), 0, 1)
    if character == "" or not keyword:match_str(character) then
        return nil
    end
    local word = vim.fn.expand("<cword>")
    return word ~= "" and word or nil
end

local function refresh()
    generation = generation + 1
    local current = generation
    clear_match()
    if vim.api.nvim_get_mode().mode ~= "n" then
        return
    end
    local word = current_word()
    if not word then
        return
    end
    local window = vim.api.nvim_get_current_win()
    local buffer = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(window)
    vim.defer_fn(function()
        if current ~= generation or not vim.api.nvim_win_is_valid(window)
            or vim.api.nvim_get_current_win() ~= window or vim.api.nvim_get_current_buf() ~= buffer
            or vim.api.nvim_get_mode().mode ~= "n"
        then
            return
        end
        local position = vim.api.nvim_win_get_cursor(window)
        if position[1] ~= cursor[1] or position[2] ~= cursor[2] then
            return
        end
        local pattern = [[\V\<]] .. vim.fn.escape(word, [[\]]) .. [[\>]]
        local ok, id = pcall(vim.fn.matchadd, "ExWordReference", pattern, 5)
        if ok then
            active = { window = window, id = id }
        end
    end, 100)
end

function M.setup()
    local function set_highlight()
        vim.api.nvim_set_hl(0, "ExWordReference", { bg = "#3c4758", default = true })
    end
    set_highlight()
    local group = vim.api.nvim_create_augroup("ex_illuminate", { clear = true })
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = group, callback = set_highlight,
    })
    vim.api.nvim_create_autocmd({ "CursorMoved", "BufEnter", "WinEnter", "InsertLeave" }, {
        group = group, callback = refresh,
    })
    vim.api.nvim_create_autocmd({ "InsertEnter", "BufLeave", "WinLeave", "TextChanged" }, {
        group = group,
        callback = function()
            generation = generation + 1
            clear_match()
        end,
    })
    refresh()
end

return M
