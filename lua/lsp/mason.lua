local M = {}
local compat = require("compat")
local repository = "https://github.com/mason-org/mason.nvim"
local loaded = false

-- packpath 配下の opt に置くことで、packadd するまで読み込まれない
M.path = compat.joinpath(vim.fn.stdpath("data"), "site", "pack", "ex", "opt", "mason.nvim")

local function notify(message, level)
    vim.notify(message, level or vim.log.levels.INFO, { title = "Mason" })
end

-- mason.nvim の対象は 0.10 以降
function M.is_supported()
    return vim.fn.has("nvim-0.10") == 1
end

function M.is_installed()
    return compat.uv.fs_stat(compat.joinpath(M.path, "lua", "mason", "init.lua")) ~= nil
end

function M.is_loaded()
    return loaded
end

function M.load()
    if loaded then
        return true
    end
    if not M.is_installed() then
        return false
    end
    local ok, load_error = pcall(function()
        vim.cmd.packadd("mason.nvim")
        require("mason").setup()
    end)
    if not ok then
        notify("Could not load mason.nvim: " .. tostring(load_error), vim.log.levels.ERROR)
        return false
    end
    loaded = true
    return true
end

function M.bootstrap(callback)
    if M.is_installed() then
        notify("mason.nvim is already installed: " .. M.path)
        callback(M.load())
        return
    end
    if vim.fn.executable("git") ~= 1 then
        notify("Mason installation skipped: git executable not found", vim.log.levels.INFO)
        return
    end
    vim.fn.mkdir(vim.fs.dirname(M.path), "p")
    notify("Installing mason.nvim...")
    compat.system({ "git", "clone", "--depth", "1", repository, M.path }, vim.schedule_wrap(function(result)
        if result.code ~= 0 then
            notify("Could not install mason.nvim: " .. vim.trim(result.stderr or ""), vim.log.levels.ERROR)
            return
        end
        notify("Installed mason.nvim: " .. M.path)
        callback(M.load())
    end))
end

function M.install(packages)
    vim.cmd.MasonInstall({ args = packages })
end

function M.on_installed(callback)
    require("mason-registry"):on("package:install:success", vim.schedule_wrap(function(package)
        callback(package.name)
    end))
end

return M
