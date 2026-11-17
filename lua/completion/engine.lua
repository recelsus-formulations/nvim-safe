-- 各ソースの候補を集め、絞り込み・結合して vim.fn.complete() で表示する。
-- 0.12 の 'autocomplete' は LSP (非同期) の結果で他の候補を置き換えてしまうため、全バージョンでこの実装を使う
local M = {}
local compat = require("compat")
local lsp = require("completion.sources.lsp")
local path = require("completion.sources.path")
local buffer = require("completion.sources.buffer")

-- 表示順 (優先度順) と1ソースあたりの最大件数。filter は絞り込みに使う項目
local sources = {
    { name = "lsp", source = lsp, limit = 100, filter = "filter" },
    { name = "path", source = path, limit = 100, filter = "word" },
    { name = "buffer", source = buffer, limit = 20, filter = "word" },
}
local lsp_delay = 30

-- キャンセル直後は、次に文字を入力するまで自動では開かない
M.suppressed = false
local lsp_cache
local lsp_timer
local generation = 0
-- 最後に表示した時点の位置と行の内容
local shown

local function make_context(manual, trigger_character)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()
    local before = line:sub(1, cursor[2])
    local keyword_start = vim.fn.match(before, [[\k*$]])
    return {
        bufnr = vim.api.nvim_get_current_buf(),
        row = cursor[1],
        col = cursor[2],
        line = line,
        before = before,
        keyword_start = keyword_start >= 0 and keyword_start or cursor[2],
        manual = manual,
        trigger_character = trigger_character,
    }
end

local function same_position(left, right)
    return left.bufnr == right.bufnr and left.row == right.row and left.col == right.col
end

local function filter(items, prefix, key, limit)
    if prefix ~= "" then
        items = vim.fn.matchfuzzy(items, prefix, { key = key })
    end
    local result = {}
    for index = 1, math.min(#items, limit) do
        result[index] = items[index]
    end
    return result
end

local function close()
    if vim.fn.pumvisible() == 1 then
        vim.fn.complete(vim.fn.col("."), {})
    end
end

-- 補完メニューの表示中は "ic" などになるため、先頭の "i" で判定する
local function is_insert_mode()
    return vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
end

local function show(context, results)
    if not is_insert_mode() or not same_position(context, make_context(false)) then
        return
    end
    local start
    for _, entry in ipairs(sources) do
        local result = results[entry.name]
        if result and #result.items > 0 and (not start or result.start < start) then
            start = result.start
        end
    end
    local items = {}
    local seen = {}
    for _, entry in ipairs(sources) do
        local result = results[entry.name]
        if result and #result.items > 0 then
            local prefix = context.before:sub(result.start + 1)
            -- 開始位置が他のソースより後ろの場合は、その差分を候補の先頭に補う
            local head = context.before:sub(start + 1, result.start)
            for _, item in ipairs(filter(result.items, prefix, entry.filter, entry.limit)) do
                local word = head .. item.word
                if not seen[word] then
                    seen[word] = true
                    local copy = vim.deepcopy(item)
                    copy.word = word
                    copy.filter = nil
                    copy.sort = nil
                    copy.directory = nil
                    copy.dup = 1
                    copy.icase = 1
                    items[#items + 1] = copy
                end
            end
        end
    end
    local typed = start and context.before:sub(start + 1) or ""
    if #items == 0 or (#items == 1 and items[1].word == typed) then
        close()
        return
    end
    vim.fn.complete(start + 1, items)
    shown = { bufnr = context.bufnr, row = context.row, col = context.col, line = vim.api.nvim_get_current_line() }
end

-- 表示後に内容が変わっていない (表示に伴う TextChangedP など) 場合は true
function M.is_unchanged()
    local cursor = vim.api.nvim_win_get_cursor(0)
    return shown ~= nil and vim.fn.pumvisible() == 1 and shown.bufnr == vim.api.nvim_get_current_buf()
        and shown.row == cursor[1] and shown.col == cursor[2] and shown.line == vim.api.nvim_get_current_line()
end

local function lsp_cache_for(context)
    local cache = lsp_cache
    if cache and not cache.incomplete and cache.bufnr == context.bufnr and cache.row == context.row
        and cache.keyword_start == context.keyword_start and context.col >= cache.col
        and not context.trigger_character and not context.manual
    then
        return cache.result
    end
end

function M.trigger(manual, trigger_character)
    local context = make_context(manual, trigger_character)
    if vim.bo[context.bufnr].buftype ~= "" then
        return
    end
    local prefix = context.before:sub(context.keyword_start + 1)
    local has_path = path.match(context) ~= nil
    if not manual and prefix == "" and not trigger_character and not has_path then
        close()
        return
    end
    generation = generation + 1
    local current = generation
    local results = {}
    path.complete(context, function(result) results.path = result end)
    if prefix ~= "" or manual then
        buffer.complete(context, function(result) results.buffer = result end)
    end
    local cached = lsp_cache_for(context)
    results.lsp = cached
    show(context, results)
    -- LSP への要求は、単語の入力中・トリガー文字・手動の場合のみ (パスの入力中などは要求しない)
    if cached or not (prefix ~= "" or trigger_character or manual) or not lsp.is_available(context.bufnr) then
        return
    end
    -- 入力が続く間は要求をまとめる
    if lsp_timer then
        lsp_timer:stop()
    else
        lsp_timer = compat.uv.new_timer()
    end
    lsp_timer:start(lsp_delay, 0, vim.schedule_wrap(function()
        if current ~= generation or not is_insert_mode() then
            return
        end
        lsp.complete(context, vim.schedule_wrap(function(result)
            if not result or current ~= generation then
                return
            end
            lsp_cache = {
                bufnr = context.bufnr,
                row = context.row,
                col = context.col,
                keyword_start = context.keyword_start,
                incomplete = result.incomplete,
                result = result,
            }
            results.lsp = result
            show(context, results)
        end))
    end))
end

function M.reset()
    generation = generation + 1
    lsp_cache = nil
    shown = nil
    M.suppressed = false
    if lsp_timer then
        lsp_timer:stop()
    end
end

return M
