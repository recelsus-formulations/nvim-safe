local M = {}
local compat = require("compat")

local severity_names = {
    [vim.diagnostic.severity.ERROR] = "Error",
    [vim.diagnostic.severity.WARN] = "Warning",
    [vim.diagnostic.severity.INFO] = "Info",
    [vim.diagnostic.severity.HINT] = "Hint",
}

local function line_diagnostics(buffer, row)
    local diagnostics = vim.diagnostic.get(buffer, { lnum = row - 1 })
    table.sort(diagnostics, function(left, right)
        if left.col ~= right.col then
            return (left.col or 0) < (right.col or 0)
        end
        return (left.severity or 4) < (right.severity or 4)
    end)
    return diagnostics
end

function M.format(buffer, diagnostic)
    local path = vim.api.nvim_buf_get_name(buffer)
    local name = path ~= "" and vim.fn.fnamemodify(path, ":.") or "[No Name]"
    local position = ("%s:%d:%d [%s]"):format(name, diagnostic.lnum + 1,
        (diagnostic.col or 0) + 1, severity_names[diagnostic.severity] or "Diagnostic")
    local source = diagnostic.source and diagnostic.source ~= "" and ("Source: " .. diagnostic.source) or nil
    local code = diagnostic.code and ("Code: " .. tostring(diagnostic.code)) or nil
    local line = vim.api.nvim_buf_get_lines(buffer, diagnostic.lnum, diagnostic.lnum + 1, false)[1]
    local parts = { position, vim.trim(diagnostic.message or "") }
    if source then parts[#parts + 1] = source end
    if code then parts[#parts + 1] = code end
    if line and vim.trim(line) ~= "" then parts[#parts + 1] = "Line: " .. vim.trim(line) end
    return table.concat(parts, "\n")
end

local function copy_diagnostics(buffer, all)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local diagnostics = line_diagnostics(buffer, cursor[1])
    if #diagnostics == 0 then
        vim.notify("No diagnostics on the current line", vim.log.levels.INFO, { title = "LSP Diagnostics" })
        return
    end
    if not all then
        local selected = diagnostics[1]
        local distance = math.abs((selected.col or 0) - cursor[2])
        for _, diagnostic in ipairs(diagnostics) do
            local next_distance = math.abs((diagnostic.col or 0) - cursor[2])
            if next_distance < distance then
                selected, distance = diagnostic, next_distance
            end
        end
        diagnostics = { selected }
    end
    local entries = {}
    for _, diagnostic in ipairs(diagnostics) do
        entries[#entries + 1] = M.format(buffer, diagnostic)
    end
    local content = table.concat(entries, "\n\n")
    local ok, result = pcall(vim.fn.setreg, "+", content)
    if not ok or result ~= 0 then
        vim.notify("Could not copy diagnostics: " .. tostring(result),
            vim.log.levels.ERROR, { title = "LSP Diagnostics" })
        return
    end
    vim.notify(("Copied %d diagnostic%s to clipboard"):format(#diagnostics,
        #diagnostics == 1 and "" or "s"), vim.log.levels.INFO, { title = "LSP Diagnostics" })
end

function M.setup()
    local group = vim.api.nvim_create_augroup("ex_diagnostic_copy", { clear = true })
    vim.api.nvim_create_autocmd("LspAttach", {
        group = group,
        callback = function(options)
            vim.keymap.set("n", "<leader>yc", function() copy_diagnostics(options.buf, false) end,
                { buffer = options.buf, silent = true, desc = "lsp: copy nearest line diagnostic" })
            vim.keymap.set("n", "<leader>ya", function() copy_diagnostics(options.buf, true) end,
                { buffer = options.buf, silent = true, desc = "lsp: copy all line diagnostics" })
        end,
    })
    vim.api.nvim_create_autocmd("LspDetach", {
        group = group,
        callback = function(options)
            local buffer = options.buf
            vim.schedule(function()
                if not vim.api.nvim_buf_is_valid(buffer) or #compat.lsp_clients({ bufnr = buffer }) > 0 then
                    return
                end
                pcall(vim.keymap.del, "n", "<leader>yc", { buffer = buffer })
                pcall(vim.keymap.del, "n", "<leader>ya", { buffer = buffer })
            end)
        end,
    })
end

return M
