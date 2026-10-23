-- Prefer embedded coordinate SyncTeX, with asynchronous SumatraPDF fallback
-- for older Windows frontends or an explicit g:glow_tex_viewer='sumatra'.
-- Every external program receives argv directly; paths never become code.
local function T(text) return require('config.platform.locale').t(text) end
local M = {}
local source_win
local function warn(message)
  vim.notify(message, vim.log.levels.WARN, { title = 'VimTeX / SumatraPDF' })
end
local function readable_exe(path)
  return type(path) == 'string' and path ~= '' and vim.fn.executable(path) == 1 and path or nil
end
function M.executable()
  if vim.g.glow_sumatra_executable then return readable_exe(vim.g.glow_sumatra_executable) end
  local found = readable_exe(vim.fn.exepath('SumatraPDF')) or readable_exe(vim.fn.exepath('SumatraPDF.exe'))
  if found then return found end
  local localapp = vim.env.LOCALAPPDATA
  local machine = (vim.env.PROCESSOR_ARCHITEW6432 or vim.env.PROCESSOR_ARCHITECTURE or ''):lower()
  local architecture = machine == 'arm64' and 'arm64' or 'x64'
  local candidates = {}
  if localapp then
    local private = {}
    -- The viewer runs out of process: an x64 editor under ARM64 emulation
    -- can use the already installed native ARM64 viewer (and vice versa).
    for _, arch in ipairs({ architecture, architecture == 'arm64' and 'x64' or 'arm64' }) do
      vim.list_extend(private, vim.fn.glob(localapp .. '/NeovideGlow/dependencies/sumatra/*/' .. arch .. '/SumatraPDF.exe', false, true))
    end
    table.sort(private, function(a, b)
      local av = vim.version.parse(vim.fs.normalize(a):match('/sumatra/([^/]+)/') or '')
      local bv = vim.version.parse(vim.fs.normalize(b):match('/sumatra/([^/]+)/') or '')
      if av and bv then return vim.version.lt(bv, av) end
      return a > b
    end)
    vim.list_extend(candidates, private)
    vim.list_extend(candidates, {
      localapp .. '/SumatraPDF/SumatraPDF.exe',
      localapp .. '/Programs/SumatraPDF/SumatraPDF.exe',
    })
  end
  for _, root in ipairs({ vim.env.ProgramW6432 or '', vim.env.ProgramFiles or '', vim.env['ProgramFiles(x86)'] or '' }) do
    if root ~= '' then candidates[#candidates + 1] = root .. '/SumatraPDF/SumatraPDF.exe' end
  end
  for _, candidate in ipairs(candidates) do found = readable_exe(candidate); if found then return found end end
end
function M.check()
  if require('config.media.synctex').native_enabled() or M.executable() then return true end
  warn(T('SumatraPDF was not found. Run Windows LaTeX dependency setup or set g:glow_sumatra_executable.'))
  return false
end
-- Quote a single argument for Windows CreateProcess, never for cmd.exe.
local function quote(value)
  value = value:gsub('(\\*)"', '%1%1\\"'):gsub('(\\+)$', '%1%1')
  return '"' .. value .. '"'
end
function M.inverse_command()
  local server = vim.v.servername
  if server == '' then server = vim.fn.serverstart() end
  local client = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h') .. '/sumatra_inverse.lua'
  return table.concat({ quote(vim.v.progpath), '--headless --noplugin -u NONE -i NONE -l', quote(client),
    quote(server), '"%f"', '%l', '%c' }, ' ')
end
function M.arguments(pdf, sync)
  local executable = M.executable()
  if not executable then return nil end
  -- Sumatra's -reuse-instance and inverse command are scoped to its appdata
  -- profile. Separate Neovim servers must never share that mutable command.
  local server = vim.v.servername
  if server == '' then server = vim.fn.serverstart() end
  local profile = vim.fn.stdpath('state') .. '/glow-sumatra/' .. vim.fn.sha256(server):sub(1, 20)
  vim.fn.mkdir(profile, 'p')
  local argv = { executable, '-appdata', profile, '-reuse-instance', '-inverse-search', M.inverse_command() }
  if sync then
    vim.list_extend(argv, { '-forward-search', vim.api.nvim_buf_get_name(0), tostring(vim.fn.line('.')) })
  end
  argv[#argv + 1] = pdf
  return argv
end
function M.view(pdf, sync)
  if sync and not vim.api.nvim_buf_get_name(0):lower():match('%.tex$') then
    warn(T('Run forward search from a TeX source file.'))
    return false
  end
  local native = require('config.media.synctex')
  if native.native_enabled() then
    if sync then return native.forward(pdf, { activate = true }) end
    return require('config.media.preview').open(pdf, { kind = 'pdf' })
  end
  local argv = M.arguments(pdf, sync)
  if not argv then return M.check() end
  source_win = vim.api.nvim_get_current_win()
  if sync then
    local stem = pdf:gsub('%.[pP][dD][fF]$', '')
    if vim.fn.filereadable(stem .. '.synctex.gz') == 0 and vim.fn.filereadable(stem .. '.synctex') == 0 then
      warn(T('The PDF has no SyncTeX mapping. Compile with -synctex=1 first.'))
      return false
    end
  end
  local ok, result = pcall(vim.system, argv, { detach = true }, function(completed)
    if completed.code ~= 0 then vim.schedule(function() warn(T('SumatraPDF exited: ') .. tostring(completed.code)) end) end
  end)
  if not ok then warn(tostring(result)) end
  return ok
end
-- Called only by our minimal RPC client, addressed to this exact Neovim server.
function M.inverse(file, line, column)
  line, column = tonumber(line), tonumber(column) or 1
  if type(file) ~= 'string' or not line or line < 1 or vim.fn.filereadable(file) ~= 1 then return false end
  local win = source_win
  for _, candidate in ipairs(vim.fn.win_findbuf(vim.fn.bufnr(file))) do win = candidate; break end
  local ok, err = pcall(function()
    if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_set_current_win(win) end
    -- Retain any modified buffer even when the user has :set nohidden.
    vim.cmd('keepalt hide edit ' .. vim.fn.fnameescape(file))
    local row = math.min(math.floor(line), vim.api.nvim_buf_line_count(0))
    local text = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ''
    vim.api.nvim_win_set_cursor(0, { row, math.max(0, math.min(#text, math.floor(column) - 1)) })
    vim.cmd('normal! zz')
    if vim.g.neovide and type(vim.g.neovide_channel_id) == 'number' then
      pcall(vim.rpcnotify, vim.g.neovide_channel_id, 'neovide.focus_window')
    end
    vim.api.nvim_exec_autocmds('User', { pattern = 'VimtexEventViewReverse', modeline = false })
  end)
  if not ok then warn(T('Inverse search could not open the source: ') .. tostring(err)) end
  return ok
end
return M
