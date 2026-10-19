-- AppKit previews use notifications only. Never make a synchronous Neovide RPC.
local M = {}
local capsule = require('config.media.capsule')
local views, active, next_id, configured, pending, timer = {}, {}, 0, false, false, nil
local audio = { mp3=true, m4a=true, aac=true, wav=true, aiff=true, aif=true, caf=true, flac=true }
local video = { mp4=true, m4v=true, mov=true, mpg=true, mpeg=true }
local web = { html=true, htm=true, xhtml=true }
local saved_options = { 'number','relativenumber','signcolumn','foldcolumn','wrap','list','cursorline','cursorcolumn','spell','winbar','fillchars' }

function M.kind(path)
  local ext = (path:match('%.([^./]+)$') or ''):lower()
  return audio[ext] and 'audio' or video[ext] and 'video' or web[ext] and 'web' or ext=='pdf' and 'pdf' or nil
end
function M.supports(path) return type(path)=='string' and M.kind(path) ~= nil end
local function available() return vim.g.neovide_native_preview == true and type(vim.g.neovide_channel_id)=='number' end
local function canonical(source)
  if source:match('^%a+://') then return source end
  local path=vim.fs.normalize(vim.fn.fnamemodify(source,':p'))
  return vim.uv.fs_realpath(path) or path
end
local function warn(text) vim.notify(text,vim.log.levels.WARN,{title='原生预览'}) end
local function rpc(method,...)
  if available() then return pcall(vim.rpcnotify,vim.g.neovide_channel_id,'neovide.preview.'..method,...) end
  return false
end
local function write(view, lines)
  if not vim.api.nvim_buf_is_valid(view.buf) then return end
  vim.bo[view.buf].modifiable=true
  vim.api.nvim_buf_set_lines(view.buf,0,-1,false,lines)
  vim.bo[view.buf].modifiable=false
  vim.bo[view.buf].modified=false
end
local function remember(win)
  local result={}
  for _,k in ipairs(saved_options) do result[k]=vim.wo[win][k] end
  return result
end
local function restore(view)
  if vim.api.nvim_win_is_valid(view.win) then
    for k,v in pairs(view.saved or {}) do vim.wo[view.win][k]=v end
  end
end
local function release(view)
  if view.id then active[view.id]=nil; rpc('close',view.id); view.id=nil; view.geometry=nil end
end
local function dispose(view)
  release(view)
  restore(view)
  if view.opts.on_close and not view.disposed then view.disposed=true; pcall(view.opts.on_close) end
