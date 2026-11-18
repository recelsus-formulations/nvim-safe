local M = {}
local sidebar = require("ex.sidebar")
local states = {}

local groups = {
    { severity = vim.diagnostic.severity.ERROR, label = "Errors" },
    { severity = vim.diagnostic.severity.WARN, label = "Warnings" },
    { severity = vim.diagnostic.severity.INFO, label = "Information" },
    { severity = vim.diagnostic.severity.HINT, label = "Hints" },
}

local function tab_state()
    local tabpage = vim.api.nvim_get_current_tabpage()
    if not states[tabpage] then
        states[tabpage] = { rows = {}, expanded = {} }
    end
    return states[tabpage]
end

local function source_buffer()
    local window = sidebar.source_window()
    if window and vim.api.nvim_win_is_valid(window) then
        local buffer = vim.api.nvim_win_get_buf(window)
        if vim.bo[buffer].buftype == "" then
            return buffer
        end
    end
end

local function render(state)
    if not state.buffer or not vim.api.nvim_buf_is_valid(state.buffer) then
        return
    end
    local buffer = state.source_buffer
    local name = buffer and vim.api.nvim_buf_is_valid(buffer)
        and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buffer), ":t") or ""
    local lines = { "DIAGNOSTICS TREE", name ~= "" and name or "[No Name]" }
    state.rows = {}
    if not buffer or not vim.api.nvim_buf_is_valid(buffer) then
        lines[#lines + 1] = "No editor buffer available"
    else
        local diagnostics = vim.diagnostic.get(buffer)
        table.sort(diagnostics, function(left, right)
            if left.lnum ~= right.lnum then return left.lnum < right.lnum end
            if left.col ~= right.col then return (left.col or 0) < (right.col or 0) end
            return (left.severity or 4) < (right.severity or 4)
        end)
        if #diagnostics == 0 then
            lines[#lines + 1] = "No diagnostics"
        end
        for _, group in ipairs(groups) do
            local entries = {}
            for _, diagnostic in ipairs(diagnostics) do
                if diagnostic.severity == group.severity then
                    entries[#entries + 1] = diagnostic
                end
            end
            if #entries > 0 then
                local expanded = state.expanded[group.severity] ~= false
                lines[#lines + 1] = (expanded and "▾ " or "▸ ") .. group.label .. " (" .. #entries .. ")"
                state.rows[#lines] = { severity = group.severity }
                if expanded then
                    for _, diagnostic in ipairs(entries) do
                        local message = (diagnostic.message or ""):gsub("%s+", " ")
                        lines[#lines + 1] = ("  %d:%d %s"):format(diagnostic.lnum + 1,
                            (diagnostic.col or 0) + 1, message)
                        state.rows[#lines] = { diagnostic = diagnostic }
                    end
                end
            end
        end
    end
    vim.bo[state.buffer].modifiable = true
    vim.api.nvim_buf_set_lines(state.buffer, 0, -1, false, lines)
    vim.bo[state.buffer].modifiable = false
    sidebar.highlight_title(state.buffer, "ExSidebarDiagnosticTitle", #lines[1])
    sidebar.refresh_preview()
end

local function refresh()
    local state = tab_state()
    state.source_buffer = source_buffer()
    render(state)
end

local function open_row()
    local state = tab_state()
    local window = sidebar.get_window()
    if not window or vim.api.nvim_win_get_buf(window) ~= state.buffer then return end
    local row = state.rows[vim.api.nvim_win_get_cursor(window)[1]]
    if not row then return end
    if row.severity then
        state.expanded[row.severity] = state.expanded[row.severity] == false
        render(state)
        return
    end
    local buffer = state.source_buffer
    if not buffer or not vim.api.nvim_buf_is_valid(buffer) then return end
    local target = sidebar.pick_editor_window()
    if not target then return end
    vim.api.nvim_set_current_win(target)
    if vim.api.nvim_win_get_buf(target) ~= buffer then
        vim.api.nvim_win_set_buf(target, buffer)
    end
    local diagnostic = row.diagnostic
    local line = math.min(diagnostic.lnum + 1, vim.api.nvim_buf_line_count(buffer))
    local text = vim.api.nvim_buf_get_lines(buffer, line - 1, line, false)[1] or ""
    vim.api.nvim_win_set_cursor(target, { line, math.min(diagnostic.col or 0, #text) })
    vim.cmd("normal! zvzz")
end

local function create()
    local state = tab_state()
    state.buffer = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buffer].bufhidden = "hide"
    vim.bo[state.buffer].swapfile = false
    vim.bo[state.buffer].filetype = "revim_diagnostics"
    vim.keymap.set("n", "<CR>", open_row,
        { buffer = state.buffer, silent = true, desc = "diagnostics: open or expand" })
    vim.keymap.set("n", "R", refresh,
        { buffer = state.buffer, silent = true, desc = "diagnostics: refresh" })
    vim.keymap.set("n", "q", sidebar.close,
        { buffer = state.buffer, silent = true, desc = "diagnostics: close" })
    return state.buffer
end

function M.setup()
    sidebar.register("diagnostics", {
        create = create,
        refresh = refresh,
        dispose = function(context) states[context.tabpage] = nil end,
    })
    vim.api.nvim_create_autocmd("DiagnosticChanged", {
        group = vim.api.nvim_create_augroup("ex_diagnostic_tree", { clear = true }),
        callback = function(options)
            if sidebar.current() == "diagnostics" then
                local state = tab_state()
                if options.buf == state.source_buffer then render(state) end
            end
        end,
    })
end

return M
