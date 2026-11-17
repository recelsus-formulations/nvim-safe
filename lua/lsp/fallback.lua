-- vim.lsp.config / vim.lsp.enable (0.11+) が無い環境向けに、vim.lsp.start で同じ動作を再現する。
-- 対応するのは lsp/servers の spec で使う範囲 (cmd・filetypes・root_markers と vim.lsp.start が扱う項目)
local M = {}
local compat = require("compat")
local configs = {}
local enabled = {}
local group

function M.config(name, config)
    configs[name] = vim.deepcopy(config)
end

local function find_root(buffer, markers)
    if not markers or #markers == 0 then
        return nil
    end
    return compat.find_root(buffer, markers)
end

local function attach(buffer)
    if not vim.api.nvim_buf_is_valid(buffer) or vim.bo[buffer].buftype ~= "" then
        return
    end
    local filetype = vim.bo[buffer].filetype
    for name in pairs(enabled) do
        local config = configs[name]
        if config and vim.tbl_contains(config.filetypes or {}, filetype) then
            local start_config = vim.deepcopy(config)
            start_config.name = name
            if type(config.root_dir) == "function" then
                local resolved_root
                config.root_dir(buffer, function(root) resolved_root = root end)
                if resolved_root then
                    start_config.root_dir = resolved_root
                else
                    start_config = nil
                end
            else
                start_config.root_dir = find_root(buffer, config.root_markers)
            end
            if start_config then
                start_config.filetypes = nil
                start_config.root_markers = nil
                -- Pass the resolved configuration to command functions on older Neovim versions.
                if type(config.cmd) == "function" then
                    start_config.cmd = function(dispatchers)
                        return config.cmd(dispatchers, start_config)
                    end
                end
                vim.lsp.start(start_config, { bufnr = buffer })
            end
        end
    end
end

function M.enable(names)
    for _, name in ipairs(type(names) == "table" and names or { names }) do
        enabled[name] = true
    end
    if not group then
        group = vim.api.nvim_create_augroup("ex_lsp_enable", { clear = true })
        vim.api.nvim_create_autocmd("FileType", {
            group = group,
            callback = function(options) attach(options.buf) end,
        })
    end
    -- 0.11+ と同様に、起動後に有効にした場合は既存バッファにも接続する
    if vim.v.vim_did_enter == 1 then
        for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(buffer) then
                attach(buffer)
            end
        end
    end
end

return M
