local M = {}

-- A terminal paints an explicit cap background as a whole rectangular cell.
-- Like the existing right cap, leave its outside to the containing bar. Only
-- the cap foreground carries the capsule color; solid bodies keep their colors.
function M.apply()
  if vim.g.neovide then return end
  local config = require("nvconfig").ui.statusline
  local groups = { "AvanteReversedTitle", "AvanteReversedSubtitle", "AvanteReversedThirdTitle" }
  if config.theme == "minimal" and config.separator_style == "round" then
    for _, mode in ipairs({ "Normal", "Visual", "Insert", "Terminal", "NTerminal", "Replace", "Confirm", "Command", "Select" }) do
      groups[#groups + 1] = "St_" .. mode .. "ModeSep"
    end
    for _, name in ipairs({ "file", "Pos", "cwd", "lsp" }) do
      groups[#groups + 1] = "St_" .. name .. "_sep"
    end
  end
  for _, name in ipairs(groups) do
    local attrs = vim.api.nvim_get_hl(0, { name = name, link = false, create = false })
    if next(attrs) and (attrs.bg ~= nil or attrs.ctermbg ~= nil) then
      attrs.bg, attrs.ctermbg = nil, nil
      vim.api.nvim_set_hl(0, name, attrs)
    end
  end
end

return M
