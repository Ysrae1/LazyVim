-- Windows float geometry is independent of macOS native window material.
-- All multigrid floats share these settings, including completion, notifications,
-- terminals and preview controls. Composed picker children retain the renderer's
-- shadow exclusions, so a picker still casts one outer shadow.
local M = {}
local applied, configured, initialized = {}, false, false
local defaults = {
  floating_shadow = true,
  floating_z_height = 6,
  light_angle_degrees = 45,
  floating_corner_radius = 0.48,
}

local function windows_gui()
  return vim.g.neovide and vim.fn.has("win32") == 1
end

local function profile()
  local value = vim.g.glow_windows_appearance
  return type(value) == "table" and value or {}
end

local function theme_value(name, fallback, maximum)
  local theme = profile()[vim.o.background]
  local value = type(theme) == "table" and theme[name] or nil
  if type(value) ~= "number" or value ~= value or value < 0 or value > maximum then
    return fallback
  end
  return value
end

local function material_settings()
  return require("config.appearance.transparency").config.windows
end

local function material_theme()
  return material_settings()[vim.o.background]
end

-- One Windows material policy for side panels and editor-backed float classes.
-- Explicit popup mode="custom" remains under popup_materials.lua user control.
function M.material_blend(fallback)
  if not windows_gui() then return fallback end
  local value = material_settings().material_blend
  if type(value) ~= "number" or value ~= value or value < 0 or value > 100 then
    return fallback
  end
  return math.floor(value)
end

function M.popup_blend(value)
  if not windows_gui() then return value end
  local maximum = theme_value("popup_blend", material_theme().popup_blend, 100)
  return math.min(value, math.floor(maximum))
end

local function valid(name, value)
  if name == "floating_shadow" then
    return type(value) == "boolean"
  end
  if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
    return false
  end
  if name == "normal_opacity" then
    return value >= 0 and value <= 1
  elseif name == "floating_corner_radius" then
    return value >= 0 and value <= 1
  elseif name == "light_angle_degrees" then
    return value >= 0 and value < 90
  end
  return value >= 0
end

function M.setup(opts)
  if not windows_gui() then
    return false
  end
  opts = opts or {}
  -- Neovide publishes Rust defaults into g: before user init.lua runs. At the
  -- platform-config entry point, explicitly install our profile once; presence
  -- of a global at that stage does not establish user ownership. Later refreshes
  -- only update values this module owns, preserving subsequent user changes.
  local initialize = opts.initialize == true and not initialized
  -- Optional user profile, e.g.:
  -- vim.g.glow_windows_appearance = { floating_z_height = 4 }
  -- Material defaults live together in appearance/transparency.lua. Direct
  -- g:neovide_* changes after initialization retain their existing priority.
  local settings = profile()
  local values = vim.tbl_extend("force", defaults, {
    normal_opacity = theme_value("normal_opacity", material_theme().normal_opacity, 1),
  })
  for name, fallback in pairs(values) do
    local key = "neovide_" .. name
    local current = vim.g[key]
    if initialize or current == nil or (applied[name] ~= nil and current == applied[name]) then
      local value = settings[name]
      if value == nil or not valid(name, value) then
        value = fallback
      end
      vim.g[key] = value
      applied[name] = value
    end
  end
  initialized = initialized or initialize
  if not configured then
    configured = true
    local group = vim.api.nvim_create_augroup("GlowWindowsAppearance", { clear = true })
    local function refresh()
      M.setup()
      require("config.appearance.transparency").apply()
    end
    vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = refresh })
    vim.api.nvim_create_autocmd("OptionSet", { group = group, pattern = "background", callback = refresh })
    vim.api.nvim_create_autocmd("User", { group = group, pattern = "NvThemeReload", callback = refresh })
  end
  return true
end

return M
