local config_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
vim.opt.runtimepath:prepend(config_root)
package.path = config_root .. "/lua/?.lua;" .. config_root .. "/lua/?/init.lua;" .. package.path

local function load_config(name)
    return dofile(config_root .. "/lua/conf.d/" .. name .. ".lua")
end

local environment = load_config("environment").detect()
load_config("clipboard").setup(environment)
require("config").setup()
vim.cmd.colorscheme("slate")
require("tree-sitter").setup()

require("ex.sidebar").setup()
require("ex.tree").setup()
require("ex.symbol").setup()
require("ex.term").setup()
require("ex.pairs").setup()
require("ex.jump").setup()
require("ex.scope").setup()
require("ex.illuminate").setup()
require("ex.panel").setup()
require("ex.find").setup()

if require("ex.git").is_available() then
    require("ex.signs").setup()
end
require("lsp").setup()
require("command").setup()
require("completion").setup()
load_config("highlight").setup()
