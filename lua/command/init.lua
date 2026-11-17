-- lua/command/*.lua を読み込み、各モジュールの setup() でユーザーコマンドを定義する。
-- コマンドを追加する場合は、setup() を持つモジュールをこのディレクトリに置く
local M = {}

local function report_error(message)
    vim.notify(tostring(message), vim.log.levels.ERROR, { title = "Command" })
end

function M.setup()
    local names = {}
    for _, file in ipairs(vim.api.nvim_get_runtime_file("lua/command/*.lua", true)) do
        local name = vim.fn.fnamemodify(file, ":t:r")
        if name ~= "init" then
            table.insert(names, name)
        end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local ok, module = pcall(require, "command." .. name)
        if not ok then
            report_error(module)
        elseif type(module) ~= "table" or type(module.setup) ~= "function" then
            report_error("Invalid command module: lua/command/" .. name .. ".lua (setup() is required)")
        else
            local set_up, setup_error = pcall(module.setup)
            if not set_up then
                report_error(setup_error)
            end
        end
    end
end

return M
