local M = {}
local compat = require("compat")
local git = require("ex.git")
local sidebar = require("ex.sidebar")
local states = {}
local git_namespace = vim.api.nvim_create_namespace("ex_tree_git")
-- git が無い環境では Git の状態表示を行わない (setup で判定)
local git_enabled = false

-- nvim-tree の既定に合わせた記号。★ と Nerd Font の記号は ambiwidth=double で幅が変わるため置き換えている
local git_icons = {
    staged = { "✓", "ExTreeGitStaged" },
    unstaged = { "✗", "ExTreeGitDirty" },
    renamed = { "➜", "ExTreeGitRenamed" },
    untracked = { "✚", "ExTreeGitNew" },
    deleted = { "✖", "ExTreeGitDeleted" },
    unmerged = { "!", "ExTreeGitMerge" },
    ignored = { "◌", "ExTreeGitIgnored" },
}
-- 名前の色に使う種類の優先順位
local git_priority = { "unmerged", "deleted", "unstaged", "renamed", "untracked", "staged", "ignored" }

local function report_error(message)
    vim.notify(tostring(message), vim.log.levels.ERROR, { title = "File tree" })
end

local function is_valid_window(window)
    return window ~= nil and vim.api.nvim_win_is_valid(window)
end

local function get_state()
    local tabpage = vim.api.nvim_get_current_tabpage()
    if not states[tabpage] then
        states[tabpage] = { root = vim.fn.getcwd(), expanded = {}, entries = {} }
    end
    return states[tabpage]
end

local function selected_entry(state)
    if not is_valid_window(state.window) or vim.api.nvim_win_get_buf(state.window) ~= state.buffer then
        return nil
    end
    return state.entries[vim.api.nvim_win_get_cursor(state.window)[1]]
end

-- entry の Git の状態を種類の一覧で返す。ディレクトリは配下に変更があれば unstaged (nvim-tree の dirty)
local function git_kinds(state, entry)
    local status = state.git
    if not status then
        return nil
    end
    local xy = status.files[entry.path]
    if entry.directory and xy ~= "!!" then
        return status.dirty[entry.path] and { "unstaged" } or nil
    end
    if xy then
        return git.kinds(xy)
    end
    -- 無視されたディレクトリの配下
    local parent = vim.fs.dirname(entry.path)
    while parent and #parent >= #state.root do
        if status.files[parent] == "!!" then
            return { "ignored" }
        end
        local next_parent = vim.fs.dirname(parent)
        if next_parent == parent then
            break
        end
        parent = next_parent
    end
end

local function decorate(state)
    if not state.buffer or not vim.api.nvim_buf_is_valid(state.buffer) then
        return
    end
    vim.api.nvim_buf_clear_namespace(state.buffer, git_namespace, 0, -1)
    if not state.git then
        return
    end
    for index, entry in ipairs(state.entries) do
        local kinds = index > 1 and git_kinds(state, entry)
        if kinds and #kinds > 0 then
            local present = {}
            local icons = {}
            for _, kind in ipairs(kinds) do
                present[kind] = true
                table.insert(icons, { git_icons[kind][1], git_icons[kind][2] })
            end
            -- 右端の区切り線と詰まらないよう余白を空ける
            table.insert(icons, { " " })
            for _, kind in ipairs(git_priority) do
                if present[kind] then
                    vim.api.nvim_buf_set_extmark(state.buffer, git_namespace, index - 1, entry.name_column, {
                        end_col = entry.name_column + #entry.name,
                        hl_group = git_icons[kind][2],
                        virt_text = icons,
                        virt_text_pos = "right_align",
                    })
                    break
                end
            end
        end
    end
end

