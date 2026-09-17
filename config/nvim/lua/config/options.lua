-- Closer to VS Code while browsing: absolute line numbers, mouse, confirm on quit.
vim.opt.relativenumber = false
vim.opt.mouse = "a"
vim.opt.confirm = true
vim.opt.showtabline = 2

-- Wrap long lines in the editor pane instead of horizontal scroll.
vim.opt.wrap = true
vim.opt.linebreak = true
vim.opt.breakindent = true

-- Never open a directory listing in the main pane (neo-tree owns the tree).
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
