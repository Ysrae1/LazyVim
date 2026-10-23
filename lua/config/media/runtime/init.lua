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
  if vim.fn.has("win32") == 1 and type(vim.g.python3_host_prog) == "string"
      and vim.fs.normalize(vim.g.python3_host_prog):lower() == vim.fs.normalize(M.python()):lower() then
    -- Standalone native Windows uses the same private provider as the packaged
    -- launcher. Molten writes data_dir/runtime even with JUPYTER_RUNTIME_DIR set.
    -- Keep defaults inside this provider and preserve explicit user overrides.
    if not vim.env.JUPYTER_DATA_DIR or vim.env.JUPYTER_DATA_DIR == "" then
      vim.env.JUPYTER_DATA_DIR = M.directory() .. "/share/jupyter"
      vim.fn.mkdir(vim.env.JUPYTER_DATA_DIR .. "/runtime", "p", 448)
    end
    if not vim.env.JUPYTER_RUNTIME_DIR or vim.env.JUPYTER_RUNTIME_DIR == "" then
      vim.env.JUPYTER_RUNTIME_DIR = M.directory() .. "/share/jupyter/runtime"
      vim.fn.mkdir(vim.env.JUPYTER_RUNTIME_DIR, "p", 448)
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
  -- BufReadCmd and the reader can spell the same Windows path with different
  -- separators; both must invalidate and reuse the same private sidecar.
  if vim.fn.has("win32") == 1 then original = vim.fs.normalize(original, { expand_env = false }) end
  return cache_directory .. "/" .. vim.fn.sha256(original) .. "." .. extension
end

function M.read_notebook(filename)
  local stat = vim.uv.fs_stat(filename)
  if not stat or stat.type ~= "file" or stat.size > 32 * 1024 * 1024 then
    error("请选择不超过 32 MiB 的本地 Notebook 文件。", 0)
  end
  local file = assert(io.open(filename, "rb"))
  local raw = file:read("*a"); file:close()
  local ok, document = pcall(vim.json.decode, raw)
  if not ok then error("该 .ipynb 不是有效的 JSON Notebook；文件未改动，请先从备份恢复。", 0) end
  if type(document) ~= "table" or document.nbformat ~= 4 or type(document.cells) ~= "table" then
    error("原生 Notebook 编辑需要 nbformat 4。", 0)
  end
  return document
end

local function write_notebook(event)
  for _, handler in ipairs(vim.api.nvim_get_autocmds({ event = "BufWriteCmd", buffer = event.buf })) do
    if handler.group_name == "jupytext-nvim" then return end
  end
  local path = vim.api.nvim_buf_get_name(event.buf)
  local staged = vim.fs.joinpath(vim.fs.dirname(path), "." .. vim.fs.basename(path)
    .. ".glow-" .. vim.fn.getpid() .. "-" .. vim.uv.hrtime() .. ".ipynb")
  local ok, err = pcall(function()
    local lines = vim.api.nvim_buf_get_lines(event.buf, 0, -1, false)
    local first = 1
    while first <= #lines and lines[first]:match("^%s*$") do first = first + 1 end
    local percent = lines[first] == "# ---"
    for _, line in ipairs(lines) do if line:match("^# %%%%") then percent = true; break end end
    if not percent then error("当前缓冲区不是 Notebook percent 源码，请重新打开文件。", 0) end
    -- A restored buffer may have blank rows before the Jupytext YAML header.
    -- Strip only that leading padding in the private serialization copy.
    if lines[first] == "# ---" and first > 1 then lines = vim.list_slice(lines, first) end
    local exists = vim.fn.filereadable(path) == 1
    if exists then
      M.read_notebook(path)
      assert(vim.uv.fs_copyfile(path, staged))
    end
    local python = M.sidecar(path, "py")
    vim.fn.writefile(lines, python)
    local args = { "--from", "py:percent", "--to", "ipynb", "--output", staged }
    if exists then args[#args + 1] = "--update" end
    args[#args + 1] = python
    M.convert(args)
    M.read_notebook(staged)
    assert(vim.uv.fs_rename(staged, path))
  end)
  if not ok then
    vim.fn.delete(staged)
    vim.bo[event.buf].modified = true
    error("Notebook 未保存，原文件已保留：" .. tostring(err), 0)
  end
  vim.bo[event.buf].modified = false
  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = event.buf, modeline = false })
