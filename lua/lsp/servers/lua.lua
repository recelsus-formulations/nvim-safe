-- name: vim.lsp.config / vim.lsp.enable に渡すサーバー名
-- package: Mason のパッケージ名 (:LspInstall で使用。Mason を使わないなら省略可)
-- requires: インストール・利用に必要な外部コマンド ("a|b" はいずれか)。bin/check.sh が参照する
-- config: vim.lsp.config に渡す設定 (:help lsp-config)
return {
    name = "lua_ls",
    package = "lua-language-server",
    requires = {},
    config = {
        cmd = { "lua-language-server" },
        filetypes = { "lua" },
        root_markers = { ".luarc.json", ".luarc.jsonc", ".stylua.toml", "stylua.toml", ".git" },
        settings = {
            Lua = {
                runtime = { version = "LuaJIT" },
                workspace = {
                    checkThirdParty = false,
                    library = { vim.env.VIMRUNTIME },
                },
            },
        },
    },
}
