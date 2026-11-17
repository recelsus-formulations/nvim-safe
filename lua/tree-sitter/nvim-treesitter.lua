local M = {}
local compat = require("compat")
local repository = "https://github.com/nvim-treesitter/nvim-treesitter"
local loaded = false

-- packpath 配下の opt に置くことで、packadd するまで読み込まれない
M.path = compat.joinpath(vim.fn.stdpath("data"), "site", "pack", "ex", "opt", "nvim-treesitter")

local function notify(message, level)
    vim.notify(message, level or vim.log.levels.INFO, { title = "nvim-treesitter" })
end

-- nvim-treesitter は main (0.12+) と master (0.10 / 0.11 向けに凍結) で互換性がなく、
-- 機能の有無では判別できないため Neovim のバージョンで選ぶ
function M.branch()
    if vim.fn.has("nvim-0.12") == 1 then
        return "main"
    end
    if vim.fn.has("nvim-0.10") == 1 then
        return "master"
    end
end

function M.is_supported()
    return M.branch() ~= nil
end

function M.is_installed()
    return compat.uv.fs_stat(compat.joinpath(M.path, "plugin", "nvim-treesitter.lua")) ~= nil
end

-- git を起動せず .git/HEAD から取得済みのブランチを読む
function M.installed_branch()
    local file = io.open(compat.joinpath(M.path, ".git", "HEAD"), "r")
    if not file then
        return nil
    end
    local head = file:read("*l") or ""
    file:close()
    return head:match("^ref: refs/heads/(.+)$")
end

function M.is_loaded()
    return loaded
end

function M.load()
    if loaded then
        return true
    end
    if not M.is_supported() or not M.is_installed() then
        return false
    end
    local branch = M.installed_branch()
    if branch ~= M.branch() then
        notify(("Installed branch is %s, but Neovim %s needs %s. Run :TreesitterBootstrap! to reinstall")
            :format(tostring(branch), tostring(vim.version()), M.branch()), vim.log.levels.WARN)
        return false
    end
    local ok, load_error = pcall(function()
        vim.cmd.packadd("nvim-treesitter")
        if M.branch() == "main" then
            require("nvim-treesitter").setup()
        end
    end)
    if not ok then
        notify("Could not load nvim-treesitter: " .. tostring(load_error), vim.log.levels.ERROR)
        return false
    end
    loaded = true
    return true
end

-- force: ブランチ違いなどで取得し直す。master の場合は取得済み parser も一緒に削除される
function M.bootstrap(force, callback)
    if not M.is_supported() then
        notify("nvim-treesitter requires Neovim 0.10 or later", vim.log.levels.ERROR)
        return
    end
    if M.is_installed() and not force then
        notify("nvim-treesitter is already installed: " .. M.path)
        callback(M.load())
        return
    end
    if loaded then
        notify("nvim-treesitter is loaded. Restart Neovim before reinstalling", vim.log.levels.ERROR)
        return
    end
    if vim.fn.executable("git") ~= 1 then
        notify("git executable not found", vim.log.levels.ERROR)
        return
    end
    if M.is_installed() and vim.fn.delete(M.path, "rf") ~= 0 then
        notify("Could not remove: " .. M.path, vim.log.levels.ERROR)
        return
    end
    vim.fn.mkdir(vim.fs.dirname(M.path), "p")
    local branch = M.branch()
    notify("Installing nvim-treesitter (" .. branch .. ")...")
    local command = { "git", "clone", "--depth", "1", "--branch", branch, repository, M.path }
    compat.system(command, vim.schedule_wrap(function(result)
        if result.code ~= 0 then
            notify("Could not install nvim-treesitter: " .. vim.trim(result.stderr or ""), vim.log.levels.ERROR)
            return
        end
        notify("Installed nvim-treesitter (" .. branch .. "): " .. M.path)
        callback(M.load())
    end))
end

-- parser の取得に必要な外部コマンド ("a|b" はいずれか)
function M.requirements()
    local compiler = "cc|gcc|clang"
    if M.branch() == "main" then
        return { "tree-sitter", compiler, "curl", "tar" }
    end
    return { compiler .. "|zig", "curl|git", "tar|git" }
end

function M.missing_requirements()
    local missing = {}
    for _, requirement in ipairs(M.requirements()) do
        local found = false
        for _, command in ipairs(vim.split(requirement, "|", { plain = true })) do
            if vim.fn.executable(command) == 1 then
                found = true
                break
            end
        end
        -- コンパイラは $CC で指定されたものも使われる
        if not found and requirement:find("gcc", 1, true) and vim.env.CC and vim.fn.executable(vim.env.CC) == 1 then
            found = true
        end
        if not found then
            table.insert(missing, requirement)
        end
    end
    return missing
end

-- 未取得の parser だけを取得し、完了後に on_done(err) を呼ぶ
function M.install(languages, on_done)
    local missing = M.missing_requirements()
    if #missing > 0 then
        on_done("Missing commands: " .. table.concat(missing, ", "))
        return
    end
    if M.branch() == "main" then
        require("nvim-treesitter").install(languages, { summary = true }):await(vim.schedule_wrap(function(err)
            on_done(err)
        end))
        return
    end
    local ok, install_error = pcall(require("nvim-treesitter.install").ensure_installed, languages)
    if not ok then
        on_done(install_error)
        return
    end
    -- master には完了通知が無いため、parser ファイルが揃うまで確認する
    local function is_done()
        for _, language in ipairs(languages) do
            if not compat.uv.fs_stat(compat.joinpath(M.path, "parser", language .. ".so")) then
                return false
            end
        end
        return true
    end
    local timer = compat.uv.new_timer()
    local elapsed = 0
    timer:start(1000, 1000, vim.schedule_wrap(function()
        elapsed = elapsed + 1
        local done = is_done()
        if done or elapsed >= 600 then
            timer:stop()
            timer:close()
            on_done(not done and "Timed out waiting for parsers (see :messages)" or nil)
        end
    end))
end

return M
