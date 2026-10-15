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
if vim.treesitter and vim.treesitter.start then
    load_config("treesitter").setup()
end

require("ex.tree").setup()
require("ex.term").setup()
require("ex.pairs").setup()
require("ex.jump").setup()
require("ex.scope").setup()
if vim.fn.executable("git") == 1 then
    require("ex.signs").setup()
end
require("ex.find").setup()
