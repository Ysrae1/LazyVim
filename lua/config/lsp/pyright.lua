-- Options are merged into LazyVim's server configuration in plugins/lspconfig.lua.
local root_markers = {
  "pyrightconfig.json", "pyproject.toml", "setup.py", "setup.cfg",
  "requirements.txt", "Pipfile", ".venv", "venv", ".git",
}

local function environment_python(directory)
  if not directory or directory == "" then
    return
  end
  for _, relative in ipairs({ "bin/python", "Scripts/python.exe" }) do
    local path = vim.fs.joinpath(directory, relative)
    if vim.fn.executable(path) == 1 then
      return path
    end
  end
end

local function resolve_python(root)
  for _, name in ipairs({ ".venv", "venv" }) do
    local path = environment_python(vim.fs.joinpath(root, name))
    if path then
      return path
    end
  end
  for _, name in ipairs({ "VIRTUAL_ENV", "CONDA_PREFIX" }) do
    local path = environment_python(vim.env[name])
    if path then
      return path
    end
  end
  for _, name in ipairs({ "python", "python3" }) do
    local path = vim.fn.exepath(name)
    if path ~= "" then
      return path
    end
  end
end

return {
  -- Give standalone files their own workspace instead of sharing a rootless client.
  root_dir = function(bufnr, on_dir)
    local file = vim.api.nvim_buf_get_name(bufnr)
    on_dir(vim.fs.root(bufnr, root_markers) or vim.fs.dirname(file) or vim.fn.getcwd())
  end,
  before_init = function(_, config)
    config.settings = config.settings or {}
    config.settings.python = config.settings.python or {}
    local python = config.settings.python
    -- Keep an explicitly selected interpreter; otherwise resolve this workspace once.
    if not python.pythonPath or python.pythonPath == "" then
      python.pythonPath = resolve_python(config.root_dir or vim.fn.getcwd())
    end
  end,
  settings = {
    python = {
      analysis = {
        typeCheckingMode = "basic",
      },
    },
  },
}
