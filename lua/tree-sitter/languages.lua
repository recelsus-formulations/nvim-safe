-- :TreesitterInstall で取得する parser (nvim-treesitter の言語名)
-- Neovim 同梱の parser (c, lua, vim, vimdoc, query, markdown, markdown_inline) も含める。
-- nvim-treesitter を読み込むとそちらの query が優先されるため、parser も合わせて更新しておく
return {
    -- Neovim 同梱
    "c",
    "lua",
    "vim",
    "vimdoc",
    "query",
    "markdown",
    "markdown_inline",

    -- lsp/servers と同じ言語
    "cpp",
    "asm",
    "python",
    "javascript",
    "typescript",
    "tsx",
    "jsdoc",
    "luadoc",
    "php",
    "phpdoc",
    "html",
    "css",
    "bash",
    "java",
    "go",
    "gomod",
    "gosum",
    "rust",
    "kotlin",
    "swift",

    -- 設定ファイル・Git など
    "json",
    "yaml",
    "toml",
    "regex",
    "diff",
    "gitcommit",
    "git_rebase",
    "gitignore",
}
