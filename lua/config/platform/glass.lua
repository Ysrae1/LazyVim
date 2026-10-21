local function T(text) return require("config.platform.locale").t(text) end
-- Native macOS material with independent, honest opacity/blur controls.
local M = {}
local configured, defaults = false, nil
local function notify(text, level)
  vim.notify(require("config.platform.locale").t(text), level or vim.log.levels.INFO, { title = 'Liquid Glass' })
end
local function number(value, minimum, maximum)
  value = tonumber(value)
  return value and value == value and value >= minimum and value <= maximum and value or nil
end
function M.opacity(value)
  value = number(value, 0, 1)
  if not value then notify(T("Enter a background opacity from 0 to 1."), vim.log.levels.WARN); return false end
  -- Only the Normal background fades. Highlight/selection colors and text stay
  -- readable even when the user chooses a fully transparent editor background.
  vim.g.neovide_normal_opacity = value
  vim.g.neovide_opacity = 1
  return true
end
function M.blur(value)
  value = number(value, 0, 100)
  if not value then notify(T("Enter a floating-window blur amount from 0 to 100."), vim.log.levels.WARN); return false end
  vim.g.neovide_floating_blur_amount_x = value
  vim.g.neovide_floating_blur_amount_y = value
  return true
end
function M.reset()
  if not defaults then return end
  vim.g.neovide_liquid_glass = defaults.enabled
  vim.g.neovide_opacity = defaults.opacity
  vim.g.neovide_normal_opacity = defaults.normal
  vim.g.neovide_floating_blur_amount_x = defaults.x
  vim.g.neovide_floating_blur_amount_y = defaults.y
end
function M.status()
  return { enabled = vim.g.neovide_liquid_glass == true,
    opacity = vim.g.neovide_normal_opacity or vim.g.neovide_opacity or 1,
    blur_x = vim.g.neovide_floating_blur_amount_x or 0,
    blur_y = vim.g.neovide_floating_blur_amount_y or 0 }
end
local function input(action)
  local current = M.status()
  require("config.platform.locale").input({ prompt = action == 'opacity' and T("Background Opacity (0–1): ") or T("Floating-Window Blur (0–100): "),
    default = tostring(action == 'opacity' and current.opacity or current.blur_x) },
    function(value) if value then M[action](value) end end)
end
function M.setup()
  if configured or not vim.g.neovide then return end
  configured = true
  defaults = { enabled = true, opacity = vim.g.neovide_opacity or 1,
    normal = vim.g.neovide_normal_opacity or 1,
    x = vim.g.neovide_floating_blur_amount_x or 2, y = vim.g.neovide_floating_blur_amount_y or 2 }
  if vim.g.neovide_native_glass then vim.g.neovide_liquid_glass = true end
  require("config.platform.locale").command('GlowGlass', function(args)
    if not vim.g.neovide_native_glass then
      notify(T("This feature requires a current Glow build with native macOS materials."), vim.log.levels.WARN); return
    end
    local action, value = args.fargs[1] or 'status', args.fargs[2]
    if action == 'on' or action == 'off' then vim.g.neovide_liquid_glass = action == 'on'
    elseif action == 'toggle' then vim.g.neovide_liquid_glass = not vim.g.neovide_liquid_glass
    elseif action == 'reset' then M.reset()
    elseif action == 'opacity' or action == 'blur' then
      if value then M[action](value) else input(action) end
    elseif action == 'status' then
      local state = M.status()
      notify((T("Native material %s · Background %.0f%% · Floating-window blur %.0f / %.0f\nmacOS controls native glass blur; blur adjusts the additional blur of Neovide floating windows.")):format(
        state.enabled and T("on") or T("off"), state.opacity * 100, state.blur_x, state.blur_y))
    else notify(T("Usage: GlowGlass on | off | toggle | opacity [0–1] | blur [0–100] | reset | status"), vim.log.levels.WARN) end
  end, { nargs = '*', desc = T("Native Glass, Background Opacity and Floating-Window Blur"), complete = function(arglead)
    return vim.tbl_filter(function(item) return item:sub(1, #arglead) == arglead end,
      { 'on', 'off', 'toggle', 'opacity', 'blur', 'reset', 'status' })
  end })
end
return M
