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

local dashboard_mouse_desc = "Drag dashboard top blank row"

function M.attach_dashboard(buf)
  if not vim.g.neovide_window_drag_supported or not vim.api.nvim_buf_is_valid(buf)
    or vim.bo[buf].filetype ~= "snacks_dashboard" then return end
  local existing = vim.api.nvim_buf_call(buf, function()
    return vim.fn.maparg("<LeftMouse>", "n", false, true)
  end)
  -- Existing mouse actions belong to their provider, including blank padding
  -- within a custom button. Never replace a user's buffer or global mapping.
  if next(existing) then return end
  vim.keymap.set("n", "<LeftMouse>", function()
    local mouse = vim.fn.getmousepos()
    local win = mouse.winid
    if vim.g.neovide_window_drag_supported and vim.o.showtabline == 0
      and mouse.screenrow == 1 and mouse.screencol > 0
      and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf
      and vim.bo[buf].filetype == "snacks_dashboard"
      and vim.fn.screenstring(1, mouse.screencol) == " " then
      _G.GlowWindowDrag(0, 1, "l", "")
      return
    end
    -- Replaying the native key without mappings preserves ordinary clicks,
    -- selection and dashboard content without adding a visible tabline.
    local key = vim.api.nvim_replace_termcodes("<LeftMouse>", true, false, true)
    vim.api.nvim_feedkeys(key, "ni", false)
  end, { buffer = buf, silent = true, desc = dashboard_mouse_desc })
end

function M.attach()
  M.attach_dashboard(vim.api.nvim_get_current_buf())
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
    group = group, pattern = { "NeovideWindowDragReady", "SnacksDashboardOpened" }, callback = M.attach,
  })
  vim.schedule(M.attach)
end

return M
