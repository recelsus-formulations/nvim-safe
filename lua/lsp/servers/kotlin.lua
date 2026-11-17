-- Kotlin (JetBrains 公式の kotlin-lsp)
-- 必要: Mason 側は無し (実行環境は配布物に同梱)
return {
    name = "kotlin_lsp",
    package = "kotlin-lsp",
    requires = {},
    config = {
        cmd = { "intellij-server", "--stdio" },
        filetypes = { "kotlin" },
        root_markers = {
            "settings.gradle",
            "settings.gradle.kts",
            "pom.xml",
            "build.gradle",
            "build.gradle.kts",
            "workspace.json",
        },
    },
}
