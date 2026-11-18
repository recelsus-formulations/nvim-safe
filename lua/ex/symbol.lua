local M = {}
local compat = require("compat")
local sidebar = require("ex.sidebar")
local states = {}

local function tab_state(tabpage)
    tabpage = tabpage or vim.api.nvim_get_current_tabpage()
    if not states[tabpage] then
        states[tabpage] = { generation = 0, rows = {}, expanded = {} }
    end
    return states[tabpage]
end

local function notify(message, level)
    vim.notify(message, level or vim.log.levels.INFO, { title = "Symbol Tree" })
end

local function supports(client, method)
    if type(client.supports_method) == "function" then
        local ok, supported = pcall(client.supports_method, client, method)
        if ok then
            return supported
        end
    end
    local capability = method == "textDocument/definition" and "definitionProvider" or "documentSymbolProvider"
    return client.server_capabilities and client.server_capabilities[capability] or false
end

local function file_location(uri, range, encoding)
    if type(uri) ~= "string" or not uri:match("^file://") or type(range) ~= "table"
        or type(range.start) ~= "table"
    then
        return nil
    end
    local ok, path = pcall(vim.uri_to_fname, uri)
    if not ok or path == "" then
        return nil
    end
    return {
        path = path,
        row = range.start.line + 1,
        character = range.start.character,
        encoding = encoding or "utf-16",
    }
end

local function display_path(path)
    return vim.fn.fnamemodify(path, ":.")
end

