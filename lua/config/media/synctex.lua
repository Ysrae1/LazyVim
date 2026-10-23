local function T(text) return require("config.platform.locale").t(text) end
-- Real SyncTeX CLI queries only. No compiler, shell command or GUI sync request.
local M = {}
local jobs, generation, configured = {}, 0, false
local uv = vim.uv or vim.loop

local function notify(message)
  vim.notify(message,vim.log.levels.WARN,{title='SyncTeX'})
end

function M.native_enabled()
  local capability=vim.g.neovide_native_pdf_synctex
  -- Older macOS frontends predate the explicit coordinate capability. Windows
  -- must advertise it: the original WebView2 PDF viewer only supports reading.
  local synchronized=capability==true or (capability==nil and vim.fn.has('win32')~=1)
  return vim.g.neovide_native_preview==true and synchronized
    and type(vim.g.neovide_channel_id)=='number'
    and vim.g.glow_tex_viewer~='skim' and vim.g.glow_tex_viewer~='sumatra'
end

local function path(value)
  return uv.fs_realpath(value) or vim.fs.normalize(vim.fn.fnamemodify(value,':p'))
end

local function executable()
  local command=vim.g.glow_synctex_executable or vim.fn.exepath('synctex')
  if command=='' and vim.fn.executable('/Library/TeX/texbin/synctex')==1 then command='/Library/TeX/texbin/synctex' end
  return command~='' and vim.fn.executable(command)==1 and command or nil
end

local function mapping(pdf)
  local stem=pdf:gsub('%.[pP][dD][fF]$','')
  return vim.fn.filereadable(stem..'.synctex.gz')==1 or vim.fn.filereadable(stem..'.synctex')==1
end

-- SyncTeX may print several records. Its documented first record is the most
-- accurate; file values are not split on ':' so paths retain spaces/colons.
function M.parse(output,mode)
  local result,inside={},false
  for line in (output or ''):gmatch('[^\r\n]+') do
    if line:match('SyncTeX result begin') then inside=true
    elseif line:match('SyncTeX result end') then break
    elseif inside then
      local key,value=line:match('^([^:]+):(.*)$')
      if key and result[key]==nil then result[key]=value end
    end
  end
  if mode=='view' then
    local point={page=tonumber(result.Page),x=tonumber(result.h) or tonumber(result.x),y=tonumber(result.v) or tonumber(result.y),
      width=tonumber(result.W) or 0,height=tonumber(result.H) or 0}
    if not point.page or not point.x or not point.y then return nil end
    point.page=math.floor(point.page); point.width=math.max(0,point.width); point.height=math.max(0,point.height)
    return point
  end
  if not result.Input or not tonumber(result.Line) then return nil end
  return {file=result.Input,line=math.max(1,tonumber(result.Line)),column=math.max(1,tonumber(result.Column) or 1)}
end

