local compat = require("compat")
local binaries = {}

local function resolve_binary(root)
    local candidates = {
        compat.joinpath(root, "node_modules", ".bin", "tsc"),
        vim.fn.exepath("tsc"),
    }
    for _, candidate in ipairs(candidates) do
        if candidate ~= "" and vim.fn.executable(candidate) == 1 then
            local result = compat.system({ candidate, "--version" }):wait(3000)
            local major = result and tonumber((result.stdout or ""):match("(%d+)%."))
            if result and result.code == 0 and major and major >= 7 then
                return candidate
            end
        end
    end
end

return {
    name = "tsc",
    requires = { "npm" },
    runtime_requires = { "node" },
    executable = "tsc",
    is_available = function() return true end,
    install_hint = "Install TypeScript 7+ in the project or on PATH; Mason does not provide this server.",
    config = {
        cmd = function(dispatchers, config)
            return compat.lsp_rpc_start({ binaries[config.root_dir], "--lsp", "--stdio" }, dispatchers)
        end,
        filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
        root_dir = function(buffer, on_dir)
            local root = compat.find_root(buffer, {
                "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lock",
                "package.json", "tsconfig.json", "jsconfig.json",
            }) or compat.find_root(buffer, { ".git" }) or vim.fn.getcwd()
            local binary = resolve_binary(root)
            if binary then
                binaries[root] = binary
                on_dir(root)
            end
        end,
        settings = {
            ["js/ts"] = {
                inlayHints = {
                    parameterNames = { enabled = "literals", suppressWhenArgumentMatchesName = true },
                    parameterTypes = { enabled = true },
                    variableTypes = { enabled = true },
                    propertyDeclarationTypes = { enabled = true },
                    functionLikeReturnTypes = { enabled = true },
                    enumMemberValues = { enabled = true },
                },
            },
        },
    },
}
