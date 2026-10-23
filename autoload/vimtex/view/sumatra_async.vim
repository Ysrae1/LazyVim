" Embedded SyncTeX first; direct-argv Sumatra fallback with reverse RPC.
function! vimtex#view#sumatra_async#new() abort
  let l:viewer = vimtex#view#_template#new({'name': 'Glow PDF'})
  let l:viewer._check = function('s:check')
  let l:viewer._start = function('s:start')
  let l:viewer._forward_search = function('s:start')
  return l:viewer
endfunction

function! s:check() dict abort
  return luaeval('require("config.latex.sumatra").check()')
endfunction

function! s:start(outfile) dict abort
  call luaeval('require("config.latex.sumatra").view(_A, true)', a:outfile)
endfunction
