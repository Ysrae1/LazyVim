local M = {}

if not vim.g.neovide then
  return M
end

vim.o.guifont = "FiraCode Nerd Font Mono:h16"
vim.opt.linespace = 0
-- Show the command line on demand instead of reserving an empty footer row.
vim.o.cmdheight = 0
vim.g.neovide_text_gamma = 0.0
vim.g.neovide_text_contrast = 0.5

vim.g.neovide_padding_top = 0
vim.g.neovide_padding_bottom = 0
vim.g.neovide_padding_right = 0
vim.g.neovide_padding_left = 0

vim.g.neovide_floating_shadow = true
vim.g.neovide_floating_z_height = 2
vim.g.neovide_light_angle_degrees = 45
vim.g.neovide_light_radius = 10
vim.g.neovide_floating_blur_amount_x = 24.0
vim.g.neovide_floating_blur_amount_y = 24.0
vim.g.neovide_floating_corner_radius = 0.48
-- Expose the whole-window material through Normal while retaining solid UI
-- highlights, selections and capsules in their existing theme colors.
vim.g.neovide_opacity = 1.0
vim.g.neovide_normal_opacity = 0.78
vim.g.neovide_refresh_rate = 120
vim.g.neovide_window_blurred = true
require("config.platform.glass").setup()
require("config.appearance.transparency").setup()
vim.g.neovide_theme = "auto"
vim.g.neovide_remember_window_size = true
vim.g.neovide_profiler = false

vim.g.neovide_cursor_smooth_blink = true
vim.g.neovide_cursor_animation_length = 0.15
vim.g.neovide_cursor_short_animation_length = 0.04
vim.g.neovide_cursor_trail_size = 0.7
vim.g.neovide_cursor_vfx_mode = "pixiedust"
vim.g.neovide_cursor_vfx_opacity = 200.0
vim.g.neovide_cursor_vfx_particle_lifetime = 0.8
vim.g.neovide_cursor_vfx_particle_density = 4.0
vim.g.neovide_cursor_vfx_particle_speed = 15.0
vim.g.neovide_cursor_vfx_particle_phase = 1.5
vim.g.neovide_cursor_vfx_particle_curl = 1.0

local state_dir = vim.fn.stdpath("state") .. "/neovide"
local scale_file = state_dir .. "/scale_factor.txt"
local legacy_scale_file = vim.fn.stdpath("config") .. "/archive/legacy/scale_factor.txt"

local function parse_scale(value)
  local scale = tonumber(value)
  if not scale or scale ~= scale or scale == math.huge or scale == -math.huge then
    return nil
  end
  return math.max(0.5, math.min(2.0, scale))
end

local function read_scale(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local value = file:read("*a")
  file:close()
  return parse_scale(value)
end

function M.load_scale_factor()
  vim.g.neovide_scale_factor = read_scale(scale_file)
    or read_scale(legacy_scale_file)
    or parse_scale(vim.g.neovide_scale_factor)
    or 1.0
end

function M.save_scale_factor()
  local scale = parse_scale(vim.g.neovide_scale_factor) or 1.0
  vim.g.neovide_scale_factor = scale
  local ok, err = pcall(function()
    vim.fn.mkdir(state_dir, "p")
    if vim.fn.writefile({ tostring(scale) }, scale_file) ~= 0 then
      error("could not write " .. scale_file)
    end
  end)
  if not ok then
    vim.notify("Could not save Neovide scale: " .. tostring(err), vim.log.levels.WARN)
  end
end

local function adjust_scale(delta)
  vim.g.neovide_scale_factor = parse_scale((parse_scale(vim.g.neovide_scale_factor) or 1.0) + delta)
end

if vim.fn.has("macunix") == 1 then
-- Keep the original zoom shortcuts and apply the saved value during startup.
vim.keymap.set("n", "<D-->", function()
  adjust_scale(0.1)
end, { silent = true, desc = "Increase Neovide scale" })
vim.keymap.set("n", "<D-9>", function()
  adjust_scale(-0.1)
end, { silent = true, desc = "Decrease Neovide scale" })
vim.keymap.set("n", "<D-0>", function()
  vim.g.neovide_scale_factor = 1.0
end, { silent = true, desc = "Reset Neovide scale" })

end

M.load_scale_factor()
local group = vim.api.nvim_create_augroup("UserNeovideScale", { clear = true })
vim.api.nvim_create_autocmd("SessionLoadPost", { group = group, callback = M.load_scale_factor })
vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.save_scale_factor })

require("config.media.image").setup()
require("config.media.preview").setup()
require("config.media.notebook").setup()
require("config.media.notebook_edit").setup()
require("config.media.book").setup()
require("config.media.open").setup()

return M
