-- Mac 编辑区背景不透明度：0=透明，1=实心；Light / Dark 可分别调整。
-- 保存后重载：:lua require('config.platform.macos_appearance').reload()
-- :GlowGlass opacity 的临时值保留到下一次主题切换／主题重载或本模块重载。
local M = {}

M.config = {
  light = { normal_opacity = 0.95 },
  dark = { normal_opacity = 0.85 },
}

local function macos_gui()
  return vim.g.neovide and vim.fn.has("macunix") == 1 and vim.fn.has("win32") ~= 1
end

function M.normal_opacity()
  local theme = M.config[vim.o.background]
  local value = type(theme) == "table" and theme.normal_opacity or nil
  if type(value) ~= "number" or value ~= value or value < 0 or value > 1 then
    return 0.85
  end
  return value
end

function M.apply()
  if not macos_gui() then
    return false
  end
  vim.g.neovide_normal_opacity = M.normal_opacity()
  -- Startup calls this before Glass captures defaults. Later refreshes reuse
  -- existing editor-mode material rules (including Avante), never their config.
  local materials = package.loaded["config.appearance.transparency"]
  if materials and type(materials.apply) == "function" then
    materials.apply()
  end
  return true
end

function M.setup()
  if not macos_gui() then
    return false
  end
  local group = vim.api.nvim_create_augroup("GlowMacOSAppearance", { clear = true })
  local function refresh()
    M.apply()
  end
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = refresh })
  vim.api.nvim_create_autocmd("OptionSet", { group = group, pattern = "background", callback = refresh })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "NvThemeReload", callback = refresh })
  return M.apply()
end

function M.reload()
  if not macos_gui() then
    return false
  end
  package.loaded["config.platform.macos_appearance"] = nil
  local applied = require("config.platform.macos_appearance").setup()
  vim.cmd("redraw!")
  return applied
end

return M
