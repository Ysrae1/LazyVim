-- Shared ownership for Notebook/image/native-media window bars. A preview
-- replacing another preview inherits the original local bar, not its controls.
local M = {}
local api = vim.api
local owners, leaving, configured, writing = {}, {}, false, false
local prefixes = { "%#GlowNotebookBar#", "%#GlowMediaBar#" }
local function local_bar(win)
  return api.nvim_get_option_value("winbar", { win = win, scope = "local" })
end
local function managed_bar(value)
  for _, prefix in ipairs(prefixes) do if value:sub(1, #prefix) == prefix then return true end end
  return false
end
function M.is_current(win, buf)
  return api.nvim_win_is_valid(win) and api.nvim_buf_is_valid(buf)
    and api.nvim_win_get_buf(win) == buf and api.nvim_win_get_config(win).relative == ""
end
local function managed_buffer(buf)
  local ft = vim.bo[buf].filetype
  if ft == "glow_image" then return type(vim.b[buf].glow_image_path) == "string" end
  if ft == "glow_pdf" or ft == "glow_web" or ft == "glow_audio" or ft == "glow_video" then return true end
  local editor = package.loaded["config.media.notebook_edit"]
  return editor and editor.supports(api.nvim_buf_get_name(buf)) and editor.status(buf) ~= nil
end
local function baseline(win, value)
  local seen = {}
  while managed_bar(value) do
    if seen[value] then return "" end
    seen[value] = true
    local saved = owners[win]
    if not saved or saved.rendered ~= value then
      saved = nil
      for _, owner in pairs(owners) do if owner.rendered == value then saved = owner; break end end
    end
    if not saved then return "" end
    value = saved.before
  end
  return value
end
local function write(win, value)
  writing = true
  local ok, err = pcall(api.nvim_set_option_value, "winbar", value, { win = win, scope = "local" })
  writing = false
  if not ok then error(err, 0) end
end
function M.capture(win)
  local current, saved = local_bar(win), owners[win]
  if current == "" and saved and not saved.retired then return saved.before end
  return baseline(win, current)
end
function M.set(win, buf, value, owner, before)
  if not M.is_current(win, buf) or not managed_buffer(buf) then return false end
  local current, saved = local_bar(win), owners[win]
  -- Neovim resets window-local options while entering a new buffer, after some
  -- BufWinEnter callbacks have already rendered its first title.
  if saved and not saved.retired and saved.owner == (owner or buf) and (saved.rendered == current or current == "") then
    before = saved.before
  elseif before == nil then
    local previous = leaving[win]
    before = current == "" and previous and previous.buf ~= buf and previous.before or baseline(win, current)
  else before = baseline(win, before) end
  leaving[win] = nil
  owners[win] = { owner = owner or buf, buf = buf, before = before, rendered = value }
  write(win, value)
  return true
end
function M.release(win, buf, owner)
  local saved = owners[win]
  if not saved or saved.buf ~= buf or saved.owner ~= (owner or buf) then return false end
  if api.nvim_win_is_valid(win) and not saved.retired then
    local current = local_bar(win)
    if current == saved.rendered or current == "" then write(win, baseline(win, saved.before)) end
  end
  saved.retired = true
  -- Keep only the last value until WinClosed to recognize inherited/legacy
  -- controls without growing a history of asynchronous status text.
  return true
end
function M.refresh()
  if writing then return end
  for win in pairs(owners) do if not api.nvim_win_is_valid(win) then owners[win] = nil end end
  for _, win in ipairs(api.nvim_list_wins()) do
    local buf, current, saved = api.nvim_win_get_buf(win), local_bar(win), owners[win]
    if saved and not saved.retired and (saved.buf ~= buf or not managed_buffer(buf)) then
      if current == saved.rendered or current == "" then write(win, baseline(win, saved.before)) end
      saved.retired = true
    elseif not saved and managed_bar(current) then
      local before = baseline(win, current)
      owners[win] = { buf = buf, before = before, rendered = current }
      if not managed_buffer(buf) then write(win, before) end
    end
    if not managed_buffer(buf) and managed_bar(local_bar(win)) then write(win, baseline(win, local_bar(win))) end
  end
end
function M.setup()
  if not configured then
    configured = true
    pcall(api.nvim_del_augroup_by_name, "GlowNotebookWinbar")
    local group = api.nvim_create_augroup("GlowMediaWinbar", { clear = true })
    api.nvim_create_autocmd("BufWinLeave", { group = group, callback = function(event)
      for _, win in ipairs(api.nvim_list_wins()) do
        if api.nvim_win_get_buf(win) == event.buf then leaving[win] = { buf = event.buf, before = M.capture(win) } end
      end
    end })
    api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "BufFilePost", "WinEnter", "WinNew", "BufDelete", "BufWipeout" }, {
      group = group, callback = function() M.refresh(); vim.schedule(M.refresh) end,
    })
    api.nvim_create_autocmd("OptionSet", { group = group, pattern = "winbar", callback = M.refresh })
    api.nvim_create_autocmd("WinClosed", { group = group, callback = function(event)
      local win = tonumber(event.match); owners[win], leaving[win] = nil, nil
    end })
  end
  M.refresh()
end
return M