end
local states={ loading='…',ready='READY',playing='PLAYING',paused='PAUSED',ended='ENDED',error='ERROR' }
-- The buffer/status line already identifies the file. Keep media controls in
-- the same compact, theme-adaptive capsules as the image preview.
function M.render_title(view,width)
  local status=view.status or {}
  local state=states[status.state] or '…'
  local function layout(compact,details,controls,show_status)
    local value=state
    if view.kind=='pdf' and status.state~='error' and (status.pages or 0)>0 then
      value=('%d/%d · %.0f%%'):format(status.page or 0,status.pages,(status.zoom or 1)*100)
    elseif view.kind=='web' and status.state=='ready' then
      value=('%.0f%%'):format((status.zoom or view.zoom or 1)*100)
    elseif view.kind~='web' and view.kind~='pdf' and details and status.state~='loading' then
      value=('%s · %.0f/%.0fs · %d%%'):format(state,status.position or 0,status.duration or 0,math.floor((status.volume or 1)*100+.5))
    end
    local left,left_width='',0
    if show_status then
      local label=({pdf='PDF',web='WEB',audio='AUDIO',video='VIDEO'})[view.kind] or 'VIEW'
      left,left_width=capsule.format('GlowMediaInfo',compact and label:sub(1,1) or label,value)
    end
    local right,right_width={},0
    local function add(group,label,key)
      local text,size=capsule.format('GlowMedia'..group,label,key)
      right_width=right_width+size+(#right>0 and 1 or 0);right[#right+1]=text
    end
    if view.kind=='pdf' or view.kind=='web' then
      if controls==2 and view.kind=='pdf' then add('Action',compact and 'P' or 'PAGE','[p ]p') end
      if controls>0 then add('Action',compact and 'Z' or 'ZOOM','+ − · 0') end
      if controls==2 and view.kind=='web' then add('Menu',compact and 'R' or 'RELOAD','r') end
    elseif controls>0 then
      add('Action',compact and 'P' or 'PLAY','␣')
      if controls==2 then add('Action',compact and 'S' or 'SEEK','h l');add('Action',compact and 'V' or 'VOL','+ −') end
    end
    if status.state=='error' then add('Menu',compact and 'R' or 'RETRY','r') end
    add('Menu',compact and 'I' or 'FOCUS','i');add('Menu',compact and 'Q' or 'CLOSE','q')
    return capsule.bar(left,table.concat(right,' '),left_width,right_width)
  end
  for _,variant in ipairs({{false,true,2,true},{false,false,1,true},{true,false,1,true},{true,false,0,true},{true,false,0,false}}) do
    local result,size=layout(unpack(variant))
    if size<=width then return result end
  end
  return capsule.close_hint(width)
end
local function title(view)
  if not vim.api.nvim_win_is_valid(view.win) then return end
  vim.wo[view.win].winbar=M.render_title(view,vim.api.nvim_win_get_width(view.win))
end
local function geometry(view)
  local pos=vim.api.nvim_win_get_position(view.win)
  local info=vim.fn.getwininfo(view.win)[1]
  return {row=pos[1]+((info and info.winbar) or 0),col=pos[2],width=vim.api.nvim_win_get_width(view.win),height=info and info.height or math.max(1,vim.api.nvim_win_get_height(view.win)-1)}
end
local function show(view)
  if not view.id or not vim.api.nvim_win_is_valid(view.win) then return end
  local rect=geometry(view)
  if not vim.deep_equal(rect,view.geometry) then rpc('show',view.id,rect); view.geometry=rect end
end
function M.refresh()
  pending=false
  local visible={}
  for _,win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local view=views[win]
    if view and vim.api.nvim_win_get_buf(win)==view.buf and vim.api.nvim_win_get_config(win).relative=='' then
      visible[win]=true
      if not view.id then
        next_id=next_id+1; view.id=next_id; active[view.id]=view
        view.inverse_seq=nil
        view.resume=view.status and view.status.position or 0
        view.resume_page=view.status and view.status.page
        view.status={state='loading',volume=view.volume or 1}
        write(view,{'正在准备原生预览…','','页面内 Cmd+Esc 返回编辑器；Ctrl+Tab / Ctrl+Shift+Tab 切换标签页。'})
        rpc('open',view.id,view.kind,view.current_url or view.source)
        if view.kind=='web' then rpc('action',view.id,'zoom',view.zoom or 1)
        elseif view.kind=='pdf' then
          if view.pdf_fit~=false then rpc('action',view.id,'fit') else rpc('action',view.id,'zoom',view.zoom or 1) end
        else rpc('action',view.id,'volume',view.volume or 1) end
      end
      title(view); show(view)
    end
  end
  for win,view in pairs(views) do
    if not visible[win] then
      release(view)
      if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win)~=view.buf then
        dispose(view); views[win]=nil
      end
    end
  end
end
local function schedule()
  if not pending then pending=true; vim.schedule(M.refresh) end
