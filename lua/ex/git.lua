-- Git の利用可否とリポジトリの状態取得。ex.signs と ex.tree で共有する
local M = {}
local compat = require("compat")

-- git が無い環境では、signs・tree ともに Git 関連の処理を一切行わない
function M.is_available()
    return vim.fn.executable("git") == 1
end

local function run(directory, arguments, callback)
    local command = { "git", "--no-optional-locks", "-C", directory }
    vim.list_extend(command, arguments)
    local ok = pcall(compat.system, command, vim.schedule_wrap(callback))
    if not ok then
        vim.schedule(function() callback({ code = -1, stdout = "", stderr = "" }) end)
    end
end

-- callback(toplevel|nil): directory を含むリポジトリのルート
function M.toplevel(directory, callback)
    run(directory, { "rev-parse", "--show-toplevel" }, function(result)
        local toplevel = result.code == 0 and vim.trim(result.stdout or "") or ""
        callback(toplevel ~= "" and toplevel or nil)
    end)
end

-- callback(files|nil): { [絶対パス] = "XY" }。XY は git status --porcelain=v1 の2文字。
-- 無視されたディレクトリは末尾の / を除いたパスで "!!" になる
function M.status(toplevel, callback)
    run(toplevel, { "status", "--porcelain=v1", "-z", "--ignored=matching", "-u" }, function(result)
        if result.code ~= 0 then
            callback(nil)
            return
        end
        local fields = {}
        -- 区切りは NUL。0.9 の vim.system 代替実装 (jobstart) では NUL が改行になるため両方で区切る
        for field in (result.stdout or ""):gmatch("[^%z\n]+") do
            fields[#fields + 1] = field
        end
        local files = {}
        local index = 1
        while index <= #fields do
            local field = fields[index]
            local xy = field:sub(1, 2)
            local path = field:sub(4):gsub("/$", "")
            files[toplevel .. "/" .. path] = xy
            -- 名前変更・コピーは次のフィールドに元のパスが続く
            if xy:find("[RC]") then
                index = index + 1
            end
            index = index + 1
        end
        callback(files)
    end)
end

-- XY を nvim-tree と同じ種類に分類する
-- staged / unstaged / renamed / untracked / deleted / unmerged / ignored
function M.kinds(xy)
    if xy == "??" then
        return { "untracked" }
    elseif xy == "!!" then
        return { "ignored" }
    end
    local x, y = xy:sub(1, 1), xy:sub(2, 2)
    if x == "U" or y == "U" or xy == "AA" or xy == "DD" then
        return { "unmerged" }
    end
    local kinds = {}
    if x == "R" then
        table.insert(kinds, "renamed")
    elseif x == "D" then
        table.insert(kinds, "deleted")
    elseif x:match("[MATC]") then
        table.insert(kinds, "staged")
    end
    if y == "M" or y == "T" then
        table.insert(kinds, "unstaged")
    elseif y == "D" then
        table.insert(kinds, "deleted")
    elseif y == "R" then
        table.insert(kinds, "renamed")
    elseif y == "A" then
        table.insert(kinds, "untracked")
    end
    return kinds
end

return M
