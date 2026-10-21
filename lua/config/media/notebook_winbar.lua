-- winbar belongs to a window, while Notebook sessions belong to buffers.
-- Keep their lifetimes separate: hiding a Notebook never stops its kernel.
local M = {}
local api = vim.api
local owners, configured, writing = {}, false, false
local prefix = "%#GlowNotebookBar#"

local function local_bar(win)
  return api.nvim_get_option_value("winbar", { win = win, scope = "local" })
end

local function notebook_bar(value)
  return type(value) == "string" and value:sub(1, #prefix) == prefix
end

local function notebook_window(win)
  if not api.nvim_win_is_valid(win) or api.nvim_win_get_config(win).relative ~= "" then return false end
  local buf = api.nvim_win_get_buf(win)
  local editor = package.loaded["config.media.notebook_edit"]
  return editor and editor.supports(api.nvim_buf_get_name(buf)) and editor.status(buf) ~= nil
end

local function inherited_before(win, value)
  local saved = owners[win]
  if saved and saved.rendered == value then return saved.before end
  -- :split can copy a literal Notebook bar before the new window has an owner.
  for _, owner in pairs(owners) do
    if owner.rendered == value then return owner.before end
  end
  return ""
end

local function write(win, value)
  writing = true
  local ok, err = pcall(api.nvim_set_option_value, "winbar", value, { win = win, scope = "local" })
  writing = false
  if not ok then error(err, 0) end
end

function M.set(win, buf, value)
  if not notebook_window(win) or api.nvim_win_get_buf(win) ~= buf then return end
  local current, saved = local_bar(win), owners[win]
  local before = saved and saved.rendered == current and saved.before
    or (notebook_bar(current) and inherited_before(win, current) or current)
  owners[win] = { buf = buf, before = before, rendered = value }
  write(win, value)
end

function M.refresh()
  if writing then return end
  for win in pairs(owners) do if not api.nvim_win_is_valid(win) then owners[win] = nil end end
  for _, win in ipairs(api.nvim_list_wins()) do
    local current, saved = local_bar(win), owners[win]
    if notebook_window(win) then
      if notebook_bar(current) and (not saved or saved.rendered ~= current) then
        owners[win] = { buf = api.nvim_win_get_buf(win), before = inherited_before(win, current), rendered = current }
      end
    elseif saved and saved.rendered == current then
      write(win, saved.before)
      -- Retain this record until WinClosed: a media preview may later restore
      -- the literal Notebook bar it saved before changing the window's buffer.
    elseif notebook_bar(current) then
      local before = inherited_before(win, current)
      owners[win] = { buf = api.nvim_win_get_buf(win), before = before, rendered = current }
      write(win, before)
    end
    -- An unrelated custom/media bar is never replaced during cleanup.
  end
end

function M.setup()
  if not configured then
    configured = true
    local group = api.nvim_create_augroup("GlowNotebookWinbar", { clear = true })
    api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "BufFilePost", "WinEnter", "WinNew", "BufDelete", "BufWipeout" }, {
      group = group, callback = function()
        M.refresh()
        -- Run after other components finish restoring their saved options.
        vim.schedule(M.refresh)
      end,
    })
    api.nvim_create_autocmd("OptionSet", { group = group, pattern = "winbar", callback = M.refresh })
    api.nvim_create_autocmd("WinClosed", { group = group, callback = function(event) owners[tonumber(event.match)] = nil end })
  end
  M.refresh()
end

return M
