-- C / C++ (cpp も含む)
-- 必要: unzip (Mason での展開)。標準ヘッダの解決に gcc または clang
return {
    name = "clangd",
    package = "clangd",
    requires = { "unzip", "gcc|clang" },
    config = {
        cmd = { "clangd" },
        filetypes = { "c", "cpp", "objc", "objcpp", "cuda" },
        root_markers = {
            ".clangd",
            ".clang-tidy",
            ".clang-format",
            "compile_commands.json",
            "compile_flags.txt",
            "configure.ac",
            ".git",
        },
    },
}
