-- Atom One Dark syntax (same as VS Code) on Ghostty's background
-- so the editor sits flush in the terminal.

return {
  {
    "navarasu/onedark.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = "dark", -- classic Atom One Dark highlighting
      term_colors = false,
      ending_tildes = false,
      colors = {
        -- Ghostty background only; syntax colors stay Atom One Dark
        bg0 = "#1D1E27",
        bg_d = "#18191F",
        bg1 = "#282c34",
        bg2 = "#31353f",
        bg3 = "#393f4a",
      },
      highlights = {
        Normal = { fg = "$fg", bg = "$bg0" },
        NormalNC = { fg = "$fg", bg = "$bg0" },
        NormalFloat = { fg = "$fg", bg = "$bg1" },
        FloatBorder = { fg = "$grey", bg = "$bg1" },
        SignColumn = { bg = "$bg0" },
        EndOfBuffer = { fg = "$bg0", bg = "$bg0" },
        WinSeparator = { fg = "$bg1", bg = "$bg0" },
        NeoTreeNormal = { fg = "$fg", bg = "$bg0" },
        NeoTreeNormalNC = { fg = "$fg", bg = "$bg0" },
        NeoTreeEndOfBuffer = { fg = "$bg0", bg = "$bg0" },
        NeoTreeWinSeparator = { fg = "$bg0", bg = "$bg0" },
        NeoTreeVertSplit = { fg = "$bg0", bg = "$bg0" },
      },
    },
    config = function(_, opts)
      require("onedark").setup(opts)
      require("onedark").load()
    end,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "onedark",
    },
  },
}
