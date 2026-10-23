-- Every platform owns its configuration and uses the same theme module paths.
-- Windows' home-config bridge also updates stdpath("config") before loading us.
local M = {}
local names = { ayu_light_customed = true, ayu_dark_customed = true }

function M.directory()
  if vim.fn.has("win32") ~= 1 then return nil end
  return vim.fs.joinpath(vim.fn.stdpath("config"), "lua", "config", "appearance", "themes")
end

function M.load(name)
  assert(names[name], "Unsupported Windows theme: " .. tostring(name))
  -- Share the normal require/cache route so the reload command in the theme
  -- file's header and this module's reload() always read the same user file.
  local theme = require("config.appearance.themes." .. name)
  assert(type(theme) == "table", "Theme must return a table: " .. name)
  return theme
end

function M.reload()
  if vim.fn.has("win32") ~= 1 then return false end
  local config = require("nvconfig").base46
  for _, mode in ipairs({ "light", "dark" }) do
    local name = "ayu_" .. mode
    local module = "config.appearance.themes." .. name .. "_customed"
    package.loaded[module] = nil
    config.changed_themes[name] = M.load(name .. "_customed")
  end
  require("base46").load_all_highlights()
  return true
end

return M
