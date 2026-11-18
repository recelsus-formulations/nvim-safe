local M = {}
local compat = require("compat")
local panel = require("ex.panel")
local namespace = vim.api.nvim_create_namespace("ex_find_matches")
local selection_namespace = vim.api.nvim_create_namespace("ex_find_selection")
local maximum_results = 500
local maximum_bytes = 1024 * 1024
local excluded_directories = { [".git"] = true, [".cache"] = true, Library = true, node_modules = true }
local default_excludes = { ".git/", ".cache/", "Library/", "node_modules/" }

local function input_text(buffer)
    local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
    local value = table.concat(lines, " ")
    if #lines > 1 then
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { value })
    end
    return value
end

local function split_filters(text)
    local values = {}
    for value in text:gmatch("[^,%s]+") do
        values[#values + 1] = value
    end
    return values
end

local function extension_filters(text)
    local values = {}
    for _, value in ipairs(split_filters(text)) do
        local extension = value:gsub("^%*%.", ""):gsub("^%.", "")
        if extension ~= "" then
            values[#values + 1] = extension
        end
    end
    return values
end

local function excluded_path(relative, name, is_directory, filters)
    for _, value in ipairs(filters) do
        if value:sub(-1) == "/" then
            local directory = value:sub(1, -2)
            if is_directory and name == directory then
                return true
            end
        else
            local target = value:find("/", 1, true) and relative or name
            local ok, pattern = pcall(vim.fn.glob2regpat, value)
            if ok and vim.fn.match(target, pattern) >= 0 then
                return true
            end
        end
    end
    return false
end

local function allowed_extension(name, extensions)
    if #extensions == 0 then
        return true
    end
    for _, extension in ipairs(extensions) do
        if name:sub(-#extension - 1) == "." .. extension then
            return true
        end
    end
    return false
end

local function is_active(state, request)
    return panel.is_active(state) and (not request or state.request == request)
end

local function stop_search(state)
    if state.request and state.request.job and state.request.job > 0 then
        vim.fn.jobstop(state.request.job)
    end
    state.request = nil
    state.revision = state.revision + 1
end

local function close(state)
    panel.close(state)
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
    compat.set_window_local(state.preview_window, "statuscolumn", lines and ("%{v:lnum + " .. (first - 1) .. "} ") or "")
    vim.bo[buffer].syntax = lines and (vim.filetype.match({ filename = entry.path }) or "") or ""
    if lines and state.pattern_text then
        for row, line in ipairs(display) do
            highlight_ranges(buffer, row - 1, 0, match_ranges(line, state.pattern_text))
        end
    elseif lines and entry and state.view_name == "grep" then
        highlight_ranges(buffer, selected_row - 1, 0, entry.ranges)
    end
    if lines and entry then
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
        title = entry and (" " .. entry.relative:gsub("[%c]", " ")
            .. (state.view_name == "grep" and ":" .. entry.row or "") .. " ") or " Preview ",
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
    compat.uv.fs_open(entry.path, "r", 0, vim.schedule_wrap(function(open_error, descriptor)
        if not descriptor then
            set_preview(state, entry, nil, "Could not open file")
            return
        end
        if not is_active(state) or state.preview_entry ~= entry then
            compat.uv.fs_close(descriptor)
            return
        end
        compat.uv.fs_fstat(descriptor, vim.schedule_wrap(function(stat_error, stat)
            if not is_active(state) or state.preview_entry ~= entry or stat_error or not stat
                or stat.type ~= "file" or stat.size > maximum_bytes
            then
                compat.uv.fs_close(descriptor)
                set_preview(state, entry, nil, "Preview unavailable")
                return
            end
            compat.uv.fs_read(descriptor, stat.size, 0, vim.schedule_wrap(function(read_error, data)
                compat.uv.fs_close(descriptor)
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

local function highlight_selection(state)
    vim.api.nvim_buf_clear_namespace(state.results_buffer, selection_namespace, 0, -1)
    if state.entries[state.selection] then
        vim.api.nvim_buf_set_extmark(state.results_buffer, selection_namespace, state.selection - 1, 0, {
            line_hl_group = "ExFindSelected", priority = 150,
        })
    end
end

local function render(state, message)
    if not is_active(state) or not vim.api.nvim_win_is_valid(state.results_window) then
        return
    end
    local lines = {}
    local highlights = {}
    local width = vim.api.nvim_win_get_width(state.results_window)
    for _, entry in ipairs(state.entries) do
        if state.view_name == "files" then
            table.insert(lines, (entry.relative:gsub("[%c]", " ")))
            table.insert(highlights, { offset = 0, start = 0 })
        else
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
    highlight_selection(state)
    vim.api.nvim_win_set_config(state.results_window, {
        title = " " .. #state.entries .. (state.view_name == "files" and " files | " or " matches | ")
            .. (message or "Done") .. " ",
    })
    update_preview(state)
end

local function move_selection(state, direction)
    if #state.entries == 0 then
        return
    end
    state.selection = (state.selection - 1 + direction) % #state.entries + 1
    vim.api.nvim_win_set_cursor(state.results_window, { state.selection, 0 })
    highlight_selection(state)
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
            if vim.bo[buffer].buftype == "" and not compat.is_winfixbuf(window)
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

local function search_rg(state, query, extensions, excludes)
    local command = { "rg", "--json", "--hidden", "--no-ignore", "--max-filesize", "1M", "--smart-case" }
    if #extensions > 0 then
        local globs = {}
        for _, extension in ipairs(extensions) do
            globs[#globs + 1] = "*." .. extension
        end
        command[#command + 1] = "--glob"
        command[#command + 1] = #globs == 1 and globs[1] or "{" .. table.concat(globs, ",") .. "}"
    end
    for _, value in ipairs(excludes) do
        local glob = value:sub(-1) == "/" and "**/" .. value .. "**" or value
        command[#command + 1] = "--glob"
        command[#command + 1] = "!" .. glob
    end
    command[#command + 1] = "--"
    command[#command + 1] = query
    command[#command + 1] = "."

    local request = { files = 0, skipped = 0, seen = {}, pending = "", errors = {} }
    state.request = request
    state.pattern_text = nil
    local function process_line(line)
        if not is_active(state, request) or line == "" then
            return
        end
        local ok, event = pcall(vim.fn.json_decode, line)
        if not ok or type(event) ~= "table" or event.type ~= "match" then
            return
        end
        local data = event.data
        local relative = data.path and data.path.text
        local content = data.lines and data.lines.text
        if not relative or not content or #state.entries >= maximum_results then
            return
        end
        content = content:gsub("\r?\n$", "")
        local ranges = {}
        for _, match in ipairs(data.submatches or {}) do
            ranges[#ranges + 1] = { match.start, match["end"] }
        end
        if #ranges == 0 then
            return
        end
        if not request.seen[relative] then
            request.seen[relative] = true
            request.files = request.files + 1
        end
        state.entries[#state.entries + 1] = {
            path = compat.joinpath(state.root, relative), relative = relative,
            row = data.line_number, column = ranges[1][1], text = content, ranges = ranges,
        }
        if #state.entries >= maximum_results then
            vim.fn.jobstop(request.job)
            render(state, "Limit " .. maximum_results .. "; narrow the pattern")
        end
    end
    local function on_output(_, data)
        if not is_active(state, request) then
            return
        end
        for index, part in ipairs(data) do
            if index == 1 then
                part = request.pending .. part
            end
            if index == #data then
                request.pending = part
            else
                process_line(part)
            end
        end
        render(state, "Searching | " .. request.files .. " files")
    end
    request.job = vim.fn.jobstart(command, {
        cwd = state.root,
        on_stdout = vim.schedule_wrap(on_output),
        on_stderr = vim.schedule_wrap(function(_, data)
            for _, line in ipairs(data) do
                if line ~= "" and #request.errors < 3 then
                    request.errors[#request.errors + 1] = line
                end
            end
        end),
        on_exit = vim.schedule_wrap(function(_, code)
            if not is_active(state, request) then
                return
            end
            process_line(request.pending)
            if #state.entries >= maximum_results then
                return
            end
            if code > 1 then
                render(state, "rg: " .. table.concat(request.errors, " "):gsub("[%c]", " "))
            else
                render(state, "Done | " .. request.files .. " files")
            end
        end),
    })
    if request.job <= 0 then
        render(state, "Could not start rg")
    end
end

local function search(state, query, extensions, excludes)
    if vim.fn.executable("rg") == 1 then
        search_rg(state, query, extensions, excludes)
        return
    end
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
        compat.uv.fs_open(path, "r", 0, vim.schedule_wrap(function(open_error, descriptor)
            if not descriptor then
                request.skipped = request.skipped + 1
                resume()
                return
            end
            if not is_active(state, request) then
                compat.uv.fs_close(descriptor)
                return
            end
            compat.uv.fs_fstat(descriptor, vim.schedule_wrap(function(stat_error, stat)
                if not is_active(state, request) or stat_error or not stat
                    or stat.type ~= "file" or stat.size > maximum_bytes
                then
                    compat.uv.fs_close(descriptor)
                    request.skipped = request.skipped + 1
                    resume()
                    return
                end
                compat.uv.fs_read(descriptor, stat.size, 0, vim.schedule_wrap(function(read_error, data)
                    compat.uv.fs_close(descriptor)
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
        local now = compat.uv.hrtime()
        if force or now - last_render >= 50000000 then
            render(state, status(label))
            last_render = now
        end
    end
    pump = function()
        if not is_active(state, request) then
            return
        end
        local deadline = compat.uv.hrtime() + 5000000
        while compat.uv.hrtime() < deadline do
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
                local name, kind = compat.uv.fs_scandir_next(request.scanner)
                if not name then
                    request.scanner = nil
                else
                    local path = compat.joinpath(request.directory, name)
                    local relative = path:sub(#state.root:gsub("/$", "") + 2)
                    if kind == "directory" and not excluded_directories[name]
                        and not excluded_path(relative, name, true, excludes)
                    then
                        table.insert(request.directories, path)
                    elseif kind == "file" and allowed_extension(name, extensions)
                        and not excluded_path(relative, name, false, excludes)
                    then
                        read_file(path)
                        report("Searching")
                        return
                    end
                end
            elseif #request.directories > 0 then
                request.directory = table.remove(request.directories)
                compat.uv.fs_scandir(request.directory, vim.schedule_wrap(function(scan_error, scanner)
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

local function file_match(relative, query)
    local ranges = {}
    local path = relative:lower()
    local search_from = 1
    local first
    local last
    for index = 1, #query do
        local position = path:find(query:sub(index, index), search_from, true)
        if not position then
            return nil
        end
        ranges[#ranges + 1] = { position - 1, position }
        first = first or position
        last = position
        search_from = position + 1
    end
    local score = first and (last - first + 1 - #query) * 10 + first + #relative / 100 or #relative
    return ranges, score
end

local function add_file(state, request, relative, query)
    relative = relative:gsub("^%./", "")
    if relative == "" or #state.entries >= maximum_results then
        return
    end
    local ranges, score = file_match(relative, query)
    if not ranges then
        return
    end
    state.entries[#state.entries + 1] = {
        path = compat.joinpath(state.root, relative), relative = relative,
        row = 1, column = 0, text = relative, ranges = ranges, score = score,
    }
    if #state.entries >= maximum_results then
        request.limited = true
        if request.job and request.job > 0 then
            vim.fn.jobstop(request.job)
        end
    end
end

local function finish_files(state, request)
    if not is_active(state, request) then
        return
    end
    table.sort(state.entries, function(left, right)
        if left.score ~= right.score then
            return left.score < right.score
        end
        return left.relative < right.relative
    end)
    render(state, request.limited and ("Limit " .. maximum_results .. "; narrow the pattern") or "Done")
end

local function search_files_rg(state, query, extensions, excludes)
    local command = { "rg", "--files", "--hidden", "--no-ignore" }
    if #extensions > 0 then
        local globs = {}
        for _, extension in ipairs(extensions) do
            globs[#globs + 1] = "*." .. extension
        end
        command[#command + 1] = "--glob"
        command[#command + 1] = #globs == 1 and globs[1] or "{" .. table.concat(globs, ",") .. "}"
    end
    for _, value in ipairs(excludes) do
        command[#command + 1] = "--glob"
        command[#command + 1] = "!" .. (value:sub(-1) == "/" and "**/" .. value .. "**" or value)
    end
    command[#command + 1] = "."
    local request = { pending = "", errors = {} }
    state.request = request
    local function process_line(line)
        if is_active(state, request) and not request.limited then
            add_file(state, request, line, query)
        end
    end
    request.job = vim.fn.jobstart(command, {
        cwd = state.root,
        on_stdout = vim.schedule_wrap(function(_, data)
            if not is_active(state, request) then
                return
            end
            for index, part in ipairs(data) do
                if index == 1 then
                    part = request.pending .. part
                end
                if index == #data then
                    request.pending = part
                else
                    process_line(part)
                end
            end
            render(state, request.limited and "Limit reached" or "Searching")
        end),
        on_stderr = vim.schedule_wrap(function(_, data)
            for _, line in ipairs(data) do
                if line ~= "" and #request.errors < 3 then
                    request.errors[#request.errors + 1] = line
                end
            end
        end),
        on_exit = vim.schedule_wrap(function(_, code)
            if not is_active(state, request) then
                return
            end
            process_line(request.pending)
            if code > 1 and not request.limited then
                render(state, "rg: " .. table.concat(request.errors, " "):gsub("[%c]", " "))
            else
                finish_files(state, request)
            end
        end),
    })
    if request.job <= 0 then
        render(state, "Could not start rg")
    end
end

local function search_files_native(state, query, extensions, excludes)
    local request = { directories = { state.root } }
    state.request = request
    local pump
    pump = function()
        if not is_active(state, request) then
            return
        end
        local deadline = compat.uv.hrtime() + 5000000
        while compat.uv.hrtime() < deadline and not request.limited do
            if request.scanner then
                local name, kind = compat.uv.fs_scandir_next(request.scanner)
                if not name then
                    request.scanner = nil
                else
                    local path = compat.joinpath(request.directory, name)
                    local relative = path:sub(#state.root:gsub("/$", "") + 2)
                    if kind == "directory" and not excluded_directories[name]
                        and not excluded_path(relative, name, true, excludes)
                    then
                        request.directories[#request.directories + 1] = path
                    elseif kind == "file" and allowed_extension(name, extensions)
                        and not excluded_path(relative, name, false, excludes)
                    then
                        add_file(state, request, relative, query)
                    end
                end
            elseif #request.directories > 0 then
                request.directory = table.remove(request.directories)
                request.scanner = compat.uv.fs_scandir(request.directory)
            else
                finish_files(state, request)
                return
            end
        end
        if request.limited then
            finish_files(state, request)
        else
            render(state, "Searching")
            vim.defer_fn(pump, 1)
        end
    end
    pump()
end

local function search_files(state, query, extensions, excludes)
    if vim.fn.executable("rg") == 1 then
        search_files_rg(state, query, extensions, excludes)
    else
        search_files_native(state, query, extensions, excludes)
    end
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
    local query = input_text(state.input_buffer)
    local extensions = extension_filters(input_text(state.extension_buffer))
    local excludes = vim.list_extend(vim.deepcopy(default_excludes), split_filters(input_text(state.exclude_buffer)))
    render(state, query == "" and (state.view_name == "files" and "Listing files" or "Type a pattern")
        or "Waiting")
    local revision = state.revision
    if query ~= "" or state.view_name == "files" then
        vim.defer_fn(function()
            if is_active(state) and state.revision == revision then
                if state.view_name == "files" then
                    search_files(state, query:lower(), extensions, excludes)
                else
                    search(state, query, extensions, excludes)
                end
            end
        end, 150)
    end
end

local function send_quickfix(state)
    local items = {}
    for _, entry in ipairs(state.entries) do
        items[#items + 1] = {
            filename = entry.path, lnum = entry.row, col = entry.column + 1, text = entry.text,
        }
    end
    local title = state.view_name == "files" and "Files: " or "Search: "
    close(state)
    vim.fn.setqflist({}, " ", { title = title .. state.root, items = items })
    vim.cmd.copen()
end

function M.grep()
    return panel.show("grep")
end

function M.files()
    return panel.show("files")
end

function M.setup()
    local common_view = {
        on_change = update_query,
        on_open = open_selection,
        on_move = move_selection,
        on_close = stop_search,
        on_quickfix = send_quickfix,
        on_select = function(state)
            state.selection = vim.api.nvim_win_get_cursor(state.results_window)[1]
            highlight_selection(state)
            update_preview(state)
        end,
    }
    panel.register("grep", vim.tbl_extend("force", common_view, {
        title = "Search",
        on_show = function(state) render(state, "Type a pattern") end,
    }))
    panel.register("files", vim.tbl_extend("force", common_view, {
        title = "Files",
        on_show = update_query,
    }))
    vim.keymap.set("n", "<leader>fg", M.grep, { desc = "find: search text" })
    vim.keymap.set("n", "<leader>ff", M.files, { desc = "find: search files" })
    local function set_highlights()
        vim.api.nvim_set_hl(0, "ExFindMatch", { fg = "#ffd166", bold = true, default = true })
        vim.api.nvim_set_hl(0, "ExFindCurrent", { bg = "#303846", default = true })
        vim.api.nvim_set_hl(0, "ExFindSelected", { bg = "#445876", bold = true, default = true })
    end
    set_highlights()
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("ex_find", { clear = true }), callback = set_highlights,
    })
end

return M
