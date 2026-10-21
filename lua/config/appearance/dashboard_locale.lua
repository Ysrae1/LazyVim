-- Keep Snacks' real startup snapshot and highlight segments; translate UI labels only.
local M = {}
function M.startup(opts)
  local section = require("snacks.dashboard").sections.startup(opts)
  if require("config.platform.locale").current() ~= "zh" then return section end
  local text = section and section.text
  if not (text and text[1] and text[3] and text[4]) then return section end
  local locale = require("config.platform.locale")
  text[1][1] = text[1][1]:gsub("Neovim loaded", locale.t("Neovim loaded"), 1)
  text[3][1] = locale.t(text[3][1])
  -- The actual elapsed value comes from Snacks. Only its unit is localized.
  text[4][1] = text[4][1]:gsub("ms$", " " .. locale.t("milliseconds"), 1)
  return section
end
return M
