-- Git branch picker. Bare `c` stays the change operator (cw/cc/ciw).
vim.keymap.set("n", "<leader>gc", function()
  Snacks.picker.git_branches()
end, { desc = "Git Branches" })

-- VS Code: Cmd+P / Ctrl+P: Quick Open. Space is the LazyVim leader.
vim.keymap.set("n", "<C-p>", function()
  LazyVim.pick("files")()
end, { desc = "Find Files" })

-- VS Code: Cmd+Shift+F: Search in files. `/` is the same picker (not in-file search).
local function search_project()
  LazyVim.pick("live_grep")()
end
vim.keymap.set("n", "<C-S-f>", search_project, { desc = "Search in Project" })
vim.keymap.set({ "n", "x" }, "/", search_project, { desc = "Search in Project" })
vim.keymap.set("n", "g/", "/", { noremap = true, desc = "Search in File" })

-- Cmd+E focuses Explorer. It does not hide it.
vim.keymap.set({ "n", "i", "x" }, "<D-e>", function()
  require("neo-tree.command").execute({ action = "focus", dir = LazyVim.root() })
end, { desc = "Focus Explorer" })

-- VS Code: Ctrl/Cmd-click a symbol to go to its definition.
-- Silent if no language server is attached (don't spam vim.lsp warnings).
local function goto_definition_at_click()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<LeftMouse>", true, false, true), "nx", false)
  vim.schedule(function()
    if vim.bo.filetype == "neo-tree" then
      return
    end
    local clients = vim.lsp.get_clients({ bufnr = 0 })
    for _, client in ipairs(clients) do
      local ok = false
      if client.supports_method then
        ok = client:supports_method("textDocument/definition")
      end
      if ok then
        vim.lsp.buf.definition()
        return
      end
    end
  end)
end

vim.keymap.set("n", "<C-LeftMouse>", goto_definition_at_click, { desc = "Goto Definition", silent = true })
vim.keymap.set("n", "<D-LeftMouse>", goto_definition_at_click, { desc = "Goto Definition", silent = true })
vim.keymap.set("n", "<C-RightMouse>", "<C-o>", { desc = "Go Back", silent = true })
