local M = {}

if not vim.g.neovide then
  return M
end

local cjk_font = vim.fn.has("macunix") == 1 and "PingFang SC" or "Noto Sans Mono CJK SC"
vim.o.guifont = "FiraCode Nerd Font Mono," .. cjk_font .. ":h16"
vim.opt.linespace = 0
-- Show the command line on demand instead of reserving an empty footer row.
vim.o.cmdheight = 0
vim.g.neovide_text_gamma = 0.0
vim.g.neovide_text_contrast = 0.5

vim.g.neovide_padding_top = 0
vim.g.neovide_padding_bottom = 0
vim.g.neovide_padding_right = 0
vim.g.neovide_padding_left = 0

local windows = vim.fn.has("win32") == 1
if windows then
  require("config.platform.windows_appearance").setup({ initialize = true })
else
  vim.g.neovide_floating_shadow = true
  vim.g.neovide_floating_z_height = 2
  vim.g.neovide_light_angle_degrees = 45
  vim.g.neovide_floating_corner_radius = 0.48
  vim.g.neovide_normal_opacity = 0.85
end
vim.g.neovide_light_radius = 10
vim.g.neovide_floating_blur_amount_x = 24.0
vim.g.neovide_floating_blur_amount_y = 24.0
-- Expose the whole-window material through Normal while retaining solid UI
-- highlights, selections and capsules in their existing theme colors.
vim.g.neovide_opacity = 1.0
vim.g.neovide_refresh_rate = 120
vim.g.neovide_window_blurred = true
require("config.platform.glass").setup()
require("config.appearance.transparency").setup()
require("config.appearance.render_roles").setup()
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

local zoom = require("config.platform.neovide_zoom")
M.load_scale_factor = zoom.load_scale_factor
M.save_scale_factor = zoom.save_scale_factor
zoom.setup()

require("config.media.image").setup()
require("config.media.preview").setup()
require("config.media.notebook").setup()
require("config.media.notebook_edit").setup()
require("config.media.book").setup()
require("config.media.open").setup()

return M
