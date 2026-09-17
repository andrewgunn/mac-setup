-- Auto-activate project .venv (same idea as VS Code's Python: Select Interpreter).

local function find_venv_python(start)
  local path = start
  while path and path ~= "" do
    for _, rel in ipairs({ ".venv/bin/python", "venv/bin/python" }) do
      local candidate = path .. "/" .. rel
      if vim.uv.fs_stat(candidate) then
        return candidate
      end
    end
    local parent = vim.fs.dirname(path)
    if parent == path then
      break
    end
    path = parent
  end
end

local function activate_project_venv(buf)
  local ok, vs = pcall(require, "venv-selector")
  if not ok then
    return
  end
  if vs.python() then
    return
  end
  local name = vim.api.nvim_buf_get_name(buf)
  local py = find_venv_python(name ~= "" and vim.fs.dirname(name) or vim.uv.cwd())
  if py then
    vs.activate_from_path(py, "venv")
  end
end

return {
  {
    "linux-cultist/venv-selector.nvim",
    opts = {
      options = {
        notify_user_on_venv_activation = true,
        cached_venv_automatic_activation = true,
      },
    },
    config = function(_, opts)
      require("venv-selector").setup(opts)
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "python",
        callback = function(event)
          vim.schedule(function()
            activate_project_venv(event.buf)
          end)
        end,
      })
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- Cursor/VS Code: python.languageServer = "None", formatter = Ruff.
        -- Keep Pyright for Ctrl-click / hover, but don't surface type errors.
        pyright = {
          settings = {
            python = {
              analysis = {
                typeCheckingMode = "off",
                autoSearchPaths = true,
                useLibraryCodeForTypes = true,
                diagnosticMode = "openFilesOnly",
              },
            },
          },
        },
      },
    },
  },
}
