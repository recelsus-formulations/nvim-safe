-- Assembly
-- 必要: cargo (Mason が cargo install でビルドする)
return {
    name = "asm_lsp",
    package = "asm-lsp",
    requires = { "cargo" },
    config = {
        cmd = { "asm-lsp" },
        filetypes = { "asm", "vmasm" },
        root_markers = { ".asm-lsp.toml", ".git" },
    },
}
