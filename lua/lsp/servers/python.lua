-- Python
-- 必要: npm
return {
    name = "pyright",
    package = "pyright",
    requires = { "npm" },
    runtime_requires = { "node" },
    config = {
        cmd = { "pyright-langserver", "--stdio" },
        filetypes = { "python" },
        root_markers = {
            "pyrightconfig.json",
            "pyproject.toml",
            "setup.py",
            "setup.cfg",
            "requirements.txt",
            "Pipfile",
            ".git",
        },
        settings = {
            python = {
                analysis = {
                    autoSearchPaths = true,
                    useLibraryCodeForTypes = true,
                    diagnosticMode = "openFilesOnly",
                },
            },
        },
    },
}
