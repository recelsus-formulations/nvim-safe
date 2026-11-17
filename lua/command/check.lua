-- :ConfigCheck  bin/check.sh を実行し、結果を分割ウィンドウに表示する
-- 確認処理が使用中のセッションに影響しないよう、別プロセスとして非同期に実行する
local M = {}
local compat = require("compat")
local config_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
local script = compat.joinpath(config_root, "bin", "check.sh")
local buffer_name = "ex://config-check"
local running = false

local function find_window(buffer)
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_buf(window) == buffer then
            return window
        end
    end
end

local function get_buffer()
    local buffer = vim.fn.bufnr(buffer_name)
    if buffer ~= -1 and vim.api.nvim_buf_is_valid(buffer) then
        return buffer
    end
    buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buffer, buffer_name)
    vim.bo[buffer].bufhidden = "hide"
    vim.bo[buffer].swapfile = false
    vim.bo[buffer].filetype = "ex_config_check"
    vim.keymap.set("n", "q", "<Cmd>close<CR>", { buffer = buffer, silent = true, desc = "check: close" })
    vim.keymap.set("n", "R", "<Cmd>ConfigCheck<CR>", { buffer = buffer, silent = true, desc = "check: rerun" })
    vim.api.nvim_buf_call(buffer, function()
        vim.cmd([[
            syntax match ExCheckOk /\[OK\]/
            syntax match ExCheckMissing /\[--\]/
            syntax match ExCheckNg /\[NG\]/
            syntax match ExCheckSection /^== .*/
            highlight default link ExCheckOk DiagnosticOk
            highlight default link ExCheckMissing DiagnosticWarn
            highlight default link ExCheckNg DiagnosticError
            highlight default link ExCheckSection Title
        ]])
    end)
    return buffer
end

local function set_lines(buffer, lines)
    vim.bo[buffer].modifiable = true
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.bo[buffer].modifiable = false
end

local function show(buffer)
    local window = find_window(buffer)
    if window then
        vim.api.nvim_set_current_win(window)
        return
    end
    vim.cmd("botright split")
    vim.api.nvim_win_set_buf(0, buffer)
    compat.set_window_local(0, "number", false)
    compat.set_window_local(0, "relativenumber", false)
    compat.set_window_local(0, "signcolumn", "no")
    compat.set_window_local(0, "wrap", false)
end

function M.run()
    if running then
        vim.notify("ConfigCheck is already running", vim.log.levels.WARN, { title = "ConfigCheck" })
        return
    end
    if vim.fn.executable("bash") ~= 1 then
        vim.notify("bash executable not found", vim.log.levels.ERROR, { title = "ConfigCheck" })
        return
    end
    local buffer = get_buffer()
    set_lines(buffer, { "Running " .. script .. " ..." })
    show(buffer)
    running = true
    local ok, start_error = pcall(compat.system, { "bash", script }, vim.schedule_wrap(function(result)
        running = false
        if not vim.api.nvim_buf_is_valid(buffer) then
            return
        end
        local output = vim.split((result.stdout or "") .. (result.stderr or ""), "\n", { plain = true })
        while #output > 0 and output[1] == "" do
            table.remove(output, 1)
        end
        while #output > 0 and output[#output] == "" do
            table.remove(output)
        end
        if result.code ~= 0 then
            table.insert(output, "")
            table.insert(output, "(exit code " .. tostring(result.code) .. ")")
        end
        table.insert(output, "")
        table.insert(output, "q: 閉じる  R: 再実行")
        set_lines(buffer, output)
    end), {
        -- 実行中の nvim と同じものを確認に使う
        env = { CHECK_NVIM = vim.v.progpath },
    })
    if not ok then
        running = false
        set_lines(buffer, { "Could not run " .. script .. ": " .. tostring(start_error) })
    end
end

function M.setup()
    vim.api.nvim_create_user_command("ConfigCheck", M.run, {
        desc = "Show available commands, parsers and language servers (bin/check.sh)",
    })
end

return M
