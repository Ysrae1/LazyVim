local M = {}

function M.render(width, system)
  if width <= 0 then return "" end
  local icon = ({ Darwin = "", Linux = "", Windows_NT = "" })[system]
  local title = " " .. (icon and icon .. " " or "") .. "File Explorer"
  local text = ""
  -- Clip by screen cells, preserving the left anchor and complete UTF-8 glyphs.
  for index = 0, vim.fn.strchars(title) - 1 do
    local next_text = text .. vim.fn.strcharpart(title, index, 1)
    if vim.fn.strdisplaywidth(next_text) > width then break end
    text = next_text
  end
  text = text .. string.rep(" ", width - vim.fn.strdisplaywidth(text))
  local separator = vim.g.neovide and " " or "│"
  return "%#NeoTreeNormal#" .. text .. "%#NeoTreeWinSeparator#" .. separator
end

function M.get()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neo-tree" then
      return M.render(vim.api.nvim_win_get_width(win), vim.uv.os_uname().sysname)
    end
  end
  return ""
end

return M
