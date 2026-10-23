-- Native media integrations are registered together, in their original order.
local M = {}

function M.setup()
  require("config.media.image").setup()
  require("config.media.preview").setup()
  require("config.media.notebook").setup()
  require("config.media.notebook_edit").setup()
  require("config.media.book").setup()
  require("config.media.open").setup()
end

return M