end

-- Safe to hot-install: this never clears/reconfigures Jupytext's reader.
function M.install_write_guard()
  local group = vim.api.nvim_create_augroup("GlowNotebookWriteSafety", { clear = false })
  if #vim.api.nvim_get_autocmds({ group = group, event = "BufWriteCmd", pattern = "*.ipynb" }) > 0 then return end
  vim.api.nvim_create_autocmd("BufWriteCmd", { group = group, pattern = "*.ipynb", callback = function(event)
    for _, handler in ipairs(vim.api.nvim_get_autocmds({ event = "BufWriteCmd", buffer = event.buf })) do
      if handler.buflocal then return end
    end
    write_notebook(event)
  end })
  vim.api.nvim_create_autocmd("BufWritePre", { group = group, pattern = "*.ipynb", callback = function(event)
    -- Last-resort abort if every write command was externally removed. Restore
    -- the guard before allowing a later save; never fall through to raw Python.
    M.ensure_notebook_writer(event.buf)
    error("已阻止直接写入 Notebook 源码；安全保存回调已恢复，请重新保存。", 0)
  end })
end

function M.ensure_notebook_writer(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  M.install_write_guard()
  vim.b[buf].glow_notebook_writer = true
  local group = vim.api.nvim_create_augroup("GlowNotebookWriteSafety", { clear = false })
  for _, handler in ipairs(vim.api.nvim_get_autocmds({ event = "BufWriteCmd", buffer = buf })) do
    if handler.buflocal and handler.group == group then return end
  end
  -- Upstream remains the single writer while its own callback is present.
  vim.api.nvim_create_autocmd("BufWriteCmd", { group = group, buffer = buf, callback = write_notebook })
end

local function percent_source(lines)
  for _, line in ipairs(lines) do
    if line == "# ---" or line:match("^# %%%%") then return true end
  end
  return false
end

function M.complete_notebook_load(buf)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf)
    or not percent_source(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) then return false end
  local modified = vim.bo[buf].modified
  M.ensure_notebook_writer(buf)
  vim.bo[buf].fileencoding, vim.bo[buf].filetype = "utf-8", "python"
  if not vim.b[buf].glow_notebook_read_complete then
    vim.b[buf].glow_notebook_read_complete = true
    vim.api.nvim_buf_call(buf, function()
      vim.api.nvim_exec_autocmds("BufReadPost", { buffer = buf, modeline = false })
    end)
  end
  -- Built-in detection sees the .ipynb filename during BufReadPost and can
  -- overwrite Python with JSON even though this buffer already holds percent
  -- source. Restore the converted language after all read handlers finish.
  if vim.bo[buf].filetype ~= "python" then vim.bo[buf].filetype = "python" end
  vim.bo[buf].modified = modified
  return true
end

