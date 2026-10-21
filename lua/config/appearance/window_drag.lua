local M = {}

local original = "%!v:lua.require('nvchad.tabufline.modules')()"
local wrapped = "%!v:lua.require('config.appearance.window_drag').render()"

-- Explicitly mark NvChad's alignment fill, not every cell that looks blank:
-- padding inside buffer labels and the GitHub/theme/close buttons stays theirs.
function M.wrap(tabline)
  if not vim.g.neovide_window_drag_supported then return tabline end
  return (tabline:gsub("%%#TbFill#%%=", function()
    return "%#TbFill#%@v:lua.GlowWindowDrag@%=%T"
  end, 1))
end

function M.render()
  return M.wrap(require("nvchad.tabufline.modules")())
end

function M.click(_, clicks, button, modifiers)
  if not vim.g.neovide_window_drag_supported or clicks ~= 1 or button ~= "l"
    or type(modifiers) ~= "string" or modifiers:find("[^ ]") then
    return
  end
  local channel = vim.g.neovide_channel_id
  local mouse = vim.fn.getmousepos()
  if type(channel) ~= "number" or channel <= 0 or mouse.screenrow ~= 1 or mouse.screencol < 1 then
    return
  end
  vim.rpcnotify(channel, "neovide.window.start_drag", {
    version = 1, row = 0, column = mouse.screencol - 1,
  })
end

function M.attach()
  if vim.g.neovide_window_drag_supported and vim.o.tabline == original then
    -- A later custom tabline belongs to its owner; never wrap it implicitly.
    vim.o.tabline = wrapped
  end
end

function M.setup()
  if not vim.g.neovide then return end
  _G.GlowWindowDrag = M.click
  local group = vim.api.nvim_create_augroup("GlowWindowDrag", { clear = true })
  vim.api.nvim_create_autocmd({ "VimEnter", "OptionSet" }, {
    group = group,
    pattern = { "*" },
    callback = function(event)
      if event.event == "VimEnter" or event.match == "tabline" then M.attach() end
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group, pattern = "NeovideWindowDragReady", callback = M.attach,
  })
  vim.schedule(M.attach)
end

return M
