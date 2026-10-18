local M = {}

-- Use the theme's named UI colors, since this config's base16 syntax slots
-- do not follow the ANSI red/green/blue order.
function M.apply(buf)
  if not package.loaded.base46 then
    return
  end
  local colors = require("base46").get_theme_tb("base_30")
  local names = {
    "black", "red", "green", "yellow", "blue", "purple", "cyan", "white",
    "light_grey", "baby_pink", "vibrant_green", "sun", "nord_blue", "pink", "teal", "white",
  }
  for index, name in ipairs(names) do
    local key = "terminal_color_" .. (index - 1)
    vim.g[key] = colors[name]
    if buf then
      vim.b[buf][key] = colors[name]
    end
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("UserTerminalColors", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "NvThemeReload",
    callback = function()
      M.apply()
    end,
  })
  vim.api.nvim_create_autocmd("TermOpen", {
    group = group,
    callback = function(event)
      M.apply(event.buf)
    end,
  })
  M.apply()
end

return M
