local M = {}

function M.setup()
    local opt = vim.opt

    vim.g.mapleader = " "

    opt.title = true
    opt.encoding = "utf-8"
    opt.fileformats = { "unix" }
    opt.mouse = "a"
    opt.termguicolors = true
    opt.ambiwidth = "double"

    opt.tabstop = 2
    opt.softtabstop = 2
    opt.shiftwidth = 2
    opt.expandtab = true
    opt.autoindent = true
    opt.smartindent = true

    opt.number = true
    opt.cursorline = true
    opt.showtabline = 2
    opt.cmdheight = 2
    opt.signcolumn = "yes"
    opt.wrap = false
    opt.errorbells = false
    opt.matchtime = 0

    opt.incsearch = true
    opt.ignorecase = true
    opt.smartcase = true
    opt.hlsearch = true
    opt.wrapscan = true
    opt.showcmd = true
    opt.wildmenu = true

    opt.hidden = true
    opt.writebackup = false
    opt.backup = false
    opt.swapfile = false
    opt.autoread = true
    opt.undofile = true
    opt.undodir = vim.fs.joinpath(vim.fn.stdpath("cache"), "undo")
    vim.fn.mkdir(opt.undodir:get()[1], "p")

    opt.clipboard:append("unnamedplus")
    opt.ttimeout = true
    opt.ttimeoutlen = 50
    opt.timeoutlen = 600
    opt.nrformats = ""
    opt.whichwrap = "h,l,<,>,[,],~"
    opt.virtualedit = "block"
    opt.splitbelow = true
    opt.splitright = true

    vim.cmd.syntax("enable")
end

return M
