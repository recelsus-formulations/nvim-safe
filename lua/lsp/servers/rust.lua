-- Rust
-- 必要: Mason 側は無し。解析には cargo / rustc (rustup) が必要
return {
    name = "rust_analyzer",
    package = "rust-analyzer",
    requires = { "cargo" },
    config = {
        cmd = { "rust-analyzer" },
        filetypes = { "rust" },
        root_markers = { "Cargo.toml", "rust-project.json", ".git" },
    },
}
