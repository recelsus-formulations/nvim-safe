local M = {}

local function start_highlighting(buffer)
    if not vim.api.nvim_buf_is_valid(buffer) or not vim.api.nvim_buf_is_loaded(buffer) then
        return
    end
    if vim.b[buffer].ex_treesitter then
        vim.treesitter.stop(buffer)
        vim.b[buffer].ex_treesitter = nil
    end
    if vim.bo[buffer].buftype ~= "" and vim.bo[buffer].buftype ~= "help" then
        return
    end
    local language = vim.treesitter.language.get_lang(vim.bo[buffer].filetype)
    if not language then
        return
    end
    local loaded, available = pcall(vim.treesitter.language.add, language)
    if not loaded or not available then
        return
    end
    local queried, query = pcall(vim.treesitter.query.get, language, "highlights")
    if not queried or not query then
        return
    end
    local syntax = vim.bo[buffer].syntax
    local started = pcall(vim.treesitter.start, buffer, language)
    if started then
        vim.b[buffer].ex_treesitter = true
    else
        pcall(vim.treesitter.stop, buffer)
        vim.bo[buffer].syntax = syntax
    end
end

function M.setup()
    vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("ex_treesitter", { clear = true }),
        callback = function(options) start_highlighting(options.buf) end,
    })
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        start_highlighting(buffer)
    end
end

return M