end
function M.on_status(id,json)
  local view=active[id]
  if not view then return end
  local ok,status=pcall(vim.json.decode,json)
  if not ok or type(status)~='table' then return end
  if view.kind=='pdf' and status.close_requested==true then M.close(id); return end
  local previous=view.status or {}
  view.status=status
  if view.kind=='pdf' and type(status.synctex)=='table' and status.synctex.seq~=view.inverse_seq then
    view.inverse_seq=status.synctex.seq
    local tab=vim.api.nvim_win_is_valid(view.win) and vim.api.nvim_win_get_tabpage(view.win)
    require('config.media.synctex').inverse(view.source,status.synctex,{win=view.opts.synctex_sourcewin,tab=tab,pdf_win=view.win,
      valid=function() return active[id]==view end})
  end
  if status.volume then view.volume=status.volume end
  if status.zoom then view.zoom=status.zoom end
  if status.url and status.url~='' then view.current_url=status.url end
  if status.state=='error' then
    write(view,{'预览失败','',tostring(status.error or '未知错误'),'','r 重试；q 关闭。'})
    if previous.error~=status.error then warn(tostring(status.error or '预览失败')) end
  elseif status.state~='loading' then
    if view.resume and view.resume>0 and (view.kind=='audio' or view.kind=='video') then rpc('action',id,'seek',view.resume); view.resume=nil end
    if view.kind=='pdf' and view.resume_page then rpc('action',id,'page',view.resume_page); view.resume_page=nil end
    if previous.state=='loading' or previous.state=='error' then write(view,{}) end
  end
  title(view)
end
local function current()
  local view=views[vim.api.nvim_get_current_win()]
  if view then return view end
  for _,win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do if views[win] then return views[win] end end
end
function M.action(action,value)
  local view=current()
  if view and view.id then
    if action=='focus' and vim.api.nvim_win_is_valid(view.win) then vim.api.nvim_set_current_win(view.win) end
    rpc('action',view.id,action,value)
  end
end
-- Last asynchronously delivered state; querying it never calls back into Neovide.
function M.status()
  local v=current()
  if not v then return nil end
  return vim.tbl_extend('force',vim.deepcopy(v.status or {}),{kind=v.kind,source=v.source,id=v.id,win=v.win})
