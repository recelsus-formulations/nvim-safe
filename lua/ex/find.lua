local M = {}
local active
local namespace = vim.api.nvim_create_namespace("ex_find_matches")
local maximum_results = 500
local maximum_bytes = 1024 * 1024
local excluded_directories = { [".git"] = true, [".cache"] = true, Library = true, node_modules = true }

local function is_active(state, request)
    return active == state and not state.closed and (not request or state.request == request)
        and vim.api.nvim_buf_is_valid(state.input_buffer)
        and vim.api.nvim_win_is_valid(state.input_window)
end

local function stop_search(state)
    state.request = nil
    state.revision = state.revision + 1
end

local function close(state)
    if state.closed then
        return
    end
    state.closed = true
    stop_search(state)
    if active == state then
        active = nil
    end
    vim.cmd.stopinsert()
    for _, window in ipairs({ state.input_window, state.results_window, state.preview_window }) do
        if vim.api.nvim_win_is_valid(window) then
            vim.api.nvim_win_close(window, true)
        end
    end
    for _, buffer in ipairs({ state.input_buffer, state.results_buffer, state.preview_buffer }) do
        if vim.api.nvim_buf_is_valid(buffer) then
            vim.api.nvim_buf_delete(buffer, { force = true })
        end
    end
    if vim.api.nvim_win_is_valid(state.origin) then
        vim.api.nvim_set_current_win(state.origin)
    end
end

