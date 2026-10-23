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
local namespace = api.nvim_create_namespace("GlowMatrixIntro")
local function editor_material()
  local normal = api.nvim_get_hl(0, { name = "Normal", link = false })
  local policy = require("config.appearance.popup_materials").resolve("matrix_intro", normal, normal.bg)
  -- Use the editor's RGB and absolute background alpha, including before a
  -- theme defines Normal. The frontend replaces the covered cells with Src.
  for _, name in ipairs({ "Normal", "NormalNC", "NormalFloat", "EndOfBuffer" }) do
    api.nvim_set_hl(namespace, name, vim.tbl_extend("force", normal, { blend = policy.blend }))
  end
  if active and active.win and api.nvim_win_is_valid(active.win) then
    api.nvim_win_set_hl_ns(active.win, namespace)
  end
end
editor_material()

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

local function open_cover()
  if active then
    return
  end
  local intro = { buf = api.nvim_create_buf(false, true) }
  active = intro
  vim.bo[intro.buf].bufhidden = "wipe"
  local opts = geometry()
  opts.style = "minimal"
  opts.border = "none"
  opts.focusable = false
  local opened, win = pcall(api.nvim_open_win, intro.buf, false, opts)
  if not opened then
    cleanup()
    return
  end
  intro.win = win
  vim.w[win].glow_popup_profile = "matrix_intro"
  api.nvim_win_set_hl_ns(win, namespace)
  vim.wo[win].winblend = 0
  require("config.appearance.float_shadows").refresh()
end

local function start_intro()
  local intro = active
  if not intro or not api.nvim_win_is_valid(intro.win) then
    cleanup()
    return
  end
  -- The dashboard must keep its original current window during initialization.
  -- Only enter the cover temporarily to attach the asynchronous terminal job.
  local started, job = pcall(api.nvim_win_call, intro.win, function()
    return vim.fn.jobstart({ "cmatrix-gm", "--intro", "--fps", "60", "--fade", "4", "-o" }, {
      term = true,
      on_exit = function()
        vim.schedule(cleanup)
      end,
    })
  end)
  if not started or job <= 0 then
    cleanup()
    return
  end
  intro.job = job
  -- Stop the terminal job as well as closing its window and buffer.
  vim.defer_fn(cleanup, 2000)
end

-- Create the cover before any plugin can flush a half-initialized dashboard.
-- Neovide attaches its UI before sourcing init.lua, so editor geometry is ready.
open_cover()
api.nvim_create_autocmd("VimEnter", {
  group = group,
  once = true,
  callback = start_intro,
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
api.nvim_create_autocmd("ColorScheme", { group = group, callback = editor_material })
