-- Swift
-- Mason には無いため package は省略。Swift ツールチェーン同梱の sourcekit-lsp を PATH から使う
return {
    name = "sourcekit",
    requires = {},
    config = {
        cmd = { "sourcekit-lsp" },
        -- c / cpp は clangd に任せる
        filetypes = { "swift" },
        root_markers = { "buildServer.json", ".bsp", "Package.swift", "compile_commands.json", ".git" },
    },
}
