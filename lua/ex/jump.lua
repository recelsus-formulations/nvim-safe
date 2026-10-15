local M = {}
local namespace = vim.api.nvim_create_namespace("ex_jump")
local alphabet = "abcdefghijklmnopqrstuvwxyz"
local active

local function collect_targets(window, buffer)
    local cursor = vim.api.nvim_win_get_cursor(window)
    local first_line = vim.fn.line("w0")
    local last_line = vim.fn.line("w$")
    local position = vim.api.nvim_win_get_position(window)
    local right_edge = position[2] + vim.api.nvim_win_get_width(window)
    local bottom_edge = position[1] + vim.api.nvim_win_get_height(window)
    local cursor_screen = vim.fn.screenpos(window, cursor[1], cursor[2] + 1)
    local word_pattern = vim.regex([[\k\+]])
    local targets = {}
    for row = first_line, last_line do
        if vim.fn.foldclosed(row) == -1 then
            local line = vim.api.nvim_buf_get_lines(buffer, row - 1, row, false)[1]
            local offset = 0
            while offset < #line do
                local start_column, end_column = word_pattern:match_str(line:sub(offset + 1))
                if not start_column then
                    break
                end
                local column = offset + start_column
                local screen = vim.fn.screenpos(window, row, column + 1)
                if screen.row > position[1] and screen.row <= bottom_edge
                    and screen.col > position[2] and screen.col <= right_edge
                    and not (row == cursor[1] and column == cursor[2])
                then
                    table.insert(targets, {
                        row = row - 1,
                        column = column,
                        distance = math.abs(screen.row - cursor_screen.row) * 10
                            + math.abs(screen.col - cursor_screen.col),
                    })
                end
                offset = offset + end_column
            end
        end
    end
    table.sort(targets, function(left, right)
        if left.distance ~= right.distance then
            return left.distance < right.distance
        end
        if left.row ~= right.row then
            return left.row < right.row
        end
        return left.column < right.column
    end)
    return targets
end

local function make_labels(count)
    local labels = {}
    for index = 1, math.min(count, #alphabet) do
        labels[index] = alphabet:sub(index, index)
    end
    while #labels < count do
        local shortest = #labels
        for index = #labels - 1, 1, -1 do
            if #labels[index] < #labels[shortest] then
                shortest = index
            end
        end
        local prefix = table.remove(labels, shortest)
        local children = math.min(#alphabet, count - #labels)
        for index = children, 1, -1 do
            table.insert(labels, shortest, prefix .. alphabet:sub(index, index))
        end
    end
    table.sort(labels, function(left, right)
        if #left ~= #right then
            return #left < #right
        end
        return left < right
    end)
    return labels
end

local function select_target(targets)
    local candidates = targets
    local prefix = ""
    while #candidates > 1 do
        active.targets = candidates
        active.prefix_length = #prefix
        vim.cmd("redraw!")
        local ok, key = pcall(vim.fn.getcharstr)
        if not ok or not key:match("^[a-zA-Z]$") then
            return nil
        end
        if not vim.api.nvim_win_is_valid(active.window)
            or vim.api.nvim_get_current_win() ~= active.window
            or vim.api.nvim_win_get_buf(active.window) ~= active.buffer
            or vim.api.nvim_buf_get_changedtick(active.buffer) ~= active.changedtick
        then
            return nil
        end
        prefix = prefix .. key:lower()
        local remaining = {}
        for _, target in ipairs(candidates) do
            if target.label:sub(1, #prefix) == prefix then
                table.insert(remaining, target)
            end
        end
        candidates = remaining
    end
    return candidates[1]
end

function M.words()
    if active then
        return
    end
    local window = vim.api.nvim_get_current_win()
    local buffer = vim.api.nvim_get_current_buf()
    if vim.bo[buffer].buftype ~= "" then
        return
    end
    local targets = collect_targets(window, buffer)
    if #targets == 0 then
        return
    end
    local labels = make_labels(#targets)
    for index, target in ipairs(targets) do
        target.label = labels[index]
    end
    active = {
        window = window,
        buffer = buffer,
        changedtick = vim.api.nvim_buf_get_changedtick(buffer),
        targets = targets,
        prefix_length = 0,
    }
    local ok, target = pcall(select_target, targets)
    active = nil
    vim.cmd("redraw!")
    if not ok then
        vim.notify(tostring(target), vim.log.levels.ERROR, { title = "Jump" })
        return
    end
    if target and vim.api.nvim_win_is_valid(window) then
        vim.cmd("normal! m'")
        vim.api.nvim_win_set_cursor(window, { target.row + 1, target.column })
    end
end

function M.setup()
    vim.keymap.set("n", "<C-f>", M.words, { desc = "jump: visible word" })
    local function set_highlights()
        vim.api.nvim_set_hl(0, "ExJumpLabel", { fg = "#ffcc66", bold = true, default = true })
    end
    set_highlights()
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("ex_jump", { clear = true }),
        callback = set_highlights,
    })
    vim.api.nvim_set_decoration_provider(namespace, {
        on_win = function(_, window, buffer)
            return active ~= nil and window == active.window and buffer == active.buffer
        end,
        on_range = function(_, _, buffer, start_row, start_column, end_row, end_column)
            if not active then
                return
            end
            for _, target in ipairs(active.targets) do
                if (target.row > start_row or (target.row == start_row and target.column >= start_column))
                    and (target.row < end_row or (target.row == end_row and target.column < end_column))
                then
                    vim.api.nvim_buf_set_extmark(buffer, namespace, target.row, target.column, {
                        virt_text = { { target.label:sub(active.prefix_length + 1), "ExJumpLabel" } },
                        virt_text_pos = "overlay",
                        hl_mode = "combine",
                        priority = 200,
                        ephemeral = true,
                    })
                end
            end
        end,
    })
end

return M
