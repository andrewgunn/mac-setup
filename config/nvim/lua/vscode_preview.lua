-- VS Code-style preview editor: single-click reuses one tab, double-click pins it.

local M = {}
M.VAR = "vscode_preview"

local function is_tree_ft(ft)
  return ft == "neo-tree" or ft == "notify" or ft == "noice" or ft == "snacks_notif"
end

function M.editor_win(tree_win)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= tree_win then
      local buf = vim.api.nvim_win_get_buf(win)
      if not is_tree_ft(vim.bo[buf].filetype) then
        return win
      end
    end
  end
end

function M.find_preview()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.b[buf][M.VAR] then
      return buf
    end
  end
end

function M.wipe_unnamed()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_valid(buf)
      and vim.bo[buf].buflisted
      and vim.api.nvim_buf_get_name(buf) == ""
      and not vim.bo[buf].modified
      and vim.bo[buf].buftype == ""
    then
      local n = vim.api.nvim_buf_line_count(buf)
      local first = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
      if n <= 1 and first == "" then
        for _, win in ipairs(vim.fn.win_findbuf(buf)) do
          local scratch = vim.api.nvim_create_buf(false, true)
          vim.bo[scratch].bufhidden = "wipe"
          vim.api.nvim_win_set_buf(win, scratch)
        end
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
  end
end

local function ensure_editor_win(tree_win)
  local win = M.editor_win(tree_win)
  if win then
    return win
  end
  vim.cmd("wincmd l")
  if vim.api.nvim_get_current_win() == tree_win then
    vim.cmd("vsplit")
  end
  return vim.api.nvim_get_current_win()
end

local function load_file(path)
  path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  local buf = vim.fn.bufnr(path)
  if buf <= 0 then
    buf = vim.fn.bufadd(path)
  end
  if not vim.api.nvim_buf_is_loaded(buf) then
    pcall(vim.fn.bufload, buf)
  end
  vim.bo[buf].buflisted = true
  return buf
end

function M.preview(path)
  local tree_win = vim.api.nvim_get_current_win()
  local win = ensure_editor_win(tree_win)
  local buf = load_file(path)

  -- Pinned tabs stay; just switch to them
  if vim.b[buf]._vscode_pinned then
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_set_current_win(tree_win)
    M.wipe_unnamed()
    return
  end

  local old = M.find_preview()
  vim.b[buf][M.VAR] = true
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].breakindent = true

  if old and old ~= buf and vim.api.nvim_buf_is_valid(old) and not vim.b[old]._vscode_pinned then
    vim.b[old][M.VAR] = nil
    if not vim.bo[old].modified and #vim.fn.win_findbuf(old) == 0 then
      pcall(vim.api.nvim_buf_delete, old, { force = false })
    end
  end

  vim.api.nvim_set_current_win(tree_win)
  M.wipe_unnamed()
end

function M.pin(path)
  local tree_win = vim.api.nvim_get_current_win()
  local win = ensure_editor_win(tree_win)
  local buf = load_file(path)
  vim.b[buf][M.VAR] = nil
  vim.b[buf]._vscode_pinned = true
  vim.bo[buf].buflisted = true
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].breakindent = true
  vim.api.nvim_set_current_win(tree_win)
  M.wipe_unnamed()
end

function M.pin_buf(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  vim.b[buf][M.VAR] = nil
  vim.b[buf]._vscode_pinned = true
end

function M.setup()
  vim.api.nvim_create_autocmd({ "InsertEnter", "BufModifiedSet" }, {
    desc = "Pin preview tab when you start editing",
    callback = function(event)
      if vim.b[event.buf][M.VAR] then
        M.pin_buf(event.buf)
      end
    end,
  })
end

return M