local function query(mode,pdf,args,options,callback)
  local command=executable()
  if not command then notify(T("synctex was not found. Install a TeX distribution or set g:glow_synctex_executable.")); return false end
  pdf=path(pdf)
  if vim.fn.filereadable(pdf)~=1 then notify(T("PDF not found: ")..pdf); return false end
  if not mapping(pdf) then notify(T("Missing ")..vim.fs.basename(pdf):gsub('%.pdf$','')..T(".synctex(.gz). Compile with SyncTeX enabled first; Glow will not rebuild automatically.")); return false end
  local key=mode..':'..pdf
  if jobs[key] then pcall(jobs[key].kill,jobs[key],9) end
  local argv={command,mode}; vim.list_extend(argv,args)
  local task
  task=vim.system(argv,{text=true,cwd=vim.fs.dirname(pdf),timeout=10000,
    -- These variables ask synctex to launch an external viewer/editor. Disable
    -- them explicitly; only stdout records belong to this integration.
    env={SYNCTEX_VIEWER='',SYNCTEX_EDITOR=''}},function(result)
      vim.schedule(function()
        if jobs[key]~=task then return end
        jobs[key]=nil
        if options.valid and not options.valid() then return end
        local parsed=result.code==0 and M.parse(result.stdout,mode)
        if not parsed then
          if vim.fn.has('win32')~=1 then
            notify('SyncTeX '..mode..T(" mapping not found: ")..vim.trim(result.stderr or result.stdout or ''):sub(1,240))
            return
          end
          -- SyncTeX writes "No tag for" to stdout even with exit code 0.
          -- An empty stderr must not hide that diagnostic (Lua strings are truthy).
          local stdout,stderr=vim.trim(result.stdout or ''),vim.trim(result.stderr or '')
          local details={}
          if stdout~='' then details[#details+1]=stdout:sub(1,240) end
          if stderr~='' then details[#details+1]=stderr:sub(1,240) end
          local message='SyncTeX '..mode..T(" mapping not found: ")
          if mode=='view' and stdout:find('No tag for ',1,true) then
            message=T("The source path recorded in the SyncTeX file does not match the current file. Force a full recompilation on this computer.")..'\n'
          end
          notify(message..table.concat(details,'\n'))
          return
        end
        callback(parsed)
      end)
    end)
  jobs[key]=task
  return true
end

local function output_file()
  -- Use VimTeX's dictionary method just as its built-in viewers do. It knows
  -- the main document, jobname and compiler out_dir, also in included buffers.
  local ok,file=pcall(vim.fn.eval,"exists('*b:vimtex.compiler.get_file') ? b:vimtex.compiler.get_file('pdf') : ''")
  if ok and type(file)=='string' and file~='' then return path(file) end
  local got,main=pcall(vim.fn.eval,"get(get(b:, 'vimtex', {}), 'tex', '')")
  if got and type(main)=='string' and main~='' then return path(main:gsub('%.[tT][eE][xX]$','.pdf')) end
  return path(vim.api.nvim_buf_get_name(0):gsub('%.[tT][eE][xX]$','.pdf'))
end

function M.forward(pdf,opts)
  opts=opts or {}
  if not M.native_enabled() then notify(T("This native PDF viewer does not support coordinate synchronization. You can use VimTeX's external PDF viewer.")); return false end
  local source=path(vim.api.nvim_buf_get_name(0))
  if not source:lower():match('%.tex$') then notify(T("Run forward search from a TeX source file.")); return false end
  local position=vim.api.nvim_win_get_cursor(0)
  local win,tab=vim.api.nvim_get_current_win(),vim.api.nvim_get_current_tabpage()
  pdf=path(pdf or output_file())
  generation=generation+1; local current=generation
  return query('view',pdf,{'-i',('%d:%d:%s'):format(position[1],position[2]+1,source),'-o',pdf},
    {valid=function() return current==generation and vim.api.nvim_win_is_valid(win) and vim.api.nvim_get_current_tabpage()==tab end},
    function(point) require('config.media.preview').pdf_sync(pdf,point,{win=win,activate=opts.activate}) end)
end

function M.inverse(pdf,point,opts)
  opts=opts or {}
  if type(point.page)~='number' or type(point.x)~='number' or type(point.y)~='number' then return false end
  pdf=path(pdf)
  return query('edit',pdf,{'-o',('%d:%.8f:%.8f:%s'):format(point.page,point.x,point.y,pdf)},
    {valid=function() return (not opts.valid or opts.valid()) and (not opts.tab or vim.api.nvim_get_current_tabpage()==opts.tab) end},
    function(result)
      -- SyncTeX returns drive/UNC paths on Windows. XeTeX may encode its
      -- filename records in the system ANSI codepage even when Neovim itself
      -- has a UTF-8 process manifest. Prefer the original path, and only use a
      -- legacy decoding when it identifies an actual readable source file.
      local function resolve(value)
        local absolute=value:match('^[/\\]') or value:match('^%a:[/\\]')
        return path(absolute and value or vim.fs.joinpath(vim.fs.dirname(pdf),value))
      end
      local file=resolve(result.file)
      if vim.fn.filereadable(file)~=1 and vim.fn.has('win32')==1 then
        local converted,decoded=pcall(function()
          local ffi=require('ffi')
          ffi.cdef('int GetLocaleInfoW(unsigned long, unsigned long, unsigned short *, int);')
          local codepage=ffi.new('unsigned long[1]')
          -- LOCALE_SYSTEM_DEFAULT, LOCALE_RETURN_NUMBER | LOCALE_IDEFAULTANSICODEPAGE.
          if ffi.C.GetLocaleInfoW(0x800,0x20001004,ffi.cast('unsigned short *',codepage),2)==0 then return end
          return vim.fn.iconv(result.file,'cp'..tonumber(codepage[0]),'utf-8')
        end)
        if converted and decoded and decoded~='' then
          local candidate=resolve(decoded)
          if vim.fn.filereadable(candidate)==1 then file=candidate end
        end
      end
      if vim.fn.filereadable(file)~=1 then notify(T("The source file returned by SyncTeX cannot be read: ")..file); return end
      local win=opts.win
      if not win or not vim.api.nvim_win_is_valid(win) or (opts.tab and vim.api.nvim_win_get_tabpage(win)~=opts.tab) then
        for _,candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          if candidate~=opts.pdf_win and vim.api.nvim_win_get_config(candidate).relative=='' then win=candidate; break end
        end
      end
      local ok,err=pcall(function()
        if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_set_current_win(win) else vim.cmd('leftabove vnew') end
        vim.cmd({cmd='edit',args={file}})
        local row=math.min(result.line,vim.api.nvim_buf_line_count(0))
        local line=vim.api.nvim_buf_get_lines(0,row-1,row,false)[1] or ''
        vim.api.nvim_win_set_cursor(0,{row,math.min(#line,result.column-1)})
        vim.cmd('normal! zz')
      end)
      if not ok then notify(T("Inverse search could not open the source: ")..tostring(err)) end
    end)
end

function M.setup()
  if configured then return end
  configured=true
  require("config.platform.locale").command('GlowTexForward',function(args)
    local file=args.args~='' and args.args or nil
    -- File completion escapes spaces for Ex, while user-command args retain
    -- those backslashes. Preserve a readable literal path before decoding.
    if file and vim.fn.filereadable(file)==0 then
      local decoded=file:gsub('\\(.)','%1')
      if vim.fn.filereadable(decoded)==1 then file=decoded end
    end
    if vim.fn.has('win32')==1 and not M.native_enabled() then
      require('config.latex.sumatra').view(file and path(file) or output_file(),true)
    else
      M.forward(file)
    end
  end,
    {nargs='?',complete='file',desc=T("Locate TeX Cursor in PDF with SyncTeX")})
  vim.api.nvim_create_autocmd('VimLeavePre',{group=vim.api.nvim_create_augroup('GlowSyncTeX',{clear=true}),callback=function()
    generation=generation+1
    for _,job in pairs(jobs) do pcall(job.kill,job,9) end
    jobs={}
  end})
end
return M
