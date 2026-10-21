-- Compatibility entry point; Notebook sessions retain their buffer lifetime.
local M = {}
function M.set(win, buf, value)
  local editor = package.loaded["config.media.notebook_edit"]
  if not editor or not editor.supports(vim.api.nvim_buf_get_name(buf)) or editor.status(buf) == nil then return false end
  return require("config.media.winbar").set(win, buf, value)
end
function M.refresh()
  return require("config.media.winbar").refresh()
end
function M.setup()
  return require("config.media.winbar").setup()
end
return M
