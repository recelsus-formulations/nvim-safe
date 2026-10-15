local M = {}
local active
local keyword = vim.regex([[\k]])

local function clear_highlights()
    if not active then
        return
    end
    if vim.api.nvim_win_is_valid(active.window) then
        for _, match in ipairs(active.matches) do
            pcall(vim.fn.matchdelete, match, active.window)
        end
    end
    active = nil
end

local function collect_positions(line, column, direction, count)
    local characters = {}
    local cursor_index = 1
    local byte_column = 0
    for _, character in ipairs(vim.fn.split(line, [[\zs]])) do
        table.insert(characters, {
            text = character,
            column = byte_column + 1,
            keyword = keyword:match_str(character) ~= nil,
        })
        if byte_column <= column then
            cursor_index = #characters
        end
        byte_column = byte_column + #character
    end
    local primary = {}
    local secondary = {}
    local occurrences = {}
    local current_word = characters[cursor_index] and characters[cursor_index].keyword or false
    local first_position
    local second_position
    local function finish_word()
        if not current_word then
            if first_position then
                table.insert(primary, first_position)
            elseif second_position then
                table.insert(secondary, second_position)
            end
        end
        current_word = false
        first_position = nil
        second_position = nil
    end
    local end_index = direction == 1 and #characters or 1
    for index = cursor_index + direction, end_index, direction do
        local character = characters[index]
        if not character.keyword then
            finish_word()
        elseif character.text:match("^[A-Za-z0-9]$") then
            local occurrence = (occurrences[character.text] or 0) + 1
            occurrences[character.text] = occurrence
            if not current_word then
                if occurrence == count and (not first_position or direction == -1) then
                    first_position = character.column
                elseif occurrence == count + 1 and (not second_position or direction == -1) then
                    second_position = character.column
                end
            end
        end
    end
    finish_word()
    return primary, secondary
end

local function show_highlights(motion)
    clear_highlights()
    if vim.bo.buftype ~= "" then
        return
    end
    local line = vim.api.nvim_get_current_line()
    if #line == 0 or #line > 1000 then
        return
    end
    local cursor = vim.api.nvim_win_get_cursor(0)
    if vim.fn.foldclosed(cursor[1]) ~= -1 then
        return
    end
    local direction = (motion == "f" or motion == "t") and 1 or -1
    local primary, secondary = collect_positions(line, cursor[2], direction, vim.v.count1)
    active = { window = vim.api.nvim_get_current_win(), matches = {} }
    local function add_positions(columns, group)
        local positions = {}
        for _, column in ipairs(columns) do
            table.insert(positions, { cursor[1], column, 1 })
        end
        if #positions > 0 then
            table.insert(active.matches, vim.fn.matchaddpos(group, positions, 20))
        end
    end
    add_positions(primary, "ExScopePrimary")
    add_positions(secondary, "ExScopeSecondary")
    vim.cmd.redraw()
end

function M.setup()
    for _, motion in ipairs({ "f", "F", "t", "T" }) do
        vim.keymap.set({ "n", "x", "o" }, motion, function()
            show_highlights(motion)
            return motion
        end, { expr = true, desc = "scope: " .. motion })
    end
    local function set_highlights()
        vim.api.nvim_set_hl(0, "ExScopePrimary", {
            fg = "#afff5f", ctermfg = 155, bold = true, default = true,
        })
        vim.api.nvim_set_hl(0, "ExScopeSecondary", {
            fg = "#5fffff", ctermfg = 81, bold = true, default = true,
        })
    end
    set_highlights()
    local group = vim.api.nvim_create_augroup("ex_scope", { clear = true })
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = group,
        callback = function()
            clear_highlights()
            set_highlights()
        end,
    })
    vim.api.nvim_create_autocmd({ "CursorMoved", "ModeChanged", "BufLeave", "WinLeave", "SafeState" }, {
        group = group,
        callback = clear_highlights,
    })
end

return M
