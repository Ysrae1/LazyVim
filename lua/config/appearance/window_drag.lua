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

local dashboard_mouse_desc = "Drag dashboard upper blank area"

local function header_top(buf, win)
  local namespace = vim.api.nvim_get_namespaces().snacks_dashboard
  if not namespace then return 2 end -- old first-row behavior without a header
  local top
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true })) do
    if mark[4].hl_group == "SnacksDashboardHeader" then
      local position = vim.fn.screenpos(win, mark[2] + 1, mark[3] + 1)
      if position.row > 0 then top = math.min(top or position.row, position.row) end
    end
  end
  return top or 2
end

function M.dashboard_click(buf)
  local mouse = vim.fn.getmousepos()
  local win = mouse.winid
  if not vim.g.neovide_window_drag_supported or vim.o.showtabline ~= 0
    or mouse.screenrow < 1 or mouse.screencol < 1
    or not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf
    or vim.api.nvim_win_get_config(win).relative ~= ""
    or vim.bo[buf].filetype ~= "snacks_dashboard" then return false end
  local extended = (tonumber(vim.g.neovide_window_drag_version) or 1) >= 2
  local limit = extended and header_top(buf, win) or 2
  if mouse.screenrow >= limit then return false end
  -- A whole empty painted row is required, so header text, other panes,
  -- floating components and the spaces inside their labels stay interactive.
  for col = 1, vim.o.columns do
    if vim.fn.screenstring(mouse.screenrow, col) ~= " " then return false end
  end
  if not extended then
    _G.GlowWindowDrag(0, 1, "l", "")
    return true
  end
  local channel = vim.g.neovide_channel_id
  if type(channel) ~= "number" or channel <= 0 then return false end
  vim.rpcnotify(channel, "neovide.window.start_drag", {
    version = 2, surface = "dashboard", row = mouse.screenrow - 1, column = mouse.screencol - 1,
  })
  return true
end

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
    if M.dashboard_click(buf) then return end
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
