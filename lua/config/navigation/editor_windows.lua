-- Editor-pane operations. No mappings, autocommands or layout changes on load.
-- win_splitmove preserves the moved window ID; native H/L/K/J target the full
-- tabpage and therefore must not be used to move panes around fixed sidebars.
local M = {}
local api = vim.api
local directions = { left = "h", down = "j", up = "k", right = "l", h = "h", j = "j", k = "k", l = "l" }

function M.is_editor(win)
  if not api.nvim_win_is_valid(win) then return false end
  local config = api.nvim_win_get_config(win)
  if config.relative ~= "" or config.external then return false end
  local explicit = vim.w[win].glow_editor_window
  if type(explicit) == "boolean" then return explicit end
  local buf = api.nvim_win_get_buf(win)
  local ft, bt = vim.bo[buf].filetype:lower(), vim.bo[buf].buftype
  if ft:match("^neo%-tree") or ft:match("^avante") or ft:match("^snacks_")
    or ft:match("^trouble") or ft == "qf" or ft == "help" then return false end
  return bt == "" or bt == "acwrite"
end

function M.list()
  local result = {}
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if M.is_editor(win) then result[#result + 1] = win end
  end
  table.sort(result, function(a, b)
    local aa, bb = api.nvim_win_get_position(a), api.nvim_win_get_position(b)
    return aa[1] == bb[1] and aa[2] < bb[2] or aa[1] < bb[1]
  end)
  return result
end

local function snapshot(win)
  return { win = win, buf = api.nvim_win_get_buf(win), width = api.nvim_win_get_width(win),
    height = api.nvim_win_get_height(win), view = api.nvim_win_call(win, vim.fn.winsaveview),
    fixed_width = vim.wo[win].winfixwidth, fixed_height = vim.wo[win].winfixheight }
end

local function restore_view(item, win)
  win = win or item.win
  if api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == item.buf then
    api.nvim_win_call(win, function() vim.fn.winrestview(item.view) end)
  end
end

local function protected(operation, rollback_buffers)
  local current, equalalways = api.nvim_get_current_win(), vim.o.equalalways
  local states, auxiliary = {}, {}
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    local item = snapshot(win)
    states[#states + 1] = item
    local config = api.nvim_win_get_config(win)
    if config.relative == "" and not config.external and not M.is_editor(win) then
      auxiliary[#auxiliary + 1] = item
      vim.wo[win].winfixwidth, vim.wo[win].winfixheight = true, true
    end
  end
  vim.o.equalalways = false
  local result = vim.F.pack_len(pcall(operation))
  if not result[1] and rollback_buffers then
    for _, item in ipairs(states) do
      if api.nvim_win_is_valid(item.win) and M.is_editor(item.win) and api.nvim_buf_is_valid(item.buf)
        and api.nvim_win_get_buf(item.win) ~= item.buf then pcall(api.nvim_win_set_buf, item.win, item.buf) end
    end
  end
  -- Keep plugin sidebars in their existing split frames, with their own sizes
  -- and fix flags. Never close/recreate them or change their buffers.
  for _, item in ipairs(auxiliary) do
    if api.nvim_win_is_valid(item.win) then
      if api.nvim_win_get_width(item.win) ~= item.width then pcall(api.nvim_win_set_width, item.win, item.width) end
      if api.nvim_win_get_height(item.win) ~= item.height then pcall(api.nvim_win_set_height, item.win, item.height) end
      vim.wo[item.win].winfixwidth, vim.wo[item.win].winfixheight = item.fixed_width, item.fixed_height
    end
  end
  for _, item in ipairs(states) do restore_view(item) end
  vim.o.equalalways = equalalways
  if api.nvim_win_is_valid(current) then api.nvim_set_current_win(current) end
  if not result[1] then return false, tostring(result[2]) end
  return unpack(result, 2, result.n)
end

local function target(direction, fallback)
  local current = api.nvim_get_current_win()
  local pos = api.nvim_win_get_position(current)
  local y, x = pos[1] + api.nvim_win_get_height(current) / 2, pos[2] + api.nvim_win_get_width(current) / 2
  local best, score, nearest, distance
  for _, win in ipairs(M.list()) do
    if win ~= current then
      local p = api.nvim_win_get_position(win)
      local dy, dx = p[1] + api.nvim_win_get_height(win) / 2 - y, p[2] + api.nvim_win_get_width(win) / 2 - x
      local d = math.abs(dx) + math.abs(dy)
      if not distance or d < distance then nearest, distance = win, d end
      local primary = direction == "h" and -dx or direction == "l" and dx or direction == "k" and -dy or dy
      local secondary = (direction == "h" or direction == "l") and math.abs(dy) or math.abs(dx)
      local value = primary * 10000 + secondary
      if primary > 0 and (not score or value < score) then best, score = win, value end
    end
  end
  return best or fallback and nearest or nil
end

-- Move next to the closest editor in that direction. With a perpendicular
-- layout, use the nearest editor to form a new row/column inside the editor
-- area, rather than moving to the full tabpage's outer edge.
function M.move(direction)
  local axis = directions[direction]
  if not axis then return false, "Invalid editor direction" end
  local current = api.nvim_get_current_win()
  if not M.is_editor(current) then return false, "Current window is auxiliary" end
  local destination = target(axis, true)
  if not destination then return false, "No other editor window" end
  return protected(function()
    if vim.fn.win_splitmove(current, destination, {
      vertical = axis == "h" or axis == "l", rightbelow = axis == "j" or axis == "l",
    }) ~= 0 then return false, "Editor window move failed" end
    return true
  end)
end

local function place(item, win)
  api.nvim_win_set_buf(win, item.buf)
  restore_view(item, win)
end

-- Exchange pane contents together with their cursor/scroll view. Window-local
-- chrome and sidebars stay in place; no plugin pane becomes an exchange target.
function M.swap(direction)
  local current = api.nvim_get_current_win()
  if not M.is_editor(current) then return false, "Current window is auxiliary" end
  local destination
  if type(direction) == "number" then destination = direction
  elseif direction then
    local axis = directions[direction]
    if not axis then return false, "Invalid editor direction" end
    destination = target(axis, false)
  else
    local wins = M.list()
    for index, win in ipairs(wins) do
      if win == current then destination = wins[index % #wins + 1] end
    end
  end
  if not destination or destination == current or not M.is_editor(destination)
    or api.nvim_win_get_tabpage(destination) ~= api.nvim_get_current_tabpage() then return false, "No editor exchange target" end
  if vim.wo[current].winfixbuf or vim.wo[destination].winfixbuf then return false, "Editor buffer is fixed" end
  local first, second = snapshot(current), snapshot(destination)
  -- Buffer assignment must not trigger bufhidden=wipe/delete/unload semantics
  -- or abandon unsaved buffers when 'hidden' is disabled.
  for _, item in ipairs({ first, second }) do
    local hidden = vim.bo[item.buf].bufhidden
    if hidden == "wipe" or hidden == "delete" or hidden == "unload" then return false, "Editor buffer has destructive bufhidden" end
    if not vim.o.hidden and vim.bo[item.buf].modified then return false, "Unsaved editor buffer requires hidden" end
  end
  local ok, reason = protected(function()
    place(second, current)
    place(first, destination)
    return true
  end, true)
  if ok then restore_view(second, current); restore_view(first, destination) end
  return ok, reason
end

function M.rotate(reverse)
  local wins, items = M.list(), {}
  if not M.is_editor(api.nvim_get_current_win()) then return false, "Current window is auxiliary" end
  if #wins < 2 then return false, "No other editor window" end
  for index, win in ipairs(wins) do
    items[index] = snapshot(win)
    local hidden = vim.bo[items[index].buf].bufhidden
    if vim.wo[win].winfixbuf or hidden == "wipe" or hidden == "delete" or hidden == "unload"
      or not vim.o.hidden and vim.bo[items[index].buf].modified then return false, "Editor buffer cannot be reassigned safely" end
  end
  local offset = reverse and 1 or -1
  local ok, reason = protected(function()
    for index, win in ipairs(wins) do place(items[(index - 1 + offset) % #wins + 1], win) end
    return true
  end, true)
  if ok then
    for index, win in ipairs(wins) do restore_view(items[(index - 1 + offset) % #wins + 1], win) end
  end
  return ok, reason
end

function M.equalize()
  if not M.is_editor(api.nvim_get_current_win()) then return false, "Current window is auxiliary" end
  if #M.list() < 2 then return false, "No other editor window" end
  return protected(function() vim.cmd("wincmd ="); return true end)
end

function M.close_others()
  local current = api.nvim_get_current_win()
  if not M.is_editor(current) then return false, "Current window is auxiliary" end
  local wins = M.list()
  for _, win in ipairs(wins) do
    local buf = api.nvim_win_get_buf(win)
    if win ~= current and vim.bo[buf].modified and (not vim.o.hidden or vim.bo[buf].bufhidden ~= "") then
      return false, "Keep unsaved editor buffers before closing other windows"
    end
  end
  return protected(function()
    for _, win in ipairs(wins) do if win ~= current then api.nvim_win_close(win, false) end end
    return true
  end)
end

-- Focus navigation deliberately retains access to the tree/AI panes.
function M.focus(direction)
  local axis = directions[direction]
  if not axis then return false, "Invalid window direction" end
  vim.cmd("wincmd " .. axis)
  return true
end

return M
