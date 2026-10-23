-- A cache copied to Windows can retain the previous machine's source paths.
-- Arm one forced build for this compiler; other platforms keep their existing flow.
local M={}
local uv=vim.uv or vim.loop
local configured=false

local function normalized(value)
  if type(value)~='string' or value=='' then return nil end
  value=value:gsub('\\','/')
  if not value:match('^/') and not value:match('^%a:/') then return nil end
  value=uv.fs_realpath(value) or vim.fs.normalize(value)
  value=value:gsub('\\','/'):gsub('/+$','')
  -- Drive and UNC paths are case-insensitive even when inspecting a cache on Mac/Linux.
  if vim.fn.has('win32')==1 or value:match('^%a:/') or value:match('^//') then value=value:lower() end
  return value
end

local function recorded_root(fls)
  if fls=='' or vim.fn.filereadable(fls)~=1 then return nil end
  local ok,lines=pcall(vim.fn.readfile,fls,'',64)
  if not ok then return nil end
  for _,line in ipairs(lines) do
    local pwd=line:match('^PWD (.+)$')
    if pwd then return pwd:gsub('\r$','') end
  end
end

local function same_root(recorded,current)
  if normalized(recorded)==current then return true end
  if vim.fn.has('win32')~=1 then return false end
  -- XeTeX may write recorder paths in the system ANSI codepage. This is only
  -- a comparison fallback; neither recorder bytes nor process arguments change.
  local ok,decoded=pcall(function()
    local ffi=require('ffi')
    ffi.cdef('int GetLocaleInfoW(unsigned long, unsigned long, unsigned short *, int);')
    local cp=ffi.new('unsigned long[1]')
    if ffi.C.GetLocaleInfoW(0x800,0x20001004,ffi.cast('unsigned short *',cp),2)==0 then return end
    return vim.fn.iconv(recorded,'cp'..tonumber(cp[0]),'utf-8')
  end)
  return ok and decoded and normalized(decoded)==current or false
end

function M.prepare()
  if vim.fn.has('win32')~=1 then return end
  if vim.fn.eval("get(get(get(b:, 'vimtex', {}), 'compiler', {}), 'name', '')")~='latexmk' then return end
  if vim.fn.eval("get(b:vimtex.compiler, '_glow_migrated_cache_g', -1)")~=-1 then return end
  local options=vim.fn.eval('b:vimtex.compiler.options')
  if vim.tbl_contains(options,'-g') or vim.tbl_contains(options,'-gg') then return end
  local fls=vim.fn.eval("b:vimtex.compiler.get_file('fls')")
  local recorded=recorded_root(fls)
  local current=normalized(vim.fn.eval('b:vimtex.compiler.file_info.root'))
  -- Missing/relative recorder PWD is inconclusive: ordinary projects remain incremental.
  if not recorded or not normalized(recorded) or not current or same_root(recorded,current) then return end
  vim.cmd("call add(b:vimtex.compiler.options, '-g')")
  vim.cmd(('let b:vimtex.compiler._glow_migrated_cache_g = %d'):format(#options))
end

function M.success()
  if vim.fn.has('win32')~=1 then return end
  if vim.fn.eval("get(get(get(b:, 'vimtex', {}), 'compiler', {}), 'name', '')")~='latexmk' then return end
  local index=vim.fn.eval("get(b:vimtex.compiler, '_glow_migrated_cache_g', -1)")
  if index<0 then return end
  local options=vim.fn.eval('b:vimtex.compiler.options')
  -- Remove only the option this module added, never a pre-existing manual -g.
  if options[index+1]=='-g' then vim.cmd(('call remove(b:vimtex.compiler.options, %d)'):format(index)) end
  vim.cmd('unlet! b:vimtex.compiler._glow_migrated_cache_g')
end

function M.setup()
  if vim.fn.has('win32')~=1 then return end
  if configured then return end
  configured=true
  local group=vim.api.nvim_create_augroup('GlowLatexBuildCache',{clear=true})
  vim.api.nvim_create_autocmd('User',{group=group,pattern='VimtexEventInitPost',callback=M.prepare})
  vim.api.nvim_create_autocmd('User',{group=group,pattern='VimtexEventCompileSuccess',callback=M.success})
end

return M
