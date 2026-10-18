local M = {}

M.default_kernel = "glow-python"
M.molten_commit = "bedea63819c618e007e7c40059fc6e72d598c8df"
M.jupytext_commit = "c8baf3ad344c59b3abd461ecc17fc16ec44d0f7b"

function M.directory()
  return vim.fn.stdpath("data") .. "/glow-notebook-venv"
end

function M.python()
  return M.directory() .. (vim.fn.has("win32") == 1 and "/Scripts/python.exe" or "/bin/python")
end

function M.jupytext()
  return M.directory() .. (vim.fn.has("win32") == 1 and "/Scripts/jupytext.exe" or "/bin/jupytext")
end

-- Called by lazy's init phase, before the Python remote-plugin host starts.
-- An explicitly configured host belongs to the user and remains authoritative.
function M.prepare_host()
  if not vim.g.python3_host_prog or vim.g.python3_host_prog == "" then
    if vim.fn.executable(M.python()) == 1 then
      vim.g.python3_host_prog = M.python()
    end
  end
end

function M.ready()
  return vim.fn.executable(M.python()) == 1 and vim.fn.executable(M.jupytext()) == 1
end

function M.convert(args)
  local command = { M.jupytext() }
  vim.list_extend(command, args)
  local output = vim.fn.system(command)
  if vim.v.shell_error ~= 0 then
    error("Notebook conversion failed: " .. output)
  end
  return output
end

local cache_directory

function M.sidecar(filename, extension)
  if not cache_directory then
    cache_directory = vim.fn.stdpath("cache") .. "/glow-notebook/" .. vim.fn.getpid() .. "-" .. vim.uv.hrtime()
    vim.fn.mkdir(cache_directory, "p", 448)
  end
  local original = vim.fn.resolve(vim.fn.fnamemodify(filename, ":p"))
  return cache_directory .. "/" .. vim.fn.sha256(original) .. "." .. extension
end

-- Upstream jupytext.nvim currently hardcodes the `jupytext` command. Keep its
-- format and buffer handling, but select our isolated CLI without changing PATH
-- (which would also change unrelated LSP, terminal, and Python processes).
function M.configure_jupytext()
  local commands = require("jupytext.commands")
  -- Never create, overwrite, or remove a user's same-basename Python script.
  local utils = require("jupytext.utils")
  utils.get_jupytext_file = M.sidecar
  -- Minimal valid nbformat files may omit kernelspec metadata. This first
  -- editable frontend is Python; report other declared languages explicitly.
  utils.get_ipynb_metadata = function(filename)
    local stat = vim.uv.fs_stat(filename)
    if not stat or stat.type ~= "file" or stat.size > 32 * 1024 * 1024 then
      error("请选择不超过 32 MiB 的本地 Notebook 文件。")
    end
    local file = assert(io.open(filename, "rb"))
    local raw = file:read("*a"); file:close()
    local document = vim.json.decode(raw)
    if type(document) ~= "table" or document.nbformat ~= 4 or type(document.cells) ~= "table" then
      error("原生 Notebook 编辑需要 nbformat 4。")
    end
    local metadata = document.metadata or {}
    local language = (metadata.kernelspec or {}).language or (metadata.language_info or {}).name or "python"
    if language:lower() ~= "python" and language:lower() ~= "python3" then
      error("原生 Notebook 首版支持 Python；其他语言可用 :GlowNotebookPreview 查看保存输出。")
    end
    return { language = "python", extension = "py" }
  end
  local group = vim.api.nvim_create_augroup("GlowNotebookRuntime", { clear = true })
  -- Register before upstream's BufReadCmd. Reload must convert the current
  -- notebook from disk, rather than reusing this session's old private sidecar.
  vim.api.nvim_create_autocmd("BufReadCmd", {
    group = group,
    pattern = "*.ipynb",
    callback = function(ev)
      vim.fn.delete(M.sidecar(ev.match, "py"))
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if cache_directory then
        vim.fn.delete(cache_directory, "rf")
      end
    end,
  })
  commands.run_jupytext_command = function(input_file, options)
    -- The pinned upstream supplies shellescape(path) for paths. Decode exactly
    -- that quoting and pass argv directly, so no shell evaluates notebook names.
    local function argument(value)
      if value:sub(1, 1) == "'" and value:sub(-1) == "'" then
        return (value:sub(2, -2):gsub("'\\''", "'"))
      end
      return value
    end
    local args = { argument(input_file) }
    for _, key in ipairs(vim.fn.sort(vim.tbl_keys(options))) do
      local value = options[key]
      args[#args + 1] = key
      if value ~= "" then
        args[#args + 1] = argument(value)
      end
    end
    return M.convert(args)
  end
  require("jupytext").setup({
    style = "percent",
    output_extension = "py",
    force_ft = "python",
  })
end

function M.configure_molten()
  M.prepare_host()
  vim.g.molten_auto_init_behavior = "raise"
  vim.g.molten_auto_open_output = false
  vim.g.molten_virt_text_output = true
  vim.g.molten_virt_lines_off_by_1 = false
  vim.g.molten_virt_text_max_lines = 16
  vim.g.molten_wrap_output = true
  vim.g.molten_tick_rate = 100
  vim.g.molten_image_provider = "none"
  vim.g.molten_image_location = "float"
  local ok, images = pcall(require, "config.media.molten_images")
  if ok and images.setup() then
    -- Only Molten's load_image_nvim module is adapted; terminal image plugins
    -- and other consumers of require("image") keep their own implementations.
    vim.g.molten_image_provider = "image.nvim"
  end
end

return M
