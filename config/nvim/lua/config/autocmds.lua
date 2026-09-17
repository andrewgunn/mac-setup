local preview = require("vscode_preview")

local function is_dir_buf(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  return name ~= "" and vim.fn.isdirectory(name) == 1
end

local function unlisted_scratch()
  local scratch = vim.api.nvim_create_buf(false, true)
  vim.bo[scratch].bufhidden = "wipe"
  vim.bo[scratch].buftype = "nofile"
  return scratch
end

-- `nvim .` would otherwise keep a directory buffer (netrw) in the main pane.
vim.api.nvim_create_autocmd("BufEnter", {
  desc = "Don't keep directory buffers in the editor",
  callback = function(event)
    if not is_dir_buf(event.buf) then
      return
    end
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(event.buf) then
        return
      end
      if vim.api.nvim_get_current_buf() == event.buf then
        vim.api.nvim_set_current_buf(unlisted_scratch())
      end
      pcall(vim.api.nvim_buf_delete, event.buf, { force = true })
      preview.wipe_unnamed()
    end)
  end,
})

-- Explorer on the left, empty unlisted editor on the right (no [No Name] tab).
vim.api.nvim_create_autocmd("UIEnter", {
  desc = "Open file explorer on startup",
  callback = function()
    local arg = vim.fn.argv(0)
    local stat = arg ~= "" and vim.uv.fs_stat(arg) or nil
    if arg ~= "" and (not stat or stat.type ~= "directory") then
      return
    end
    vim.schedule(function()
      local buf = vim.api.nvim_get_current_buf()
      if is_dir_buf(buf) or vim.bo[buf].filetype == "netrw" then
        vim.api.nvim_set_current_buf(unlisted_scratch())
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
      preview.wipe_unnamed()
      pcall(function()
        require("neo-tree.command").execute({ action = "show", dir = vim.uv.cwd() })
      end)
    end)
  end,
})