local function match_ranges(line, pattern)
    local ranges = {}
    local offset = 0
    local attempts = 0
    while offset <= #line and attempts < 100 do
        attempts = attempts + 1
        local match = vim.fn.matchstrpos(line, pattern, offset, 1)
        local first, last = match[2], match[3]
        if first < 0 then
            break
        end
        if last > first then
            table.insert(ranges, { first, last })
            offset = last
        else
            offset = first + math.max(1, #vim.fn.strcharpart(line:sub(first + 1), 0, 1))
        end
    end
    return ranges
end

local function highlight_ranges(buffer, row, offset, ranges, start)
    start = start or 0
    for _, range in ipairs(ranges) do
        if range[2] > start then
            vim.api.nvim_buf_set_extmark(buffer, namespace, row, offset + math.max(0, range[1] - start), {
                end_col = offset + range[2] - start, hl_group = "ExFindMatch", priority = 200,
            })
        end
    end
end

local function set_preview(state, entry, lines, message)
    if not is_active(state) or state.preview_entry ~= entry or not state.preview_window
        or not vim.api.nvim_win_is_valid(state.preview_window)
    then
        return
    end
    local first = 1
    local selected_row = 1
    local display = { message or "Select a result" }
    if lines and entry then
        local context = math.max(20, vim.api.nvim_win_get_height(state.preview_window) * 2)
        first = math.max(1, entry.row - context)
        local last = math.min(#lines, entry.row + context)
        display = {}
        for row = first, last do
            table.insert(display, lines[row])
        end
        if #display == 0 then
            display = { "File changed: matching line is no longer available" }
        else
            selected_row = entry.row - first + 1
        end
    end
    local buffer = state.preview_buffer
    vim.bo[buffer].modifiable = true
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, display)
    vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
    vim.bo[buffer].modifiable = false
    vim.wo[state.preview_window][0].statuscolumn = lines and ("%{v:lnum + " .. (first - 1) .. "} ") or ""
    vim.bo[buffer].syntax = lines and (vim.filetype.match({ filename = entry.path }) or "") or ""
    if lines and state.pattern_text then
        for row, line in ipairs(display) do
            highlight_ranges(buffer, row - 1, 0, match_ranges(line, state.pattern_text))
        end
        selected_row = math.min(selected_row, #display)
        local column = math.min(entry.column, #display[selected_row])
        vim.api.nvim_win_set_cursor(state.preview_window, { selected_row, column })
        vim.api.nvim_buf_set_extmark(buffer, namespace, selected_row - 1, 0, {
            line_hl_group = "ExFindCurrent", priority = 100,
        })
        vim.api.nvim_win_call(state.preview_window, function()
            vim.cmd("normal! zz")
            local target_column = vim.fn.strdisplaywidth(display[selected_row]:sub(1, column))
            local width = vim.api.nvim_win_get_width(state.preview_window)
            vim.fn.winrestview({ leftcol = math.max(0, target_column - math.floor(width / 2)) })
        end)
    end
    vim.api.nvim_win_set_config(state.preview_window, {
        title = entry and (" " .. entry.relative:gsub("[%c]", " ") .. ":" .. entry.row .. " ") or " Preview ",
    })
end

local function update_preview(state)
    if not state.preview_window or not vim.api.nvim_win_is_valid(state.preview_window) then
        return
    end
    local entry = state.entries[state.selection]
    if state.preview_entry == entry and entry then
        return
    end
    state.preview_entry = entry
    if not entry then
        set_preview(state, nil)
        return
    end
    if state.preview_cache and state.preview_cache.path == entry.path then
        set_preview(state, entry, state.preview_cache.lines)
        return
    end
    set_preview(state, entry, nil, "Loading...")
    vim.uv.fs_open(entry.path, "r", 0, vim.schedule_wrap(function(open_error, descriptor)
        if not descriptor then
            set_preview(state, entry, nil, "Could not open file")
            return
        end
        if not is_active(state) or state.preview_entry ~= entry then
            vim.uv.fs_close(descriptor)
            return
        end
        vim.uv.fs_fstat(descriptor, vim.schedule_wrap(function(stat_error, stat)
            if not is_active(state) or state.preview_entry ~= entry or stat_error or not stat
                or stat.type ~= "file" or stat.size > maximum_bytes
            then
                vim.uv.fs_close(descriptor)
                set_preview(state, entry, nil, "Preview unavailable")
                return
            end
            vim.uv.fs_read(descriptor, stat.size, 0, vim.schedule_wrap(function(read_error, data)
                vim.uv.fs_close(descriptor)
                if not is_active(state) or state.preview_entry ~= entry then
                    return
                end
                if read_error or not data or data:find("\0", 1, true) then
                    set_preview(state, entry, nil, "Could not read text")
                    return
                end
                data = data:gsub("^\239\187\191", ""):gsub("\r\n", "\n")
                local lines = vim.split(data, "\n", { plain = true })
                if data:sub(-1) == "\n" then
                    table.remove(lines)
                end
                state.preview_cache = { path = entry.path, lines = lines }
                set_preview(state, entry, lines)
            end))
        end))
    end))
end

local function render(state, message)
    if not is_active(state) or not vim.api.nvim_win_is_valid(state.results_window) then
        return
    end
    local lines = {}
    local highlights = {}
    local width = vim.api.nvim_win_get_width(state.results_window)
    for _, entry in ipairs(state.entries) do
        local prefix = entry.relative .. ":" .. entry.row .. ":" .. (entry.column + 1) .. ": "
        local context = math.max(4, math.floor((width - vim.fn.strdisplaywidth(prefix) - 4) / 3))
        local start = math.max(0, entry.column - context)
        while start > 0 and entry.text:byte(start + 1) >= 128 and entry.text:byte(start + 1) < 192 do
            start = start - 1
        end
        prefix = prefix .. (start > 0 and "... " or "")
        local text = prefix .. entry.text:sub(start + 1)
        table.insert(lines, (text:gsub("[%c]", " ")))
        table.insert(highlights, { offset = #prefix, start = start })
    end
    if #lines == 0 then
        lines = { message or "No matches" }
    end
    vim.bo[state.results_buffer].modifiable = true
    vim.api.nvim_buf_set_lines(state.results_buffer, 0, -1, false, lines)
    vim.api.nvim_buf_clear_namespace(state.results_buffer, namespace, 0, -1)
    for row, entry in ipairs(state.entries) do
        highlight_ranges(state.results_buffer, row - 1, highlights[row].offset, entry.ranges, highlights[row].start)
    end
    vim.bo[state.results_buffer].modifiable = false
    state.selection = math.max(1, math.min(state.selection, #lines))
    vim.api.nvim_win_set_cursor(state.results_window, { state.selection, 0 })
    vim.api.nvim_win_set_config(state.results_window, {
        title = " " .. #state.entries .. " matches | " .. (message or "Done") .. " ",
    })
    update_preview(state)
end

local function move_selection(state, direction)
    if #state.entries == 0 then
        return
    end
    state.selection = (state.selection - 1 + direction) % #state.entries + 1
    vim.api.nvim_win_set_cursor(state.results_window, { state.selection, 0 })
    update_preview(state)
end

local function open_selection(state, mode)
    local entry = state.entries[state.selection]
    if not entry then
        return
    end
    close(state)
    local ok, open_error = pcall(function()
        local usable = false
        for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            local buffer = vim.api.nvim_win_get_buf(window)
            if vim.bo[buffer].buftype == "" and not vim.wo[window].winfixbuf
                and vim.api.nvim_win_get_config(window).relative == ""
            then
                vim.api.nvim_set_current_win(window)
                usable = true
                if window == state.origin then
                    break
                end
            end
        end
        if not usable then
            vim.cmd("belowright vnew")
        elseif mode == "vertical" then
            vim.cmd("belowright vsplit")
        elseif mode == "horizontal" then
            vim.cmd("belowright split")
        end
        vim.cmd("normal! m'")
        vim.api.nvim_cmd({ cmd = "edit", args = { entry.path } }, {})
        local row = math.min(entry.row, vim.api.nvim_buf_line_count(0))
        local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
        vim.api.nvim_win_set_cursor(0, { row, math.min(entry.column, #line) })
        vim.cmd("normal! zvzz")
    end)
    if not ok then
        vim.notify(tostring(open_error), vim.log.levels.ERROR, { title = "Find" })
    end
end

local function search(state, query)
    local pattern_text = "\\m" .. (query:find("%u") and "\\C" or "\\c") .. query
    local ok, pattern = pcall(vim.regex, pattern_text)
    if not ok then
        render(state, "Invalid pattern: " .. tostring(pattern):gsub("[%c]", " "))
        return
    end
    state.pattern_text = pattern_text
    local request = { directories = { state.root }, files = 0, skipped = 0 }
    state.request = request
    local pump
    local function resume()
        if is_active(state, request) then
            vim.defer_fn(pump, 1)
        end
    end
    local function read_file(path)
        vim.uv.fs_open(path, "r", 0, vim.schedule_wrap(function(open_error, descriptor)
            if not descriptor then
                request.skipped = request.skipped + 1
                resume()
                return
            end
            if not is_active(state, request) then
                vim.uv.fs_close(descriptor)
                return
            end
            vim.uv.fs_fstat(descriptor, vim.schedule_wrap(function(stat_error, stat)
                if not is_active(state, request) or stat_error or not stat
                    or stat.type ~= "file" or stat.size > maximum_bytes
                then
                    vim.uv.fs_close(descriptor)
                    request.skipped = request.skipped + 1
                    resume()
                    return
                end
                vim.uv.fs_read(descriptor, stat.size, 0, vim.schedule_wrap(function(read_error, data)
                    vim.uv.fs_close(descriptor)
                    if not is_active(state, request) then
                        return
                    end
                    request.files = request.files + 1
                    if read_error or not data or data:find("\0", 1, true) then
                        request.skipped = request.skipped + 1
                    elseif data ~= "" then
                        request.path = path
                        request.lines = vim.split(data, "\n", { plain = true })
                        if data:sub(-1) == "\n" then
                            table.remove(request.lines)
                        end
                        request.line_index = 1
                    end
                    resume()
                end))
            end))
        end))
    end
    local function status(label)
        return label .. " | " .. request.files .. " files | " .. request.skipped .. " skipped"
    end
    local last_render = 0
    local function report(label, force)
        local now = vim.uv.hrtime()
        if force or now - last_render >= 50000000 then
            render(state, status(label))
            last_render = now
        end
    end
    pump = function()
        if not is_active(state, request) then
            return
        end
        local deadline = vim.uv.hrtime() + 5000000
        while vim.uv.hrtime() < deadline do
            if request.lines then
                local row = request.line_index
                local line = request.lines[row]
                if not line then
                    request.lines = nil
                else
                    line = line:gsub("\r$", "")
                    if row == 1 then
                        line = line:gsub("^\239\187\191", "")
                    end
                    local column = pattern:match_str(line)
                    if column then
                        local relative = request.path:sub(#state.root:gsub("/$", "") + 2)
                        table.insert(state.entries, {
                            path = request.path, relative = relative, row = row, column = column, text = line,
                            ranges = match_ranges(line, pattern_text),
                        })
                        if #state.entries >= maximum_results then
                            report("Limit " .. maximum_results .. "; narrow the pattern", true)
                            return
                        end
                    end
                    request.line_index = row + 1
                end
            elseif request.scanner then
                local name, kind = vim.uv.fs_scandir_next(request.scanner)
                if not name then
                    request.scanner = nil
                else
                    local path = vim.fs.joinpath(request.directory, name)
                    if kind == "directory" and not excluded_directories[name] then
                        table.insert(request.directories, path)
                    elseif kind == "file" then
                        read_file(path)
                        report("Searching")
                        return
                    end
                end
            elseif #request.directories > 0 then
                request.directory = table.remove(request.directories)
                vim.uv.fs_scandir(request.directory, vim.schedule_wrap(function(scan_error, scanner)
                    if not is_active(state, request) then
                        return
                    end
                    if scan_error then
                        request.skipped = request.skipped + 1
                    else
                        request.scanner = scanner
                    end
                    resume()
                end))
                return
            else
                report("Done", true)
                return
            end
        end
        report("Searching")
        resume()
    end
    pump()
end

local function update_query(state)
    if not is_active(state) then
        return
    end
    stop_search(state)
    state.entries = {}
    state.selection = 1
    state.pattern_text = nil
    state.preview_cache = nil
    local input_lines = vim.api.nvim_buf_get_lines(state.input_buffer, 0, -1, false)
    local query = table.concat(input_lines, " ")
    if #input_lines > 1 then
        vim.api.nvim_buf_set_lines(state.input_buffer, 0, -1, false, { query })
        vim.api.nvim_win_set_cursor(state.input_window, { 1, #query })
    end
    render(state, query == "" and "Type a pattern" or "Waiting")
    local revision = state.revision
    if query ~= "" then
        vim.defer_fn(function()
            if is_active(state) and state.revision == revision then
                search(state, query)
            end
        end, 150)
    end
end

function M.grep()
    if active and is_active(active) then
        vim.api.nvim_set_current_win(active.input_window)
        vim.cmd.startinsert()
        return
    end
    if vim.o.columns < 35 or vim.o.lines - vim.o.cmdheight < 10 then
        vim.notify("Screen is too small for search", vim.log.levels.WARN)
        return
    end
    local state = {
        origin = vim.api.nvim_get_current_win(), root = vim.fn.getcwd(),
        entries = {}, selection = 1, revision = 0,
        input_buffer = vim.api.nvim_create_buf(false, true),
        results_buffer = vim.api.nvim_create_buf(false, true),
        preview_buffer = vim.api.nvim_create_buf(false, true),
    }
    for _, buffer in ipairs({ state.input_buffer, state.results_buffer, state.preview_buffer }) do
        vim.bo[buffer].bufhidden = "hide"
        vim.bo[buffer].swapfile = false
    end
    vim.bo[state.input_buffer].filetype = "ex_find_input"
    vim.bo[state.results_buffer].filetype = "ex_find_results"
    vim.bo[state.preview_buffer].filetype = "ex_find_preview"
    local width = math.min(vim.o.columns - 4, math.floor(vim.o.columns * 0.9))
    local height = math.floor((vim.o.lines - vim.o.cmdheight) * 0.8)
    local row = math.floor((vim.o.lines - vim.o.cmdheight - height) / 2)
    local column = math.floor((vim.o.columns - width - 2) / 2)
    local results_width = width
    local results_height = height - 5
    local preview_config
    if height >= 10 then
        if width >= 90 then
            results_width = math.floor((width - 2) / 2)
            preview_config = {
                row = row + 3, col = column + results_width + 2,
                width = width - results_width - 2, height = results_height,
            }
        else
            results_height = math.max(1, math.floor((height - 7) / 2))
            preview_config = {
                row = row + results_height + 5, col = column,
                width = width, height = height - results_height - 7,
            }
        end
    end
    state.results_window = vim.api.nvim_open_win(state.results_buffer, false, {
        relative = "editor", row = row + 3, col = column, width = results_width, height = results_height,
        border = "single", style = "minimal", title = " Results ",
    })
    vim.wo[state.results_window][0].cursorline = true
    vim.wo[state.results_window][0].wrap = false
    vim.wo[state.results_window][0].signcolumn = "no"
    if preview_config then
        preview_config.relative = "editor"
        preview_config.border = "single"
        preview_config.style = "minimal"
        preview_config.title = " Preview "
        preview_config.focusable = false
        state.preview_window = vim.api.nvim_open_win(state.preview_buffer, false, preview_config)
        vim.wo[state.preview_window][0].wrap = false
        vim.wo[state.preview_window][0].signcolumn = "no"
        vim.wo[state.preview_window][0].number = true
    end
    state.input_window = vim.api.nvim_open_win(state.input_buffer, true, {
        relative = "editor", row = row, col = column, width = width, height = 1,
        border = "single", style = "minimal", title = " Search: " .. state.root .. " ",
    })
    vim.wo[state.input_window][0].wrap = false
    vim.wo[state.input_window][0].signcolumn = "no"
    active = state
    for _, buffer in ipairs({ state.input_buffer, state.results_buffer }) do
        local function map(modes, key, callback, description)
            vim.keymap.set(modes, key, callback, { buffer = buffer, silent = true, desc = description })
        end
        map({ "i", "n" }, "<CR>", function() open_selection(state) end, "find: open")
        map({ "i", "n" }, "<C-v>", function() open_selection(state, "vertical") end, "find: vertical split")
        map({ "i", "n" }, "<C-x>", function() open_selection(state, "horizontal") end, "find: horizontal split")
        map({ "i", "n" }, "<C-n>", function() move_selection(state, 1) end, "find: next")
        map({ "i", "n" }, "<C-p>", function() move_selection(state, -1) end, "find: previous")
        map({ "i", "n" }, "<Down>", function() move_selection(state, 1) end, "find: next")
        map({ "i", "n" }, "<Up>", function() move_selection(state, -1) end, "find: previous")
        for _, key in ipairs({ "<C-d>", "<C-u>" }) do
            map({ "i", "n" }, key, function()
                if state.preview_window and vim.api.nvim_win_is_valid(state.preview_window) then
                    vim.api.nvim_win_call(state.preview_window, function()
                        vim.cmd("normal! " .. vim.api.nvim_replace_termcodes(key, true, false, true))
                    end)
                end
            end, "find: scroll preview")
        end
        map({ "i", "n" }, "<Esc>", function() close(state) end, "find: close")
        map({ "i", "n" }, "<C-c>", function() close(state) end, "find: close")
        map({ "i", "n" }, "<Tab>", function()
            vim.cmd.stopinsert()
            if vim.api.nvim_get_current_win() == state.input_window then
                vim.api.nvim_set_current_win(state.results_window)
            else
                vim.api.nvim_set_current_win(state.input_window)
                vim.cmd.startinsert()
            end
        end, "find: switch input/results")
        map({ "i", "n" }, "<C-q>", function()
            local items = {}
            for _, entry in ipairs(state.entries) do
                table.insert(items, {
                    filename = entry.path, lnum = entry.row, col = entry.column + 1, text = entry.text,
                })
            end
            close(state)
            vim.fn.setqflist({}, " ", { title = "Search: " .. state.root, items = items })
            vim.cmd.copen()
        end, "find: send results to quickfix")
    end
    local group = vim.api.nvim_create_augroup("ex_find_session", { clear = true })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
        group = group, buffer = state.input_buffer, callback = function() update_query(state) end,
    })
    vim.api.nvim_create_autocmd("CursorMoved", {
        group = group, buffer = state.results_buffer,
        callback = function()
            if is_active(state) and vim.api.nvim_win_is_valid(state.results_window) then
                state.selection = vim.api.nvim_win_get_cursor(state.results_window)[1]
                update_preview(state)
            end
        end,
    })
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        callback = function(options)
            local window = tonumber(options.match)
            if not state.closed and (window == state.input_window or window == state.results_window
                or window == state.preview_window)
            then
                vim.schedule(function() close(state) end)
            end
        end,
    })
    vim.api.nvim_create_autocmd("VimResized", { group = group, callback = function() close(state) end })
    render(state, "Type a pattern")
    vim.cmd.startinsert()
end

function M.setup()
    vim.keymap.set("n", "<leader>fg", M.grep, { desc = "find: search text" })
    local function set_highlights()
        vim.api.nvim_set_hl(0, "ExFindMatch", { fg = "#ffd166", bold = true, default = true })
        vim.api.nvim_set_hl(0, "ExFindCurrent", { bg = "#303846", default = true })
    end
    set_highlights()
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("ex_find", { clear = true }), callback = set_highlights,
    })
end

return M
