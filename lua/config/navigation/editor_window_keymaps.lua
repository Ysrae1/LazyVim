-- Keep layout-changing shortcuts inside the editing area. Directional focus
-- navigation remains native so the file tree and AI panes stay reachable.
local M = {}

function M.setup()
  local panes = require("config.navigation.editor_windows")
  local function bind(lhs, callback, desc, modes)
    vim.keymap.set(modes or "n", lhs, callback, { silent = true, desc = desc })
  end
  for _, item in ipairs({
    { "Left", "left", "H" }, { "Right", "right", "L" },
    { "Up", "up", "K" }, { "Down", "down", "J" },
  }) do
    local direction = item[2]
    local desc = "Move Editor Window " .. item[1]
    bind("<C-S-" .. item[1] .. ">", function() panes.move(direction) end, desc, { "n", "x" })
    bind("<C-S-" .. item[1] .. ">",
      "<C-\\><C-n><Cmd>lua require('config.navigation.editor_windows').move('" .. direction .. "')<CR>",
      desc, { "i", "t" })
    bind("<C-w>" .. item[3], function() panes.move(direction) end, desc)
  end
  bind("<C-w>x", function() panes.swap() end, "Swap Editor Windows")
  bind("<C-w><C-x>", function() panes.swap() end, "Swap Editor Windows")
  bind("<C-w>r", function() panes.rotate() end, "Rotate Editor Windows")
  bind("<C-w><C-r>", function() panes.rotate() end, "Rotate Editor Windows")
  bind("<C-w>R", function() panes.rotate(true) end, "Rotate Editor Windows Reverse")
  bind("<C-w>=", function() panes.equalize() end, "Equalize Editor Windows")
  bind("<C-w>o", function() panes.close_others() end, "Close Other Editor Windows")
  bind("<C-w><C-o>", function() panes.close_others() end, "Close Other Editor Windows")
  -- LazyVim has a direct mapping here in addition to the Ctrl-W proxy.
  bind("<leader>wo", function() panes.close_others() end, "Close Other Editor Windows")
end

return M
