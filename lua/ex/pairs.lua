local M = {}
local opening_pairs = {
    ["("] = ")",
    ["["] = "]",
    ["{"] = "}",
    ['"'] = '"',
    ["'"] = "'",
    ["`"] = "`",
}
local closing_pairs = { [")"] = true, ["]"] = true, ["}"] = true }

local function get_context()
    local line = vim.api.nvim_get_current_line()
    local column = vim.api.nvim_win_get_cursor(0)[2]
    return line:sub(1, column), line:sub(column + 1, column + 1)
end

local function is_enabled()
    return vim.bo.buftype == "" and not vim.o.paste
end

local function is_escaped(text)
    local count = 0
    for index = #text, 1, -1 do
        if text:sub(index, index) ~= "\\" then
            break
        end
        count = count + 1
    end
    return count % 2 == 1
end

local function is_inside_quote(text, quote)
    local inside = false
    local escaped = false
    for index = 1, #text do
        local character = text:sub(index, index)
        if character == quote and not escaped then
            inside = not inside
        end
        escaped = character == "\\" and not escaped
    end
    return inside
end

local function insert_character(character)
    if not is_enabled() then
        return character
    end
    local before, next_character = get_context()
    local closing = opening_pairs[character]
    local is_quote = closing == character
    if is_quote and is_escaped(before) then
        return character
    end
    if next_character == character and (is_quote or closing_pairs[character]) then
        return "<C-g>U<Right>"
    end
    if not closing then
        return character
    end
    if is_quote and (before:match("[%w_]$") or is_inside_quote(before, character)) then
        return character
    end
    if next_character ~= "" and not next_character:match("[%s%)%]%},;:]") then
        return character
    end
    return character .. closing .. "<C-g>U<Left>"
end

local function backspace()
    if not is_enabled() then
        return "<BS>"
    end
    local before, next_character = get_context()
    local previous_character = before:sub(-1)
    if opening_pairs[previous_character] == next_character then
        local is_quote = previous_character == next_character
        if not is_quote or not is_escaped(before:sub(1, -2)) then
            return "<BS><Del>"
        end
    end
    return "<BS>"
end

function M.setup()
    local function map(key, callback, description)
        vim.keymap.set("i", key, callback, { expr = true, replace_keycodes = true, desc = description })
    end
    for opening in pairs(opening_pairs) do
        map(opening, function() return insert_character(opening) end, "pairs: " .. opening)
    end
    for closing in pairs(closing_pairs) do
        map(closing, function() return insert_character(closing) end, "pairs: " .. closing)
    end
    map("<BS>", backspace, "pairs: delete empty pair")
end

return M
