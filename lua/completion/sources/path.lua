-- ファイルパス (cmp-path 相当)。カーソル直前が ./ ../ ~/ / などのパスの場合に、そのディレクトリの中身を候補にする
local M = {}
local compat = require("compat")
local maximum_entries = 300

-- { directory = 一覧を取るディレクトリ, name = 入力中の名前, start = 置き換え開始位置 } または nil
function M.match(context)
    local token = context.before:match("[^%s'\"`<>()%[%]{}=,;|]*$") or ""
    local directory_part = token:match("^(.*/)")
    -- URL (://) やコメント (//) は対象外
    if not directory_part or token:find("://", 1, true) or directory_part:find("//", 1, true) then
        return nil
    end
    local directory
    if directory_part:sub(1, 1) == "/" then
        directory = directory_part
    elseif directory_part:sub(1, 2) == "~/" then
        directory = vim.fn.expand("~") .. directory_part:sub(2)
    elseif directory_part:sub(1, 1) == "$" then
        directory = vim.fn.expand(directory_part)
    else
        -- 相対パスは編集中のファイルのディレクトリを基準にする (無名バッファは作業ディレクトリ)
        local name = vim.api.nvim_buf_get_name(context.bufnr)
        local base = name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd()
        directory = compat.joinpath(base, directory_part)
    end
    local stat = compat.uv.fs_stat(directory)
    if not stat or stat.type ~= "directory" then
        return nil
    end
    local name = token:sub(#directory_part + 1)
    return { directory = directory, name = name, start = #context.before - #name }
end

function M.complete(context, callback)
    local target = M.match(context)
    if not target then
        callback(nil)
        return
    end
    local scanner = compat.uv.fs_scandir(target.directory)
    local items = {}
    while scanner and #items < maximum_entries do
        local name, kind = compat.uv.fs_scandir_next(scanner)
        if not name then
            break
        end
        -- 隠しファイルは . から入力した場合のみ
        if name:sub(1, 1) ~= "." or target.name:sub(1, 1) == "." then
            if kind == "link" then
                local stat = compat.uv.fs_stat(compat.joinpath(target.directory, name))
                kind = stat and stat.type or kind
            end
            local is_directory = kind == "directory"
            items[#items + 1] = {
                word = name .. (is_directory and "/" or ""),
                abbr = name .. (is_directory and "/" or ""),
                kind = is_directory and "Folder" or "File",
                menu = "[Path]",
                directory = is_directory,
            }
        end
    end
    table.sort(items, function(left, right)
        if left.directory ~= right.directory then
            return left.directory
        end
        return left.word < right.word
    end)
    callback({ start = target.start, items = items })
end

return M
