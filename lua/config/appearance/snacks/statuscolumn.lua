local M = {}

function M.get()
  local value = require("snacks.statuscolumn").get()
  local win = vim.g.statusline_winid or vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.wo[win].signcolumn == "no" or vim.b[buf].snacks_statuscolumn_left == false then
    return value
  end
  -- Keep Snacks' two-column left slot, number formatting, highlights and mouse
  -- callback. One extra cell before the number field gives diagnostics a gap
  -- on both sides without changing component order or truncating another slot.
  return (value:gsub("%%=", " %%=", 1))
end

function M.setup()
  vim.o.statuscolumn = [[%!v:lua.require'config.appearance.snacks.statuscolumn'.get()]]
end

return M