local function render(state, selected_path)
    if not state.buffer or not vim.api.nvim_buf_is_valid(state.buffer) then
        return
    end
    local previous = selected_entry(state)
    selected_path = selected_path or (previous and previous.path)
    local entries = { { path = state.root, directory = true } }
    local lines = { state.root }
    local function append_directory(path, depth)
        local scanner, scan_error = compat.uv.fs_scandir(path)
        if not scanner then
            report_error(scan_error)
            return
        end
        local children = {}
        while true do
            local name, kind = compat.uv.fs_scandir_next(scanner)
            if not name then
                break
            end
            local child_path = compat.joinpath(path, name)
            local stat = kind == "link" and compat.uv.fs_stat(child_path) or nil
            table.insert(children, {
                path = child_path,
                name = name,
                directory = kind == "directory" or (stat and stat.type == "directory") or false,
            })
        end
        table.sort(children, function(left, right)
            if left.directory ~= right.directory then
                return left.directory
            end
            return left.name < right.name
        end)
        for _, entry in ipairs(children) do
            table.insert(entries, entry)
            local marker = entry.directory and (state.expanded[entry.path] and "- " or "+ ") or "  "
            local prefix = string.rep("  ", depth) .. marker
            entry.name_column = #prefix
            table.insert(lines, prefix .. entry.name)
            if entry.directory and state.expanded[entry.path] then
                append_directory(entry.path, depth + 1)
            end
        end
    end
    append_directory(state.root, 0)
    state.entries = entries
    vim.bo[state.buffer].modifiable = true
    vim.api.nvim_buf_set_lines(state.buffer, 0, -1, false, lines)
    vim.bo[state.buffer].modifiable = false
    decorate(state)
    if is_valid_window(state.window) and vim.api.nvim_win_get_buf(state.window) == state.buffer then
        for index, entry in ipairs(entries) do
            if entry.path == selected_path then
                vim.api.nvim_win_set_cursor(state.window, { index, 0 })
                break
            end
        end
    end
end

local function is_visible(state)
    return is_valid_window(state.window) and vim.api.nvim_win_get_buf(state.window) == state.buffer
end

local function is_inside(path, directory)
    return path == directory or path:sub(1, #directory + 1) == directory .. "/"
end

-- 表示中のルートと展開済みディレクトリが属するリポジトリの git status を取得し、表示に反映する。
-- only_new: 所属リポジトリが未確認のディレクトリがある場合だけ取得する (展開時)
local function refresh_git(state, only_new)
    if not git_enabled or not is_visible(state) then
        return
    end
    if state.git_running then
        state.git_pending = state.git_pending or not only_new
        return
    end
    state.git_toplevels = state.git_toplevels or {}
    local directories = { state.root }
    for directory, expanded in pairs(state.expanded) do
        if expanded and is_inside(directory, state.root) then
            table.insert(directories, directory)
        end
    end
    local unresolved = {}
    for _, directory in ipairs(directories) do
        if state.git_toplevels[directory] == nil then
            local covered = false
            for _, toplevel in pairs(state.git_toplevels) do
                if toplevel and is_inside(directory, toplevel) then
                    covered = true
                    break
                end
            end
            if not covered then
                table.insert(unresolved, directory)
            end
        end
    end
    if only_new and #unresolved == 0 then
        return
    end
    state.git_running = true
    -- git は実体のパスを返すため、シンボリックリンク経由のルートとの差を変換する
    local real_root = compat.uv.fs_realpath(state.root) or state.root
    local function to_tree_path(path)
        if real_root ~= state.root and is_inside(path, real_root) then
            return state.root .. path:sub(#real_root + 1)
        end
        return path
    end
    local function finish(files)
        state.git_running = false
        local dirty = {}
        for path, xy in pairs(files) do
            if xy ~= "!!" then
                local parent = vim.fs.dirname(path)
                while parent and not dirty[parent] do
                    dirty[parent] = true
                    local next_parent = vim.fs.dirname(parent)
                    if next_parent == parent then
                        break
                    end
                    parent = next_parent
                end
            end
        end
        state.git = { files = files, dirty = dirty }
        decorate(state)
        if state.git_pending then
            state.git_pending = false
            refresh_git(state)
        end
    end
    local function collect_status()
        local toplevels = {}
        for _, directory in ipairs(directories) do
            local toplevel = state.git_toplevels[directory]
            if toplevel == nil then
                for _, known in pairs(state.git_toplevels) do
                    if known and is_inside(directory, known) then
                        toplevel = known
                        break
                    end
                end
            end
            if toplevel then
                toplevels[toplevel] = true
            end
        end
        local files = {}
        local remaining = vim.tbl_count(toplevels)
        if remaining == 0 then
            finish(files)
            return
        end
        for toplevel in pairs(toplevels) do
            git.status(toplevel, function(result)
                for path, xy in pairs(result or {}) do
                    files[to_tree_path(path)] = xy
                end
                remaining = remaining - 1
                if remaining == 0 then
                    finish(files)
                end
            end)
        end
    end
    local remaining = #unresolved
    if remaining == 0 then
        collect_status()
        return
    end
    for _, directory in ipairs(unresolved) do
        git.toplevel(directory, function(toplevel)
            state.git_toplevels[directory] = toplevel and to_tree_path(toplevel) or false
            remaining = remaining - 1
            if remaining == 0 then
                collect_status()
            end
        end)
    end
end

local function open_entry(state, mode)
    local entry = selected_entry(state)
    if not entry then
        return
    end
    if entry.directory then
        if entry.path ~= state.root then
            state.expanded[entry.path] = not state.expanded[entry.path]
            render(state)
            refresh_git(state, true)
        end
        return
    end
    local windows = sidebar.editor_windows()
    local target
    for _, window in ipairs(windows) do
        if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(window)) == entry.path then
            if mode ~= "preview" then
                vim.api.nvim_set_current_win(window)
                vim.bo[vim.api.nvim_win_get_buf(window)].bufhidden = ""
            end
            return
        end
    end
    if #windows > 0 then
        target = sidebar.pick_editor_window(windows)
        if not target then
            return
        end
    end
    local was_loaded = false
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_get_name(buffer) == entry.path and vim.api.nvim_buf_is_loaded(buffer) then
            was_loaded = true
            break
        end
    end
    local ok, open_error = pcall(function()
        if target then
            vim.api.nvim_set_current_win(target)
            local buffer = vim.api.nvim_win_get_buf(target)
            if mode == "edit" or mode == "preview" then
                if not vim.o.hidden and vim.bo[buffer].modified then
                    vim.cmd("belowright vsplit")
                end
            else
                vim.cmd(mode == "vertical" and "belowright vsplit" or "belowright split")
            end
        else
            vim.api.nvim_set_current_win(state.window)
            vim.cmd("belowright vsplit")
        end
        vim.api.nvim_cmd({ cmd = "edit", args = { entry.path } }, {})
        local buffer = vim.api.nvim_get_current_buf()
        if mode == "preview" and not was_loaded then
            vim.bo[buffer].bufhidden = "delete"
            vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
                buffer = buffer,
                once = true,
                callback = function()
                    vim.bo[buffer].bufhidden = ""
                end,
            })
        elseif mode ~= "preview" then
            vim.bo[buffer].bufhidden = ""
        end
    end)
    if is_valid_window(state.window) then
        sidebar.restore_width()
        if mode == "preview" or not ok then
            vim.api.nvim_set_current_win(state.window)
        end
    end
    if not ok then
        report_error(open_error)
    end
