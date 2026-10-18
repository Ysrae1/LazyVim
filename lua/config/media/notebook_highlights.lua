local M = {}

local function color(group, fallback)
  local hl = vim.api.nvim_get_hl(0, { name = group, link = false, create = false })
  return hl.fg or fallback
end

-- The Python provider adapter assigns these groups before Molten's own write.
-- Changing a theme only changes groups; no output extmarks are rewritten.
function M.apply()
  vim.api.nvim_set_hl(0, "MoltenVirtualText", { link = "Normal" })
  local dark = vim.o.background == "dark"
  local palette = {}
  local ok, base = pcall(function() return require("base46").get_theme_tb("base_16") end)
  if ok then palette = base or {} end
  local function themed(key, group, fallback)
    local value = palette[key]
    if type(value) == "string" then value = tonumber(value:gsub("^#", ""), 16) end
    return type(value) == "number" and value or color(group, fallback)
  end
  vim.api.nvim_set_hl(0, "GlowNotebookOutputNumber", { fg = themed("base0D", "Function", dark and 0x96d7f3 or 0x21759b), bold = true })
  vim.api.nvim_set_hl(0, "GlowNotebookOutputSuccess", { fg = themed("base0B", "DiagnosticOk", dark and 0xb5f297 or 0x397825), bold = true })
  vim.api.nvim_set_hl(0, "GlowNotebookOutputFailure", { fg = themed("base08", "DiagnosticError", dark and 0xf07178 or 0xc02738), bold = true })
  vim.api.nvim_set_hl(0, "GlowNotebookOutputError", { fg = themed("base08", "DiagnosticError", dark and 0xf07178 or 0xc02738) })
  vim.api.nvim_set_hl(0, "GlowNotebookOutputRunning", { fg = themed("base0A", "DiagnosticWarn", dark and 0xe6c07b or 0x946400), bold = true })
  vim.api.nvim_set_hl(0, "GlowNotebookOutputPending", { link = "DiagnosticInfo" })
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
