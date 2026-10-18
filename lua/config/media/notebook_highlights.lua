local M = {}

-- Pinned Molten assigns one group to every virtual output chunk, including
-- Out[n], status and body. Keep those as normal text without rewriting its
-- extmarks; separate success/error text colors need an upstream chunk API.
function M.apply()
  vim.api.nvim_set_hl(0, "MoltenVirtualText", { link = "Normal" })
end

local configured = false

function M.setup()
  M.apply()
  if configured then
    return
  end
  configured = true
  local group = vim.api.nvim_create_augroup("GlowNotebookOutputHighlights", { clear = true })
  local function after_theme()
    vim.schedule(M.apply)
  end
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = after_theme })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "NvThemeReload", callback = after_theme })
end

return M