-- Wrap the pinned reader, retaining all of its normal serialization/undo work.
-- This can be installed on an already running editor without clearing groups.
function M.install_reader_guard()
  local count = 0
  for _, handler in ipairs(vim.api.nvim_get_autocmds({ event = "BufReadCmd", group = "jupytext-nvim" })) do
    if type(handler.callback) == "function" and handler.desc ~= "GlowNotebookReadGuard" then
      local original = handler.callback
      vim.api.nvim_del_autocmd(handler.id)
      vim.api.nvim_create_autocmd("BufReadCmd", { group = handler.group, pattern = handler.pattern,
        desc = "GlowNotebookReadGuard", callback = function(event)
          vim.b[event.buf].glow_notebook_read_complete = nil
          vim.b[event.buf].glow_notebook_swap_read_resumed = nil
          local set_lines = vim.api.nvim_buf_set_lines
          vim.api.nvim_buf_set_lines = function(buf, first, last, strict, lines)
            local ok, result = pcall(set_lines, buf, first, last, strict, lines)
            if not ok then
              local target = buf == 0 and vim.api.nvim_get_current_buf() or buf
              -- Choosing "edit anyway" can raise E325 AFTER writing the
              -- complete converted text. Continue only that exact operation;
              -- any other error or partial/unrelated mutation still fails.
              if target == event.buf and first == 0 and last == -1
                and tostring(result):find("E325:", 1, true) and percent_source(lines)
                and vim.deep_equal(vim.api.nvim_buf_get_lines(target, 0, -1, false), lines) then
                vim.b[event.buf].glow_notebook_swap_read_resumed = true
                return
              end
              error(result, 0)
            end
            return result
          end
          local ok, err = pcall(original, event)
          vim.api.nvim_buf_set_lines = set_lines
          if not ok then error(err, 0) end
          -- The pinned reader replaces source via API but never clears its
          -- synthetic edit flag. A successful disk read begins clean.
          vim.bo[event.buf].modified = false
          M.complete_notebook_load(event.buf)
        end })
      count = count + 1
    end
  end
  return count
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
    local document = M.read_notebook(filename)
    local metadata = document.metadata or {}
    local language = (metadata.kernelspec or {}).language or (metadata.language_info or {}).name or "python"
    if language:lower() ~= "python" and language:lower() ~= "python3" then
      error("原生 Notebook 首版支持 Python；其他语言可用 :GlowNotebookPreview 查看保存输出。")
    end
    return { language = "python", extension = "py" }
  end
  local group = vim.api.nvim_create_augroup("GlowNotebookRuntime", { clear = true })
  M.install_write_guard()
  -- Register before upstream's BufReadCmd. Reload must convert the current
  -- notebook from disk, rather than reusing this session's old private sidecar.
  vim.api.nvim_create_autocmd("BufReadCmd", {
    group = group,
    pattern = "*.ipynb",
    callback = function(ev)
      M.ensure_notebook_writer(ev.buf)
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
      -- Windows shellescape() uses doubled double-quotes unless shellslash is set.
      if vim.fn.has("win32") == 1 and value:sub(1, 1) == '"' and value:sub(-1) == '"' then
        return (value:sub(2, -2):gsub('""', '"'))
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
  M.install_reader_guard()
end

-- Match remote#host's manifest paths: backslashes are escapes in its Vimscript RPC wrappers.
local adapter_path = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h"), { expand_env = false }) .. "/glow_molten_output.py"

function M.configure_output_adapter()
  local registered = vim.fn["remote#host#PluginsForHost"]("python3")
  for _, plugin in ipairs(registered) do
    if plugin.path == adapter_path then return end
  end
  if vim.fn["remote#host#IsRunning"]("python3") ~= 0 then
    vim.notify("Notebook output colors require a new editor session: the Python host is already running.", vim.log.levels.WARN)
    return
  end
  vim.fn["remote#host#RegisterPlugin"]("python3", adapter_path, {
    { type = "function", name = "GlowNotebookOutputAdapterInfo", sync = 1, opts = vim.empty_dict() },
    { type = "function", name = "GlowNotebookSavedOutputs", sync = 1, opts = vim.empty_dict() },
  })
  local group = vim.api.nvim_create_augroup("GlowNotebookOutputAdapter", { clear = true })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "MoltenInitPost", once = true, callback = function()
    vim.schedule(function()
      local ok, info = pcall(vim.fn.GlowNotebookOutputAdapterInfo)
      if not ok or not info.active then
        vim.notify("Notebook output colors unavailable: " .. tostring(ok and info.error or info), vim.log.levels.ERROR)
      end
    end)
  end })
end

function M.configure_molten()
  require("config.media.notebook_highlights").setup()
  M.prepare_host()
  M.configure_output_adapter()
  vim.g.molten_auto_init_behavior = "raise"
  vim.g.molten_auto_open_output = false
  vim.g.molten_virt_text_output = true
  vim.g.molten_virt_lines_off_by_1 = false
  vim.g.molten_virt_text_max_lines = 16
  vim.g.molten_wrap_output = true
  vim.g.molten_tick_rate = 100
  if vim.g.neovide_native_notebook == true then
    -- Molten snapshots this option when its Python host initializes and reapplies
    -- it on every popup refresh. Keep character borders out of the native frame.
    vim.g.molten_output_win_border = "none"
  end
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