local function collect_definitions(result, encoding, locations, seen)
    if type(result) ~= "table" then
        return
    end
    local items = result
    if result.uri or result.targetUri then
        items = { result }
    end
    for _, item in ipairs(items) do
        local location = file_location(item.targetUri or item.uri,
            item.targetSelectionRange or item.targetRange or item.range, encoding)
        if location then
            local key = location.path .. ":" .. location.row .. ":" .. location.character
            if not seen[key] then
                seen[key] = true
                locations[#locations + 1] = location
            end
        end
    end
end

local function definition_nodes(locations)
    table.sort(locations, function(left, right)
        if left.path ~= right.path then
            return left.path < right.path
        end
        if left.row ~= right.row then
            return left.row < right.row
        end
        return left.character < right.character
    end)
    local nodes = {}
    local groups = {}
    for _, location in ipairs(locations) do
        local group = groups[location.path]
        if not group then
            group = { id = "file:" .. location.path, label = display_path(location.path), children = {} }
            groups[location.path] = group
            nodes[#nodes + 1] = group
        end
        group.children[#group.children + 1] = {
            id = location.path .. ":" .. location.row .. ":" .. location.character,
            label = "line " .. location.row,
            location = location,
        }
    end
    return nodes
end

local function document_nodes(items, uri, encoding, parent_id)
    local nodes = {}
    for index, item in ipairs(items or {}) do
        local location = item.location
            and file_location(item.location.uri, item.location.range, encoding)
            or file_location(uri, item.selectionRange or item.range, encoding)
        if location then
            local id = (parent_id or "document") .. ":" .. index .. ":" .. item.name
            local children = item.children and document_nodes(item.children, uri, encoding, id) or nil
            nodes[#nodes + 1] = {
                id = id,
                label = item.name .. (item.detail and item.detail ~= "" and " — " .. item.detail or ""),
                location = location,
                children = children and #children > 0 and children or nil,
            }
        end
    end
    return nodes
end

local function render(state, message)
    if not state.buffer or not vim.api.nvim_buf_is_valid(state.buffer) then
        return
    end
    local source_name = state.source_buffer and vim.api.nvim_buf_is_valid(state.source_buffer)
        and vim.api.nvim_buf_get_name(state.source_buffer) or ""
    local header = state.mode == "definition" and "DEFINITION TREE" or "SYMBOL TREE"
    local subject = state.mode == "definition" and (state.word or "")
        or vim.fn.fnamemodify(source_name, ":t")
    local lines = { header, subject ~= "" and subject or "[No Name]", message or "" }
    state.rows = {}
    local function append(nodes, depth)
        for _, node in ipairs(nodes) do
            local branch = node.children and #node.children > 0
            local expanded = state.expanded[node.id] ~= false
            local prefix = string.rep("  ", depth) .. (branch and (expanded and "▾ " or "▸ ") or "  ")
            lines[#lines + 1] = prefix .. node.label
            state.rows[#lines] = node
            if branch and expanded then
                append(node.children, depth + 1)
            end
        end
    end
    append(state.nodes or {}, 0)
    vim.bo[state.buffer].modifiable = true
    vim.api.nvim_buf_set_lines(state.buffer, 0, -1, false, lines)
    vim.bo[state.buffer].modifiable = false
    sidebar.highlight_title(state.buffer, "ExSidebarSymbolTitle", #header)
    sidebar.refresh_preview()
end

local function selected_node(state)
    local window = sidebar.get_window()
    if not window or vim.api.nvim_win_get_buf(window) ~= state.buffer then
        return nil
    end
    return state.rows[vim.api.nvim_win_get_cursor(window)[1]]
end

local function byte_column(buffer, location)
    local line = vim.api.nvim_buf_get_lines(buffer, location.row - 1, location.row, false)[1] or ""
    if location.encoding == "utf-8" then
        return math.min(location.character, #line)
    end
    return compat.lsp_byte_index(line, location.character, location.encoding)
end

local function open_node(state, mode)
    local node = selected_node(state)
    if not node then
        return
    end
    if node.children and mode == "edit" then
        state.expanded[node.id] = state.expanded[node.id] == false
        render(state)
        return
    end
    local location = node.location or (node.children and node.children[1] and node.children[1].location)
    if not location or vim.fn.filereadable(location.path) ~= 1 then
        notify("Definition file is unavailable", vim.log.levels.WARN)
        return
    end
    local windows = sidebar.editor_windows()
    local target = sidebar.pick_editor_window(windows)
    if #windows > 0 and not target then
        return
    end
    local sidebar_window = sidebar.get_window()
    local ok, open_error = pcall(function()
        if target then
            vim.api.nvim_set_current_win(target)
            if mode == "vertical" then
                vim.cmd("belowright vsplit")
            elseif mode == "horizontal" then
                vim.cmd("belowright split")
            elseif not vim.o.hidden and vim.bo[vim.api.nvim_get_current_buf()].modified then
                vim.cmd("belowright vsplit")
            end
        else
            vim.api.nvim_set_current_win(sidebar_window)
            vim.cmd("belowright vsplit")
        end
        vim.cmd("normal! m'")
        vim.api.nvim_cmd({ cmd = "edit", args = { location.path } }, {})
        local buffer = vim.api.nvim_get_current_buf()
        local row = math.min(location.row, vim.api.nvim_buf_line_count(buffer))
        vim.api.nvim_win_set_cursor(0, { row, byte_column(buffer, location) })
        vim.cmd("normal! zvzz")
    end)
    if sidebar_window and vim.api.nvim_win_is_valid(sidebar_window) then
        sidebar.restore_width()
        if mode == "preview" or not ok then
            vim.api.nvim_set_current_win(sidebar_window)
        end
    end
    if not ok then
        notify(tostring(open_error), vim.log.levels.ERROR)
    end
end

local function character_offset(line, byte_column_value, encoding)
    local prefix = line:sub(1, byte_column_value)
    if encoding == "utf-8" then
        return #prefix
    end
    local units = 0
    for index = 0, vim.fn.strchars(prefix) - 1 do
        local character = vim.fn.strcharpart(prefix, index, 1)
        local codepoint = vim.fn.char2nr(character)
        units = units + (encoding == "utf-16" and codepoint > 65535 and 2 or 1)
    end
    return units
end

local function request_symbols(state)
    state.generation = state.generation + 1
    state.result_ready = false
    local generation = state.generation
    local tabpage = state.tabpage
    local buffer = state.source_buffer
    if not buffer or not vim.api.nvim_buf_is_valid(buffer) or vim.bo[buffer].buftype ~= "" then
        state.message = "No source buffer available"
        render(state, state.message)
        notify("No source buffer available")
        return
    end
    local method = state.mode == "definition" and "textDocument/definition" or "textDocument/documentSymbol"
    local clients = {}
    for _, client in ipairs(compat.lsp_clients({ bufnr = buffer })) do
        if supports(client, method) then
            clients[#clients + 1] = client
        end
    end
    if #clients == 0 then
        state.nodes = {}
        state.result_ready = true
        state.message = "No connected LSP supports " .. method
        render(state, state.message)
        notify("No connected LSP supports " .. method)
        return
    end
    state.message = "Loading..."
    render(state, "Loading...")
    local remaining = #clients
    local locations, seen, nodes = {}, {}, {}
    local uri = vim.uri_from_bufnr(buffer)
    local function valid_response()
        return states[tabpage] == state and vim.api.nvim_tabpage_is_valid(tabpage)
            and vim.api.nvim_buf_is_valid(buffer) and state.generation == generation
            and sidebar.current(tabpage) == "symbol"
    end
    local function finish()
        remaining = remaining - 1
        if remaining ~= 0 or not valid_response() then
            return
        end
        state.nodes = state.mode == "definition" and definition_nodes(locations) or nodes
        state.result_ready = true
        state.message = #state.nodes == 0 and "No symbols found" or nil
        render(state, state.message)
    end
    for _, client in ipairs(clients) do
        local encoding = client.offset_encoding or "utf-16"
        local params = { textDocument = { uri = uri } }
        if state.mode == "definition" then
            local cursor = state.source_cursor
            local line = vim.api.nvim_buf_get_lines(buffer, cursor[1] - 1, cursor[1], false)[1] or ""
            params.position = { line = cursor[1] - 1,
                character = character_offset(line, cursor[2], encoding) }
        end
        local ok, sent = pcall(compat.lsp_request, client, method, params, function(error, result)
            if valid_response() and not error then
                if state.mode == "definition" then
                    collect_definitions(result, encoding, locations, seen)
                elseif type(result) == "table" then
                    vim.list_extend(nodes, document_nodes(result, uri, encoding))
                end
            end
            finish()
        end, buffer)
        if not ok or not sent then
            finish()
        end
    end
end

local function create_buffer(state)
    state.buffer = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buffer].bufhidden = "hide"
    vim.bo[state.buffer].filetype = "revim_symbol"
    vim.bo[state.buffer].swapfile = false
    local function map(key, callback, description)
        vim.keymap.set("n", key, callback, { buffer = state.buffer, silent = true, desc = description })
    end
    map("<CR>", function() open_node(state, "edit") end, "symbol: open or expand")
    map("<Tab>", function() open_node(state, "preview") end, "symbol: preview")
    map("<C-v>", function() open_node(state, "vertical") end, "symbol: vertical split")
    map("<C-x>", function() open_node(state, "horizontal") end, "symbol: horizontal split")
    map("R", function() request_symbols(state) end, "symbol: refresh")
    map("q", sidebar.close, "symbol: close")
    return state.buffer
end

local function show(mode)
    local source_window = vim.api.nvim_get_current_win()
    if source_window == sidebar.get_window() then
        source_window = sidebar.source_window()
    end
    if not source_window or not vim.api.nvim_win_is_valid(source_window) then
        notify("No editor window available")
        return
    end
    local buffer = vim.api.nvim_win_get_buf(source_window)
    if vim.bo[buffer].buftype ~= "" then
        notify("No source buffer available")
        return
    end
    local method = mode == "definition" and "textDocument/definition" or "textDocument/documentSymbol"
    local available = false
    for _, client in ipairs(compat.lsp_clients({ bufnr = buffer })) do
        if supports(client, method) then
            available = true
            break
        end
    end
    if not available then
        notify("No connected LSP supports " .. method)
        return
    end
    local state = tab_state()
    local cursor = vim.api.nvim_win_get_cursor(source_window)
    local same_context = state.mode == mode and state.source_buffer == buffer and state.result_ready
        and (mode == "document" or state.source_cursor and state.source_cursor[1] == cursor[1]
            and state.source_cursor[2] == cursor[2])
    state.tabpage = vim.api.nvim_get_current_tabpage()
    state.source_buffer = buffer
    state.source_cursor = cursor
    state.word = ""
    if mode == "definition" then
        local ok, word = pcall(vim.api.nvim_win_call, source_window,
            function() return vim.fn.expand("<cword>") end)
        if ok then
            state.word = word
        end
    end
    state.mode = mode
    if not same_context then
        state.nodes = {}
        state.expanded = {}
    end
    sidebar.show("symbol", { refresh = not same_context })
end

function M.definition()
    show("definition")
end

function M.document()
    show("document")
end

function M.setup()
    sidebar.register("symbol", {
        create = function()
            return create_buffer(tab_state())
        end,
        refresh = function(context)
            local state = tab_state()
            if not state.mode then
                local source_window = sidebar.source_window()
                state.tabpage = vim.api.nvim_get_current_tabpage()
                state.mode = "document"
                if source_window and vim.api.nvim_win_is_valid(source_window) then
                    local buffer = vim.api.nvim_win_get_buf(source_window)
                    if vim.bo[buffer].buftype == "" then
                        state.source_buffer = buffer
                        state.source_cursor = vim.api.nvim_win_get_cursor(source_window)
                    end
                end
            end
            if context and (context.refresh == false or context.restore and state.result_ready) then
                render(state, state.message)
            else
                request_symbols(state)
            end
        end,
        dispose = function(context)
            local state = states[context.tabpage]
            if state then
                state.generation = state.generation + 1
                states[context.tabpage] = nil
            end
        end,
    })
    if vim.fn.maparg("gd", "n") == "" then
        vim.keymap.set("n", "gd", M.definition, { desc = "symbol: definitions" })
    end
    vim.api.nvim_create_user_command("SymbolTree", function(options)
        if options.args == "definition" then
            M.definition()
        elseif options.args == "" or options.args == "document" then
            M.document()
        else
            notify("Expected :SymbolTree [definition|document]", vim.log.levels.ERROR)
        end
    end, { nargs = "?", complete = function() return { "definition", "document" } end })
end

return M
