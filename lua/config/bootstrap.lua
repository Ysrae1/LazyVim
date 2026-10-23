-- Startup order lives here; feature settings stay in their existing modules.
local M = {}

function M.setup()
  -- Apply GUI options and register native integrations before plugin startup
  -- can process the first UI events. The intro also precedes theme selection.
  require("config.platform.neovide")
  require("config.appearance.intro")
  require("config.appearance.startup")

  require("config.lazy")

  require("config.platform.locale").setup()
  require("config.platform.macos_keymaps")
  require("config.editor.settings")
end

return M
