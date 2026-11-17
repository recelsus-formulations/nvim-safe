-- Java
-- 必要: Java 21 以上、python3 (jdtls の起動スクリプト)
local compat = require("compat")
local root_markers = {
    "mvnw",
    "gradlew",
    "settings.gradle",
    "settings.gradle.kts",
    "build.xml",
    "pom.xml",
    "build.gradle",
    "build.gradle.kts",
    ".git",
}

return {
    name = "jdtls",
    package = "jdtls",
    requires = { "java", "python3" },
    -- cmd が関数のため、有効化の判定に使う実行ファイルを明示する
    executable = "jdtls",
    config = {
        -- jdtls はプロジェクトごとに作業データの保存先 (-data) が必要
        -- config 引数は 0.11.3+ (0.11 未満は lsp/fallback.lua が渡す)。
        -- 0.11.0 - 0.11.2 では渡されないため、接続中のバッファから同じ規則でルートを求める
        cmd = function(dispatchers, config)
            config = config or {}
            local root = config.root_dir or compat.find_root(0, root_markers) or vim.fn.getcwd()
            local data = compat.joinpath(vim.fn.stdpath("cache"), "jdtls", (root:gsub("[/\\:]", "%%")))
            return compat.lsp_rpc_start({ "jdtls", "-data", data }, dispatchers, {
                cwd = config.cmd_cwd,
                env = config.cmd_env,
            })
        end,
        filetypes = { "java" },
        root_markers = root_markers,
    },
}