end

local function matching_buffers(path)
    local buffers = {}
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        local name = vim.api.nvim_buf_get_name(buffer)
        if name == path or name:sub(1, #path + 1) == path .. "/" then
            table.insert(buffers, buffer)
        end
    end
    return buffers
end

local function create_entry(state)
    local entry = selected_entry(state)
    local directory = entry and (entry.directory and entry.path or vim.fs.dirname(entry.path)) or state.root
    vim.ui.input({ prompt = "Create (trailing / for directory): ", default = directory .. "/" }, function(path)
        if not path or path == "" then
            return
        end
        local is_directory = path:sub(-1) == "/"
        path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("/+$", "")
        local ok, create_error = pcall(function()
            if compat.uv.fs_lstat(path) then
                error("Path already exists: " .. path)
            end
            vim.fn.mkdir(is_directory and path or vim.fs.dirname(path), "p")
            if not is_directory then
                local descriptor, file_error = compat.uv.fs_open(path, "wx", 420)
                if not descriptor then
                    error(file_error)
                end
                compat.uv.fs_close(descriptor)
            end
        end)
        if not ok then
            report_error(create_error)
        end
        state.expanded[directory] = true
        render(state, path)
        refresh_git(state)
    end)
end

local function delete_entry(state)
    local entry = selected_entry(state)
    if not entry or entry.path == state.root then
        return
    end
    local buffers = matching_buffers(entry.path)
    for _, buffer in ipairs(buffers) do
        if vim.bo[buffer].modified then
            report_error("Save or discard changes before deleting: " .. vim.api.nvim_buf_get_name(buffer))
            return
        end
    end
    vim.ui.select({ "Cancel", "Delete" }, { prompt = "Delete " .. entry.path .. "?" }, function(choice)
        if choice ~= "Delete" then
            return
        end
        for _, buffer in ipairs(matching_buffers(entry.path)) do
            if vim.bo[buffer].modified then
                report_error("File has unsaved changes")
                return
            end
        end
        local stat = compat.uv.fs_lstat(entry.path)
        local flags = stat and stat.type == "directory" and "rf" or ""
        if vim.fn.delete(entry.path, flags) ~= 0 then
            report_error("Could not delete: " .. entry.path)
            return
        end
        for _, buffer in ipairs(buffers) do
            if vim.api.nvim_buf_is_valid(buffer) then
                vim.api.nvim_buf_delete(buffer, { force = false })
            end
        end
        render(state)
        refresh_git(state)
    end)
end

local function rename_entry(state)
    local entry = selected_entry(state)
    if not entry or entry.path == state.root then
        return
    end
    vim.ui.input({ prompt = "Rename: ", default = entry.path }, function(path)
        if not path or path == "" then
            return
        end
        path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("/+$", "")
        if path == entry.path then
            return
        end
        if compat.uv.fs_lstat(path) then
            report_error("Path already exists: " .. path)
            return
        end
        for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
            local name = vim.api.nvim_buf_get_name(buffer)
            if name == path or name:sub(1, #path + 1) == path .. "/" then
                report_error("Destination has an existing buffer: " .. name)
                return
            end
        end
        local renamed, rename_error = compat.uv.fs_rename(entry.path, path)
        if not renamed then
            report_error(rename_error)
            return
        end
        for _, buffer in ipairs(matching_buffers(entry.path)) do
            local suffix = vim.api.nvim_buf_get_name(buffer):sub(#entry.path + 1)
            vim.api.nvim_buf_set_name(buffer, path .. suffix)
        end
        local expanded = {}
        for directory, value in pairs(state.expanded) do
            if directory == entry.path or directory:sub(1, #entry.path + 1) == entry.path .. "/" then
                directory = path .. directory:sub(#entry.path + 1)
            end
            expanded[directory] = value
        end
        state.expanded = expanded
        render(state, path)
        refresh_git(state)
    end)
end

local function change_root(state, path, selected_path)
    path = vim.fs.normalize(path)
    if path == state.root or vim.fn.isdirectory(path) ~= 1 then
        return
    end
    local ok, cd_error = pcall(vim.api.nvim_cmd, { cmd = "tcd", args = { path } }, {})
    if not ok then
        report_error(cd_error)
        return
    end
    state.root = path
    render(state, selected_path)
    refresh_git(state)
end

local function change_root_to_parent(state)
    local parent = vim.fs.dirname(state.root)
    if parent == state.root then
        return
    end
    local entry = selected_entry(state)
    -- 元のルートを展開しておき、カーソル位置のエントリを見失わないようにする
    state.expanded[state.root] = true
    change_root(state, parent, entry and entry.path or state.root)
end

local function change_root_to_node(state)
    local entry = selected_entry(state)
    if not entry then
        return
    end
    if entry.path == state.root then
        change_root_to_parent(state)
    elseif entry.directory then
        change_root(state, entry.path)
    else
        change_root(state, vim.fs.dirname(entry.path), entry.path)
    end
end

local function create_tree_buffer(state)
    if not state.buffer or not vim.api.nvim_buf_is_valid(state.buffer) then
        state.buffer = vim.api.nvim_create_buf(false, true)
        vim.bo[state.buffer].bufhidden = "hide"
        vim.bo[state.buffer].filetype = "revim_tree"
        vim.bo[state.buffer].swapfile = false
        local function map(key, callback, description)
            vim.keymap.set("n", key, callback, { buffer = state.buffer, silent = true, desc = description })
        end
        for key, mode in pairs({ ["<CR>"] = "edit", ["<Tab>"] = "preview", ["<C-v>"] = "vertical",
            ["<C-x>"] = "horizontal" }) do
            map(key, function() open_entry(state, mode) end, "tree: " .. mode)
        end
        map("a", function() create_entry(state) end, "tree: create")
        map("d", function() delete_entry(state) end, "tree: delete")
        map("r", function() rename_entry(state) end, "tree: rename")
        map("R", function()
            render(state)
            refresh_git(state)
        end, "tree: refresh")
        map("-", function() change_root_to_parent(state) end, "tree: change root to parent")
        map("<C-]>", function() change_root_to_node(state) end, "tree: change root to node")
        map("q", M.toggle, "tree: close")
    end
    return state.buffer
end

function M.toggle()
    sidebar.toggle("file")
end

local function open_directory(buffer, window, path)
    if not is_valid_window(window) or not vim.api.nvim_buf_is_valid(buffer)
        or vim.api.nvim_win_get_buf(window) ~= buffer or vim.bo[buffer].modified
        or vim.fs.normalize(vim.api.nvim_buf_get_name(buffer)) ~= path or vim.fn.isdirectory(path) ~= 1
    then
        return
    end
    local origin = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(window)
    local state = get_state()
    if state.root ~= path then
        state.root = path
        state.expanded = {}
    end
    if state.window == window and state.buffer and vim.api.nvim_buf_is_valid(state.buffer) then
        vim.api.nvim_win_set_buf(window, state.buffer)
    else
        local previous = vim.fn.bufnr("#")
        local previous_path = previous > 0 and vim.api.nvim_buf_get_name(previous) or ""
        if previous <= 0 or not vim.api.nvim_buf_is_valid(previous) or vim.bo[previous].buftype ~= ""
            or vim.fn.isdirectory(previous_path) == 1
        then
            previous = vim.api.nvim_create_buf(true, false)
        end
        vim.api.nvim_win_set_buf(window, previous)
    end
    sidebar.show("file")
    if #vim.fn.win_findbuf(buffer) == 0 then
        vim.api.nvim_buf_delete(buffer, { force = false })
    end
    if origin ~= window and is_valid_window(origin) then
        vim.api.nvim_set_current_win(origin)
    end
end

local function setup_git(group)
    git_enabled = git.is_available()
    if not git_enabled then
        return
    end
    -- 色は Git Signs (ExGit*) に合わせる
    local function set_highlights()
        vim.api.nvim_set_hl(0, "ExTreeGitStaged", { link = "ExGitAdd", default = true })
        vim.api.nvim_set_hl(0, "ExTreeGitDirty", { link = "ExGitChange", default = true })
        vim.api.nvim_set_hl(0, "ExTreeGitDeleted", { link = "ExGitDelete", default = true })
        vim.api.nvim_set_hl(0, "ExTreeGitNew", { fg = "#56b6c2", default = true })
        vim.api.nvim_set_hl(0, "ExTreeGitRenamed", { fg = "#c678dd", default = true })
        vim.api.nvim_set_hl(0, "ExTreeGitMerge", { fg = "#d19a66", bold = true, default = true })
        vim.api.nvim_set_hl(0, "ExTreeGitIgnored", { link = "Comment", default = true })
    end
    set_highlights()
    vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_highlights })
    -- 保存・フォーカス復帰・端末や :! での git 操作の後に、表示中のツリーを更新する
    vim.api.nvim_create_autocmd({ "BufWritePost", "FocusGained", "TermLeave", "TermClose", "ShellCmdPost" }, {
        group = group,
        callback = function()
            for _, state in pairs(states) do
                refresh_git(state)
            end
        end,
    })
end

function M.setup()
    sidebar.register("file", {
        create = function()
            return create_tree_buffer(get_state())
        end,
        refresh = function()
            local state = get_state()
            state.window = sidebar.get_window()
            render(state)
            refresh_git(state)
        end,
        dispose = function(context)
            states[context.tabpage] = nil
        end,
    })
    vim.g.loaded_netrw = 1
    vim.g.loaded_netrwPlugin = 1
    vim.keymap.set("n", "<C-e>", M.toggle, { desc = "tree: toggle" })
    vim.api.nvim_create_user_command("Ex", M.toggle, {})
    local group = vim.api.nvim_create_augroup("revim_file_tree", { clear = true })
    setup_git(group)
    vim.api.nvim_create_autocmd("BufEnter", {
        group = group,
        callback = function(options)
            local window = vim.api.nvim_get_current_win()
            local path = vim.api.nvim_buf_get_name(options.buf)
            if vim.api.nvim_win_get_config(window).relative ~= "" or vim.fn.isdirectory(path) ~= 1 then
                return
            end
            path = vim.fs.normalize(path)
            vim.schedule(function() open_directory(options.buf, window, path) end)
        end,
    })
end

return M
