vim.o.shell = "/bin/zsh --login"
vim.o.encoding = "utf-8"
vim.o.fileencoding = "utf-8"
vim.wo.wrap = true
vim.wo.linebreak = true
vim.wo.list = false
vim.o.number = true
vim.o.relativenumber = true

vim.cmd([[highlight FloatingWindow guibg=#2E3440]])
vim.cmd([[highlight FloatingBorder guifg=#81A1C1 guibg=#2E3440]])

-- This is a GUI decoration only. Missing animation tools must not block startup.
-- The nvidec launcher skips this opening animation.
if vim.env.NVIM_SKIP_MATRIX_INTRO == "1" or not vim.g.neovide or vim.fn.executable("cmatrix-gm") ~= 1 then
  return
end

local api = vim.api
local active
local group = api.nvim_create_augroup("UserMatrixIntro", { clear = true })

local function geometry()
  local columns = math.max(1, vim.o.columns)
  local lines = math.max(1, vim.o.lines)
  return {
    relative = "editor",
    width = columns,
    height = lines,
    col = 0,
    row = 0,
    zindex = 250,
  }
end

local function cleanup()
  local intro = active
  if not intro then
    return
  end
  active = nil
  if intro.job and intro.job > 0 then
    pcall(vim.fn.jobstop, intro.job)
  end
  if intro.win and api.nvim_win_is_valid(intro.win) then
    pcall(api.nvim_win_close, intro.win, true)
  end
  if api.nvim_buf_is_valid(intro.buf) then
    pcall(api.nvim_buf_delete, intro.buf, { force = true })
  end
end

local function open_intro()
  if active then
    return
  end
  local intro = { buf = api.nvim_create_buf(false, true) }
  active = intro
  vim.bo[intro.buf].bufhidden = "wipe"
  local opts = geometry()
  opts.style = "minimal"
  opts.border = "none"
  local opened, win = pcall(api.nvim_open_win, intro.buf, true, opts)
  if not opened then
    cleanup()
    return
  end
  intro.win = win
  local started, job = pcall(vim.fn.jobstart, { "cmatrix-gm", "--intro", "--fps", "60", "--fade", "4", "-o" }, {
    term = true,
    on_exit = function()
      vim.schedule(cleanup)
    end,
  })
  if not started or job <= 0 then
    cleanup()
    return
  end
  intro.job = job
  -- Stop the terminal job as well as closing its window and buffer.
  vim.defer_fn(cleanup, 2000)
end

api.nvim_create_autocmd("VimEnter", {
  group = group,
  once = true,
  callback = function()
    vim.schedule(open_intro)
  end,
})
api.nvim_create_autocmd("VimResized", {
  group = group,
  callback = function()
    if active and active.win and api.nvim_win_is_valid(active.win) then
      pcall(api.nvim_win_set_config, active.win, geometry())
    end
  end,
})
api.nvim_create_autocmd("VimLeavePre", { group = group, callback = cleanup })
