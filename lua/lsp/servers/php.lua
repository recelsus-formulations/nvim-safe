local compat = require("compat")

local function is_cakephp(root)
    local composer_file = compat.joinpath(root, "composer.json")
    if vim.fn.filereadable(composer_file) ~= 1 then
        return false
    end
    local ok, composer = pcall(vim.fn.json_decode, table.concat(vim.fn.readfile(composer_file), "\n"))
    if not ok or type(composer) ~= "table" then
        return false
    end
    return type(composer.require) == "table" and composer.require["cakephp/cakephp"] ~= nil
end

return {
    name = "intelephense",
    package = "intelephense",
    requires = { "npm" },
    config = {
        cmd = { "intelephense", "--stdio" },
        filetypes = { "php" },
        root_markers = { "composer.json", ".git" },
        before_init = function(params, config)
            local root = type(config.root_dir) == "string" and config.root_dir
                or (params.rootUri and vim.uri_to_fname(params.rootUri))
            if not root or not is_cakephp(root) then
                return
            end
            config.settings = config.settings or {}
            config.settings.intelephense = config.settings.intelephense or {}
            local settings = config.settings.intelephense
            settings.files = settings.files or {}
            settings.files.associations = { "*.php", "*.phtml", "*.ctp" }
            local webroot = compat.joinpath(root, "webroot")
            if vim.fn.isdirectory(webroot) == 1 then
                settings.environment = settings.environment or {}
                settings.environment.documentRoot = webroot
            end
        end,
        settings = {
            intelephense = {
                telemetry = { enabled = false },
            },
        },
    },
}
