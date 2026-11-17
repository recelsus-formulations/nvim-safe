-- Go
-- 必要: go (Mason が go install でビルドする)
return {
    name = "gopls",
    package = "gopls",
    requires = { "go" },
    config = {
        cmd = { "gopls" },
        filetypes = { "go", "gomod", "gowork", "gotmpl" },
        root_markers = { "go.work", "go.mod", ".git" },
    },
}
