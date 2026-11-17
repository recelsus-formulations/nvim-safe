-- sh / bash
-- 必要: npm (shellcheck を PATH に置くと診断にも使われる)
return {
    name = "bashls",
    package = "bash-language-server",
    requires = { "npm" },
    config = {
        cmd = { "bash-language-server", "start" },
        filetypes = { "sh", "bash" },
        root_markers = { ".git" },
        settings = {
            bashIde = {
                -- ホームディレクトリ直下などで開いた際に再帰的に走査しないようにする
                globPattern = "*@(.sh|.inc|.bash|.command)",
            },
        },
    },
}
