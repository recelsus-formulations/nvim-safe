-- 入力中の自動補完 (LSP・パス・バッファ内の単語)。表示は組み込みのポップアップメニューを使う
local M = {}
local engine = require("completion.engine")
local lsp = require("completion.sources.lsp")
local buffer = require("completion.sources.buffer")

-- <CR> で確定した場合だけ、LSP のスニペット展開・追加の編集 (import など) を行う
local confirming = false
-- 文字の入力 (InsertCharPre) があった場合だけ自動で開く
local typed_character

local function is_selected()
    return vim.fn.pumvisible() == 1 and vim.fn.complete_info({ "selected" }).selected ~= -1
end

-- 既存の挿入モードのマッピング (pairs の <BS> など) を、補完で扱わない場合に呼び出す
local function fallback(key)
    local mapping = vim.fn.maparg(key, "i", false, true)
    if vim.tbl_isempty(mapping) then
        return function() return key end
    end
    if mapping.callback and mapping.expr == 1 then
        return mapping.callback
    end
    if mapping.rhs and mapping.expr ~= 1 then
        return function() return mapping.rhs end
    end
    return function() return key end
end

local function map(key, handler)
    local original = fallback(key)
    vim.keymap.set("i", key, function()
        return handler(original)
    end, { expr = true, replace_keycodes = true, desc = "completion: " .. key })
end

local function cancel(keys)
    engine.suppressed = true
    return keys
end

local function apply_confirmed(item)
    local data = type(item) == "table" and item.user_data
    if type(data) ~= "table" or data.source ~= "lsp" then
        return
    end
    local bufnr = vim.api.nvim_get_current_buf()
    local client = vim.lsp.get_client_by_id(data.client_id)
    if type(data.snippet) == "string" and vim.snippet then
        local cursor = vim.api.nvim_win_get_cursor(0)
        local start = cursor[2] - #item.word
        if start >= 0 then
            vim.api.nvim_buf_set_text(bufnr, cursor[1] - 1, start, cursor[1] - 1, cursor[2], { "" })
            vim.api.nvim_win_set_cursor(0, { cursor[1], start })
            vim.snippet.expand(data.snippet)
        end
    end
    if type(data.additional_text_edits) == "table" and #data.additional_text_edits > 0 and client then
        vim.lsp.util.apply_text_edits(data.additional_text_edits, bufnr, client.offset_encoding)
    end
end

local function set_options()
    vim.opt.completeopt = { "menuone", "noselect" }
    -- 候補の説明を横に表示する ("popup" は 0.10+)
    pcall(function() vim.opt.completeopt:append("popup") end)
    vim.opt.shortmess:append("c")
    vim.opt.pumheight = 15
end

local function set_keymaps()
    local function select(next_key)
        return function(original)
            if vim.fn.pumvisible() == 1 then
                return next_key
            end
            return original()
        end
    end
    map("<Tab>", select("<C-n>"))
    map("<S-Tab>", select("<C-p>"))
    map("<C-n>", select("<C-n>"))
    map("<C-p>", select("<C-p>"))
    map("<CR>", function(original)
        if is_selected() then
            confirming = true
            return "<C-y>"
        end
        if vim.fn.pumvisible() == 1 then
            return "<C-e>" .. original()
        end
        return original()
    end)
    -- キャンセルして入力していた文字に戻す
    map("<C-e>", function(original)
        if vim.fn.pumvisible() == 1 then
            return cancel("<C-e>")
        end
        return original()
    end)
    map("<BS>", function(original)
        if is_selected() then
            return cancel("<C-e>")
        end
        return original()
    end)
    map("<Esc>", function(original)
        if vim.fn.pumvisible() == 1 then
            return cancel("<C-e>") .. original()
        end
        return original()
    end)
    -- 手動で開く (端末によって Ctrl-Space は <C-@> として届く)
    for _, key in ipairs({ "<C-Space>", "<C-@>" }) do
        vim.keymap.set("i", key, function()
            engine.suppressed = false
            vim.schedule(function() engine.trigger(true) end)
        end, { desc = "completion: open" })
    end
end

local function set_autocmds()
    local group = vim.api.nvim_create_augroup("ex_completion", { clear = true })
    vim.api.nvim_create_autocmd("InsertCharPre", {
        group = group,
        callback = function()
            engine.suppressed = false
            typed_character = vim.v.char
        end,
    })
    vim.api.nvim_create_autocmd({ "TextChangedI", "TextChangedP" }, {
        group = group,
        callback = function()
            local character = typed_character
            typed_character = nil
            if engine.suppressed or vim.bo.buftype ~= "" or is_selected() then
                return
            end
            -- 文字の入力時、または表示中に削除した場合に候補を更新する
            if not character and (vim.fn.pumvisible() == 0 or engine.is_unchanged()) then
                return
            end
            local trigger = character and lsp.trigger_characters(0)[character] and character or nil
            engine.trigger(false, trigger)
        end,
    })
    vim.api.nvim_create_autocmd("CompleteDone", {
        group = group,
        callback = function()
            if not confirming then
                return
            end
            confirming = false
            local item = vim.v.completed_item
            vim.schedule(function() apply_confirmed(item) end)
        end,
    })
    vim.api.nvim_create_autocmd("InsertLeave", {
        group = group,
        callback = function()
            typed_character = nil
            engine.reset()
        end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
        group = group,
        callback = function(options) buffer.forget(options.buf) end,
    })
end

-- pairs などの挿入モードのマッピングより後に呼ぶ (それらを補完で扱わない場合に呼び出すため)
function M.setup()
    set_options()
    set_keymaps()
    set_autocmds()
end

return M
