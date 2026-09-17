-- Persistent VS Code-style explorer.

local preview = require("vscode_preview")
local folders = require("material_folders")

local hl_defined = {}
local function folder_hl(color)
  local name = "MaterialFolder" .. color:gsub("#", "")
  if not hl_defined[name] then
    vim.api.nvim_set_hl(0, name, { fg = color })
    hl_defined[name] = true
  end
  return name
end

local function skip_root(node)
  return not node or node:get_depth() == 1
end

local function on_single_click(state)
  local node = state.tree:get_node()
  if skip_root(node) then
    return
  end
  if node.type == "directory" then
    require("neo-tree.sources.filesystem.commands").toggle_node(state)
    return
  end
  if node.type == "file" then
    preview.preview(node.path)
  end
end

-- Enter: open the file and move the cursor into it (keyboard flow).
local function on_enter(state)
  local node = state.tree:get_node()
  if skip_root(node) then
    return
  end
  if node.type == "directory" then
    require("neo-tree.sources.filesystem.commands").toggle_node(state)
    return
  end
  if node.type == "file" then
    local tree_win = vim.api.nvim_get_current_win()
    preview.pin(node.path)
    local win = preview.editor_win(tree_win)
    if win then
      vim.api.nvim_set_current_win(win)
    end
  end
end

local function on_double_click(state)
  local node = state.tree:get_node()
  if skip_root(node) then
    return
  end
  if node.type == "directory" then
    require("neo-tree.sources.filesystem.commands").toggle_node(state)
    return
  end
  if node.type == "file" then
    preview.pin(node.path)
  end
end

-- Keyboard crawl: j/k previews the file under the cursor, same as a click.
local preview_seq = 0
local function preview_under_cursor()
  if vim.bo.filetype ~= "neo-tree" then
    return
  end
  preview_seq = preview_seq + 1
  local seq = preview_seq
  vim.defer_fn(function()
    if seq ~= preview_seq or vim.bo.filetype ~= "neo-tree" then
      return
    end
    local ok, manager = pcall(require, "neo-tree.sources.manager")
    if not ok then
      return
    end
    local state = manager.get_state("filesystem")
    if not state or not state.tree or state.winid ~= vim.api.nvim_get_current_win() then
      return
    end
    local node = state.tree:get_node()
    if skip_root(node) or node.type ~= "file" then
      return
    end
    preview.preview(node.path)
  end, 40)
end

return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    init = function()
      preview.setup()
      vim.api.nvim_create_autocmd("ColorScheme", {
        callback = function()
          hl_defined = {}
        end,
      })
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "neo-tree",
        callback = function(event)
          vim.api.nvim_create_autocmd("CursorMoved", {
            buffer = event.buf,
            callback = preview_under_cursor,
          })
        end,
      })
    end,
    opts = {
      default_component_configs = {
        icon = {
          folder_closed = folders.folder_closed,
          folder_open = folders.folder_open,
          folder_empty = "󰉖",
          folder_empty_open = "󰷏",
          use_filtered_colors = false,
          provider = function(icon, node)
            if node.type == "directory" then
              local glyph, color = folders.icon_for(node.name, node:is_expanded())
              icon.text = glyph
              icon.highlight = folder_hl(color)
            elseif node.type == "file" or node.type == "terminal" then
              local ok, devicons = pcall(require, "nvim-web-devicons")
              if ok then
                local name = node.type == "terminal" and "terminal" or node.name
                local devicon, hl = devicons.get_icon(name)
                icon.text = devicon or icon.text
                icon.highlight = hl or icon.highlight
              end
            end
            return icon
          end,
        },
      },
      filesystem = {
        hijack_netrw_behavior = "open_default",
        follow_current_file = { enabled = true },
        filtered_items = {
          visible = true,
          hide_dotfiles = false,
          hide_gitignored = true,
          hide_hidden = false,
          never_show = { ".git", ".DS_Store" },
        },
        components = {
          name = function(config, node, state)
            if node:get_depth() == 1 then
              node.name = vim.fn.fnamemodify(node.path, ":t")
            end
            return require("neo-tree.sources.common.components").name(config, node, state)
          end,
        },
      },
      window = {
        width = 34,
        mappings = {
          ["<cr>"] = on_enter,
          ["<LeftRelease>"] = on_single_click,
          ["<2-LeftMouse>"] = on_double_click,
          -- Keep `/` as project search, not neo-tree's filter.
          ["/"] = "none",
        },
      },
    },
  },
}
