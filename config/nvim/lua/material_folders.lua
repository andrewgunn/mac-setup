-- Nerd Font folder glyphs for neo-tree. Ghostty falls back to its bundled
-- Nerd Font symbols for these, so the main font doesn't have to be a patched one.
local M = {}

M.default_color = "#90a4ae"
M.folder_closed = "󰉋"
M.folder_open = "󰝰"

function M.icon_for(_, opened)
  local glyph = opened and M.folder_open or M.folder_closed
  return glyph, M.default_color
end

return M
