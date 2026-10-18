" Keep VimTeX's Skim/SyncTeX integration, but never wait for macOS automation.
function! vimtex#view#skim_async#new() abort
  let l:viewer = vimtex#view#skim#new()
  let l:viewer._check = function('s:check')
  let l:viewer._start = function('s:start')
  let l:viewer._forward_search = function('s:start')
  let l:viewer.compiler_callback = function('s:compiler_callback')
  return l:viewer
endfunction

function! s:check() dict abort
  return luaeval('require("config.latex.skim").check()')
endfunction

function! s:start(outfile) dict abort
  call luaeval('require("config.latex.skim").view(_A[1], true, true, true)', [a:outfile])
endfunction

function! s:compiler_callback(outfile) dict abort
  let l:open = g:vimtex_view_automatic && !has_key(self, 'started_through_callback')
  call luaeval('require("config.latex.skim").view(_A[1], _A[2] ~= 0, _A[3] ~= 0, false)',
        \ [a:outfile, l:open, g:vimtex_view_skim_sync])
  let self.started_through_callback = 1
endfunction
