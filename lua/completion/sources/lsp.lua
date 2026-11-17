-- LSP (textDocument/completion)。接続中の全クライアントに要求し、結果をまとめて返す
local M = {}
local compat = require("compat")
local item_kinds = vim.lsp.protocol.CompletionItemKind
local pending = {}

local function clients(bufnr)
    local result = {}
    for _, client in ipairs(compat.lsp_clients({ bufnr = bufnr })) do
        if client.server_capabilities and client.server_capabilities.completionProvider then
            result[#result + 1] = client
        end
    end
    return result
end

function M.is_available(bufnr)
    return #clients(bufnr) > 0
end

function M.trigger_characters(bufnr)
    local characters = {}
    for _, client in ipairs(clients(bufnr)) do
        for _, character in ipairs(client.server_capabilities.completionProvider.triggerCharacters or {}) do
            characters[character] = true
        end
    end
    return characters
end

local function documentation(entry)
    local parts = {}
    if type(entry.detail) == "string" and entry.detail ~= "" then
        parts[#parts + 1] = entry.detail
    end
    local value = type(entry.documentation) == "table" and entry.documentation.value or entry.documentation
    if type(value) == "string" and value ~= "" then
        parts[#parts + 1] = value
    end
    return table.concat(parts, "\n\n")
end

-- スニペットを展開できない場合に挿入する文字列 (${1:name} → name、$1 などは削除)
local function strip_snippet(text)
    text = text:gsub("%${%d+:([^}]*)}", "%1")
    text = text:gsub("%${%d+|([^,|}]*)[^}]*}", "%1")
    text = text:gsub("%${%d+}", "")
    text = text:gsub("%$%d+", "")
    return text
end

-- textEdit の範囲がカーソル行にあれば、その開始位置 (バイト) を返す。無ければ単語の先頭
local function item_start(client, entry, context)
    local edit = entry.textEdit
    local range = type(edit) == "table" and (edit.range or edit.insert)
    if range and range.start.line == context.row - 1 then
        local start = compat.lsp_byte_index(context.line, range.start.character, client.offset_encoding)
        if start <= context.col then
            return start
        end
    end
    return context.keyword_start
end

local function to_item(client, entry, context)
    local text = (type(entry.textEdit) == "table" and entry.textEdit.newText) or entry.insertText or entry.label
    local snippet = entry.insertTextFormat == 2 and text or nil
    local word = snippet and strip_snippet(text) or text
    word = vim.split(word, "\n", { plain = true })[1]
    return {
        start = item_start(client, entry, context),
        word = word,
        abbr = entry.label,
        kind = item_kinds[entry.kind] or "",
        menu = "[LSP]",
        info = documentation(entry),
        filter = entry.filterText or entry.label,
        sort = entry.sortText or entry.label,
        user_data = {
            source = "lsp",
            client_id = client.id,
            snippet = snippet,
            additional_text_edits = entry.additionalTextEdits,
        },
    }
end

-- callback({ start, items, incomplete }) は全クライアントの応答が揃った時点で1回呼ばれる
function M.complete(context, callback)
    local targets = clients(context.bufnr)
    if #targets == 0 then
        callback(nil)
        return
    end
    local remaining = #targets
    local items = {}
    local incomplete = false
    -- 候補ごとに置き換え開始位置が異なる場合は、最も前の位置に揃えて差分を候補の先頭に補う
    local function done()
        remaining = remaining - 1
        if remaining > 0 then
            return
        end
        local start = context.keyword_start
        for _, item in ipairs(items) do
            start = math.min(start, item.start)
        end
        for _, item in ipairs(items) do
            local head = context.line:sub(start + 1, item.start)
            item.word = head .. item.word
            item.filter = head .. item.filter
            item.start = nil
        end
        callback({ start = start, items = items, incomplete = incomplete })
    end
    for _, client in ipairs(targets) do
        if pending[client.id] then
            pcall(compat.lsp_cancel_request, client, pending[client.id])
            pending[client.id] = nil
        end
        local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
        params.context = context.trigger_character
            and { triggerKind = 2, triggerCharacter = context.trigger_character }
            or { triggerKind = 1 }
        local request_id
        local ok, sent, id = pcall(compat.lsp_request, client, "textDocument/completion", params,
            function(err, result)
                if pending[client.id] == request_id then
                    pending[client.id] = nil
                end
                if not err and type(result) == "table" then
                    incomplete = incomplete or result.isIncomplete == true
                    for _, entry in ipairs(result.items or result) do
                        items[#items + 1] = to_item(client, entry, context)
                    end
                end
                done()
            end, context.bufnr)
        if ok and sent then
            request_id = id
            pending[client.id] = request_id
        else
            done()
        end
    end
end

return M
