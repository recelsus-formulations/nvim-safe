local M = {}
local lsp_directory = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local mason = require("lsp.mason")
local specs = {}
-- vim.lsp.is_enabled は 0.11.2+ のため、有効化済みのサーバーはここで管理する
local enabled = {}

-- 0.11+ は標準の vim.lsp.config / vim.lsp.enable、それ以前は vim.lsp.start による代替実装を使う
local function has_native()
    return type(vim.lsp.config) == "table" and type(vim.lsp.enable) == "function"
end
local client = has_native() and {
    config = function(name, config) vim.lsp.config(name, config) end,
    enable = function(names)
        vim.lsp.enable(names)
        -- 起動後に有効にした場合の既存バッファへの接続は 0.11.2+。それ以前は同じ処理をここで行う
        if vim.v.vim_did_enter == 1 and vim.fn.has("nvim-0.11.2") == 0 then
            vim.cmd.doautoall("nvim.lsp.enable FileType")
        end
    end,
} or require("lsp.fallback")

local function report_error(message)
    vim.notify(tostring(message), vim.log.levels.ERROR, { title = "LSP" })
end

local function load_specs()
    specs = {}
    for _, file in ipairs(vim.fn.glob(lsp_directory .. "/servers/*.lua", false, true)) do
        local language = vim.fn.fnamemodify(file, ":t:r")
        local ok, spec = pcall(dofile, file)
        if not ok then
            report_error(spec)
        elseif type(spec) ~= "table" or type(spec.name) ~= "string" or type(spec.config) ~= "table" then
            report_error("Invalid server spec: lsp/servers/" .. language .. ".lua")
        else
            spec.language = language
            specs[language] = spec
            client.config(spec.name, spec.config)
        end
    end
end

local function is_executable(spec)
    for _, requirement in ipairs(spec.runtime_requires or {}) do
        local available = false
        for _, command in ipairs(vim.split(requirement, "|", { plain = true })) do
            if vim.fn.executable(command) == 1 then
                available = true
                break
            end
        end
        if not available then
            return false
        end
    end
    if type(spec.is_available) == "function" then
        return spec.is_available()
    end
    local command = spec.executable or (type(spec.config.cmd) == "table" and spec.config.cmd[1])
    if not command then
        return type(spec.config.cmd) == "function"
    end
    return vim.fn.executable(command) == 1
end

-- 実行ファイルが無いサーバーを有効にすると、対象バッファを開くたびにエラーになるため除外する
local function enable_available()
    local names = {}
    for _, spec in pairs(specs) do
        if not enabled[spec.name] and is_executable(spec) then
            enabled[spec.name] = true
            table.insert(names, spec.name)
        end
    end
    if #names > 0 then
        client.enable(names)
    end
end

local function on_mason_loaded()
    mason.on_installed(enable_available)
    enable_available()
end

local function install(languages)
    local install_all = #languages == 0
    if install_all then
        languages = vim.tbl_keys(specs)
        table.sort(languages)
    end
    local packages = {}
    for _, language in ipairs(languages) do
        local spec = specs[language]
        if not spec then
            report_error("Unknown language: " .. language)
            return
        end
        if spec.package then
            table.insert(packages, spec.package)
        elseif spec.install_hint and not install_all then
            vim.notify(spec.install_hint, vim.log.levels.INFO, { title = "LSP" })
        end
    end
    if #packages > 0 then
        if not mason.is_loaded() then
            report_error("mason.nvim is not installed. Run :MasonBootstrap first")
            return
        end
        mason.install(packages)
    end
end

function M.is_native()
    return has_native()
end

function M.setup()
    require("lsp.hover").setup()
    require("lsp.diagnostics").setup()
    vim.filetype.add({ extension = { ctp = "php" } })
    -- 行末に診断を表示する (既定値は 0.11 以降 false、0.10 以前 true のため明示して揃える)
    vim.diagnostic.config({ virtual_text = true })
    load_specs()
    if mason.is_supported() and mason.is_installed() and mason.load() then
        on_mason_loaded()
    else
        enable_available()
    end
    -- Mason が対象外の環境 (0.10 未満) では PATH 上のサーバーだけを使う
    if not mason.is_supported() then
        return
    end
    vim.api.nvim_create_user_command("MasonBootstrap", function()
        mason.bootstrap(function(loaded)
            if loaded then
                on_mason_loaded()
            end
        end)
    end, { desc = "Install mason.nvim" })
    vim.api.nvim_create_user_command("LspInstall", function(options)
        install(options.fargs)
    end, {
        nargs = "*",
        desc = "Install language servers via mason.nvim",
        complete = function()
            local languages = vim.tbl_keys(specs)
            table.sort(languages)
            return languages
        end,
    })
end

return M