end
-- Show scope on request; opening local HTML intentionally permits its sibling assets.
function M.info()
  local status=M.status()
  if not status then return end
  local lines={ '来源：'..(status.url or status.source) }
  if status.kind=='web' then
    local root=status.read_root
    if root==nil then
      root=not status.source:match('^%a+://') and vim.fs.dirname(status.source) or ''
    end
    lines[#lines+1]=root~='' and ('可读取文件夹（含子目录）：'..root) or '未授权读取本地文件夹。'
    lines[#lines+1]='网页脚本可执行；请仅预览可信内容。'
  end
  local text=table.concat(lines,'\n')
  vim.notify(text,vim.log.levels.INFO,{title='预览信息'})
  return text
end
-- Source-identified targeting avoids sending a SyncTeX result to whichever
-- unrelated media view happens to be current when its asynchronous CLI ends.
function M.pdf_sync(source,point,opts)
  opts=opts or {}; source=canonical(source)
  local target
  for _,win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local view=views[win]
    if view and view.kind=='pdf' and view.source==source then target=view; break end
  end
  if not target then
    if not M.open(source,{kind='pdf',synctex_sourcewin=opts.win}) then return false end
    target=views[vim.api.nvim_get_current_win()]
  end
  if not target or not target.id then return false end
  target.opts.synctex_sourcewin=opts.win or target.opts.synctex_sourcewin
  rpc('pdf_sync',target.id,point)
  if not opts.activate and opts.win and vim.api.nvim_win_is_valid(opts.win) then vim.api.nvim_set_current_win(opts.win) end
  return true
end
function M.seek(delta)
  local v=current(); if not v then return end
  local s=v.status or {}; M.action('seek',math.max(0,math.min(s.duration or 0,(s.position or 0)+delta)))
end
function M.zoom(factor)
  local v=current(); if v then v.pdf_fit=false; v.zoom=math.max(.25,math.min(5,(v.zoom or 1)*factor)); M.action('zoom',v.zoom) end
end
function M.volume(delta)
  local v=current(); if v then v.volume=math.max(0,math.min(1,(v.volume or 1)+delta)); M.action('volume',v.volume) end
end
function M.reload()
  local v=current(); if not v then return end
  if v.kind~='web' or (v.status and v.status.state=='error') then release(v); M.refresh() else M.action('reload') end
end
function M.refresh_source(source)
  source=canonical(source)
  for _,v in pairs(views) do
    if v.source==source then
      v.current_url=nil
      -- Reopen also returns a page that navigated away to its source document.
      release(v)
    end
  end
  schedule()
end
function M.close(id)
  local v
  if id~=nil then v=active[id] else v=current() end
  if not v then return end
  dispose(v); views[v.win]=nil
  if vim.api.nvim_win_is_valid(v.win) then
    if #vim.api.nvim_tabpage_list_wins(0)>1 then vim.api.nvim_win_close(v.win,false)
    else vim.api.nvim_win_call(v.win,function() vim.cmd.enew() end) end
  end
  if vim.api.nvim_buf_is_valid(v.buf) then pcall(vim.api.nvim_buf_delete,v.buf,{force=true}) end
end
function M.open(source,opts)
  opts=opts or {}
  if not available() then warn('此功能需要本项目 macOS 原生预览构建。'); return false end
  M.setup()
  local kind=opts.kind or M.kind(source)
  if not kind then warn('无法识别预览类型。'); return false end
  source=canonical(source)
  if opts.win and vim.api.nvim_win_is_valid(opts.win) then vim.api.nvim_set_current_win(opts.win) end
  local command=opts.command
  if command==nil then command='rightbelow vnew' end
  if command~='' then vim.cmd(command) end
  local win=vim.api.nvim_get_current_win()
  if views[win] then dispose(views[win]) end
  local saved=remember(win)
  local buf=vim.api.nvim_create_buf(false,true)
  vim.api.nvim_buf_set_name(buf,'glow-'..kind..'://'..buf..'/'..source)
  vim.bo[buf].filetype='glow_'..kind; vim.bo[buf].bufhidden='wipe'; vim.bo[buf].swapfile=false; vim.bo[buf].modifiable=false
  vim.api.nvim_win_set_buf(win,buf)
  for k,v in pairs({number=false,relativenumber=false,signcolumn='no',foldcolumn='0',wrap=false,list=false,cursorline=false,cursorcolumn=false,spell=false,fillchars='eob: '}) do vim.wo[win][k]=v end
  local v={win=win,buf=buf,source=source,kind=kind,title=opts.title or vim.fs.basename(source),opts=opts,saved=saved,zoom=1,volume=1}
  views[win]=v
  local function map(lhs,fn,desc) vim.keymap.set('n',lhs,fn,{buffer=buf,silent=true,desc=desc}) end
  map('q',M.close,'关闭预览'); map('<Esc>',M.close,'关闭预览'); map('r',M.reload,'刷新预览')
  map('<Tab>','gt','下一个标签页'); map('<S-Tab>','gT','上一个标签页')
  map('<D-{>','gT','上一个标签页'); map('<D-}>','gt','下一个标签页')
  map('<C-Tab>','gt','下一个标签页'); map('<C-S-Tab>','gT','上一个标签页')
  map('i',function() M.action('focus') end,'进入原生面板'); map('<CR>',function() M.action('focus') end,'进入原生面板')
  map('g?',M.info,'预览来源与读取范围')
  if kind=='web' or kind=='pdf' then
    if kind=='pdf' then
      map(']p',function() M.action('next') end,'PDF 下一页'); map('[p',function() M.action('previous') end,'PDF 上一页')
      map('<PageDown>',function() M.action('next') end,'PDF 下一页'); map('<PageUp>',function() M.action('previous') end,'PDF 上一页')
    end
    map('+',function() M.zoom(1.1) end,'放大预览'); map('=',function() M.zoom(1.1) end,'放大预览'); map('-',function() M.zoom(1/1.1) end,'缩小预览')
    map('0',function()
      if kind=='pdf' then v.pdf_fit=true; M.action('fit') else v.zoom=1; M.action('zoom',1) end
    end,'恢复默认缩放')
  else
    map('<Space>',function() M.action('toggle') end,'播放或暂停')
    map('h',function() M.seek(-5) end,'后退五秒'); map('l',function() M.seek(5) end,'前进五秒')
    map('+',function() M.volume(.1) end,'提高音量'); map('=',function() M.volume(.1) end,'提高音量'); map('-',function() M.volume(-.1) end,'降低音量')
    map('0',function() M.action('seek',0) end,'回到开头')
  end
  M.refresh()
  return true
end
function M.from_tree(event)
  if not vim.g.neovide or (not M.supports(event.path) and not event.path:lower():match('%.ipynb$')) then return end
  local state=event.state
  local win,is_tree=require('neo-tree.utils').get_appropriate_window(state)
  local cmd=event.open_cmd or 'edit'
  local split=({split='split',sp='split',sb='split',vsplit='vsplit',vs='vsplit',['vert sb']='vsplit',tabnew='tabnew',tabedit='tabnew'})[cmd]
  if not split and is_tree then split=state.current_position=='right' and 'leftabove vnew' or 'rightbelow vnew' end
  local opener=event.path:lower():match('%.ipynb$') and require('config.media.notebook_edit').open or M.open
  local ok,err=pcall(opener,event.path,{win=win,command=split or ''})
  if not ok then warn(tostring(err)) end
  return {handled=true}
end
function M.setup()
  if configured then return end
  configured=true
  capsule.refresh_colors()
  require('config.media.synctex').setup()
  for lhs,rhs in pairs({['<C-Tab>']='gt',['<C-S-Tab>']='gT'}) do
    if vim.fn.maparg(lhs,'n')=='' then vim.keymap.set('n',lhs,rhs,{silent=true,desc='切换 Neovim 标签页'}) end
  end
  local group=vim.api.nvim_create_augroup('GlowNativePreview',{clear=true})
  local function refresh_colors()
    capsule.refresh_colors();for _,view in pairs(views) do title(view) end
  end
  vim.api.nvim_create_autocmd('ColorScheme',{group=group,callback=refresh_colors})
  vim.api.nvim_create_autocmd('User',{group=group,pattern='NvThemeReload',callback=refresh_colors})
  vim.api.nvim_create_autocmd({'BufWinEnter','BufWinLeave','WinEnter','WinClosed','WinResized','VimResized','WinScrolled','TabEnter'}, {group=group,callback=schedule})
  vim.api.nvim_create_autocmd({'TabLeave','VimLeavePre'},{group=group,callback=function()
    for _,v in pairs(views) do release(v) end
  end})
  vim.api.nvim_create_autocmd('VimLeavePre',{group=group,callback=function()
    if timer then timer:stop(); timer:close(); timer=nil end
    for _,v in pairs(views) do dispose(v) end
  end})
  vim.api.nvim_create_autocmd('BufWritePost',{group=group,pattern={'*.html','*.htm','*.css','*.js','*.mjs'},callback=function(event)
    local changed=canonical(event.file)
    for _,v in pairs(views) do
      if v.kind=='web' and not v.source:match('^%a+://') then
        local dir=vim.fs.dirname(v.source)..'/'
        if changed:sub(1,#dir)==dir and v.id then rpc('action',v.id,'reload') end
      end
    end
  end})
  vim.api.nvim_create_user_command('GlowMedia',function(a) M.open(a.args~='' and a.args or vim.api.nvim_buf_get_name(0)) end,{nargs='?',complete='file',desc='音频与视频原生预览'})
  vim.api.nvim_create_user_command('GlowWeb',function(a) M.open(a.args~='' and a.args or vim.api.nvim_buf_get_name(0),{kind='web'}) end,{nargs='?',complete='file',desc='内嵌网页预览'})
  vim.api.nvim_create_user_command('GlowPDF',function(a) M.open(a.args~='' and a.args or vim.api.nvim_buf_get_name(0),{kind='pdf'}) end,{nargs='?',complete='file',desc='原生 PDF 预览'})
  vim.api.nvim_create_user_command('GlowPreviewFocus',function() M.action('focus') end,{desc='进入原生预览面板'})
  vim.api.nvim_create_user_command('GlowPreviewClose',M.close,{desc='关闭原生预览面板'})
  vim.api.nvim_create_user_command('GlowPreviewInfo',M.info,{desc='预览来源与读取范围'})
  timer=vim.uv.new_timer()
  timer:start(500,500,vim.schedule_wrap(function() for id in pairs(active) do rpc('action',id,'status') end end))
end
return M
