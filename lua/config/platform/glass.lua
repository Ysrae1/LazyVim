-- Native macOS material with independent, honest opacity/blur controls.
local M = {}
local configured, defaults = false, nil
local function notify(text, level)
  vim.notify(text, level or vim.log.levels.INFO, { title = 'Liquid Glass' })
end
local function number(value, minimum, maximum)
  value = tonumber(value)
  return value and value == value and value >= minimum and value <= maximum and value or nil
end
function M.opacity(value)
  value = number(value, 0, 1)
  if not value then notify('背景不透明度请输入 0～1。', vim.log.levels.WARN); return false end
  -- Only the Normal background fades. Highlight/selection colors and text stay
  -- readable even when the user chooses a fully transparent editor background.
  vim.g.neovide_normal_opacity = value
  vim.g.neovide_opacity = 1
  return true
end
function M.blur(value)
  value = number(value, 0, 100)
  if not value then notify('浮窗模糊请输入 0～100。', vim.log.levels.WARN); return false end
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
  vim.ui.input({ prompt = action == 'opacity' and '背景不透明度 (0～1): ' or '浮窗模糊 (0～100): ',
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
  vim.api.nvim_create_user_command('GlowGlass', function(args)
    if not vim.g.neovide_native_glass then
      notify('此功能需要本项目的新 macOS 原生材质构建。', vim.log.levels.WARN); return
    end
    local action, value = args.fargs[1] or 'status', args.fargs[2]
    if action == 'on' or action == 'off' then vim.g.neovide_liquid_glass = action == 'on'
    elseif action == 'toggle' then vim.g.neovide_liquid_glass = not vim.g.neovide_liquid_glass
    elseif action == 'reset' then M.reset()
    elseif action == 'opacity' or action == 'blur' then
      if value then M[action](value) else input(action) end
    elseif action == 'status' then
      local state = M.status()
      notify(('原生材质%s · 背景 %.0f%% · 浮窗模糊 %.0f / %.0f\n原生玻璃模糊由 macOS 控制；blur 调整 Neovide 浮窗的附加模糊。'):format(
        state.enabled and '开启' or '关闭', state.opacity * 100, state.blur_x, state.blur_y))
    else notify('用法：GlowGlass on | off | toggle | opacity [0～1] | blur [0～100] | reset | status', vim.log.levels.WARN) end
  end, { nargs = '*', desc = '原生玻璃、背景透明度与浮窗模糊', complete = function(arglead)
    return vim.tbl_filter(function(item) return item:sub(1, #arglead) == arglead end,
      { 'on', 'off', 'toggle', 'opacity', 'blur', 'reset', 'status' })
  end })
end
return M
