-- Adapted from neo-tree.nvim (MIT), pinned v3 help view; only display text and UTF-8 sizing differ.
local function T(text) return require("config.platform.locale").t(text) end
local Popup = require("nui.popup")
local NuiLine = require("nui.line")
local utils = require("neo-tree.utils")
local popups = require("neo-tree.ui.popups")
local highlights = require("neo-tree.ui.highlights")
local M = {}

-- Missing command labels in the pinned v3 sources. Keep this scoped to help:
-- IDs, resolved handlers, custom descriptions and the shared catalog are intact.
local command_labels = {
  clear_clipboard = "清空 NeoTree 文件剪贴板",
  toggle_auto_expand_width = "切换自动扩展窗口宽度",
  jump_to_symbol = "跳转到符号",
  git_undo_last_commit = "撤销最近一次提交（保留暂存更改）",
  filter = "即时筛选符号",
}

local function command_text(state, key, resolved)
  if require("config.platform.locale").current() ~= "zh" then return T(resolved.text) end
  local binding = state.window and state.window.mappings and state.window.mappings[key]
  local command = type(binding) == "table" and (binding.command or binding[1]) or binding
  local config = type(binding) == "table" and binding.config or nil
  if type(command) == "string" and resolved.text == command then
    if command == "scroll_preview" then
      -- Preview.scroll maps a negative direction to Ctrl-E (down), a positive
      -- direction to Ctrl-Y (up). Read config, not the default physical key.
      local direction = config and tonumber(config.direction)
      if direction and direction < 0 then return "向下滚动预览" end
      if direction and direction > 0 then return "向上滚动预览" end
      return "滚动预览"
    end
    return command_labels[command] or T(resolved.text)
  end
  if type(command) == "string" and resolved.text == "<invalid> (" .. command .. ")" then
    -- The pinned document_symbols source inherits clear_clipboard but exports
    -- no such command. Describe its existing no-op honestly; do not enable it.
    local label = command_labels[command] or T(command)
    return "不可用（" .. label .. "）"
  end
  return T(resolved.text)
end

---@param text string
---@param highlight string?
---@return NuiLine
local add_text = function(text, highlight)
  local line = NuiLine()
  line:append(text, highlight)
  return line
end

---@param state neotree.State
---@param prefix_key string?
local get_sub_keys = function(state, prefix_key)
  local keys = utils.get_keys(state.resolved_mappings)
  if not prefix_key then
    return keys
  end

  local len = prefix_key:len()
  local sub_keys = {}
  for _, key in ipairs(keys) do
    if #key > len and key:sub(1, len) == prefix_key then
      table.insert(sub_keys, key)
    end
  end
  return sub_keys
end

---@param key string
---@param prefix string?
local function key_minus_prefix(key, prefix)
  if prefix then
    return key:sub(prefix:len() + 1)
  else
    return key
  end
end

---@class neotree.Help.Mapping
---@field key string
---@field mapping neotree.State.ResolvedMapping

---@alias neotree.Help.Sorter fun(a: neotree.Help.Mapping, b: neotree.Help.Mapping):boolean

---@type neotree.Help.Sorter
local default_help_sort = function(a, b)
  return a.key < b.key
end

---Shows a help screen for the mapped commands when will execute those commands
---when the corresponding key is pressed.
---@param state neotree.State state of the source.
---@param title string? if this is a sub-menu for a multi-key mapping, the title for the window.
---@param prefix_key string? if this is a sub-menu, the start of tehe multi-key mapping
---@param sorter neotree.Help.Sorter?
M.show = function(state, title, prefix_key, sorter)
  local tree_width = vim.api.nvim_win_get_width(state.winid)
  local keys = get_sub_keys(state, prefix_key)

  local function render_lines()
    ---@type NuiLine[]
    local lines = { add_text("") }
    lines[1] = add_text(" " .. T("Press the corresponding key to execute the command."), "Comment")
    lines[2] = add_text(" " .. T("Press <Esc> to cancel."), "Comment")
    lines[3] = add_text("")
    local header = NuiLine()
    header:append(string.format(" %14s", T("KEY(S)")), highlights.ROOT_NAME)
    header:append("    ", highlights.DIM_TEXT)
    header:append(T("COMMAND ACTION"), highlights.ROOT_NAME)
    lines[4] = header
    local max_width = vim.fn.strdisplaywidth(lines[1]:content())
    ---@type neotree.Help.Mapping[]
    local maps = {}
    for _, key in ipairs(keys) do
      maps[#maps + 1] = {
        key = key,
        mapping = state.resolved_mappings[key]
          or { text = "<error mapping for key " .. key .. ">", handler = function() end },
      }
    end

    table.sort(maps, sorter or default_help_sort)
    for _, val in ipairs(maps) do
      local nuiline = NuiLine()
      nuiline:append(
        string.format(" %14s", key_minus_prefix(val.key, prefix_key)),
        highlights.FILTER_TERM
      )
      nuiline:append(" -> ", highlights.DIM_TEXT)
      nuiline:append(command_text(state, val.key, val.mapping), highlights.NORMAL)
      local line = nuiline:content()
      if vim.fn.strdisplaywidth(line) > max_width then
        max_width = vim.fn.strdisplaywidth(line)
      end
      lines[#lines + 1] = nuiline
    end

    return lines, math.min(60, max_width + 1)
  end
  local lines, width = render_lines()
  local col
  if state.current_position == "right" then
    col = vim.o.columns - tree_width - width - 1
  else
    col = tree_width - 1
  end

  ---@type nui_popup_options
  local options = {
    position = {
      row = 2,
      col = col,
    },
    size = {
      width = width,
      height = #keys + 5,
    },
    enter = true,
    focusable = true,
    zindex = 50,
    relative = "editor",
    win_options = {
      foldenable = false, -- Prevent folds from hiding lines
    },
  }

  ---@return integer lines The number of screen lines that the popup should occupy at most
  local popup_max_height = function()
    -- statusline
    local statusline_lines = 0
    local laststatus = vim.o.laststatus
    if laststatus ~= 0 then
      local windows = vim.api.nvim_tabpage_list_wins(0)
      if (laststatus == 1 and #windows > 1) or laststatus > 1 then
        statusline_lines = 1
      end
    end
    -- tabs
    local tab_lines = 0
    local showtabline = vim.o.showtabline
    if showtabline ~= 0 then
      local tabs = vim.api.nvim_list_tabpages()
      if (showtabline == 1 and #tabs > 1) or showtabline == 2 then
        tab_lines = 1
      end
    end
    return vim.o.lines - vim.o.cmdheight - statusline_lines - tab_lines - 2
  end
  local max_height = popup_max_height()
  if options.size.height > max_height then
    options.size.height = max_height
  end

  local title_source = title or "NeoTree Shortcuts"
  title = T(title_source)
  options = popups.popup_options(title, width, options)
  local popup = Popup(options)
  popup:mount()

  local event = require("nui.utils.autocmd").event
  popup:on({ event.VimResized }, function()
    popup:update_layout({
      size = {
        height = math.min(options.size.height --[[@as integer]], popup_max_height()),
        width = math.min(options.size.width --[[@as integer]], vim.o.columns - 2),
      },
    })
  end)
  popup:on({ event.BufLeave, event.BufDelete }, function()
    popup:unmount()
  end, { once = true })

  popup:map("n", "<esc>", function()
    popup:unmount()
  end, { noremap = true })

  for _, key in ipairs(keys) do
    -- map everything except for <escape>
    if string.match(key:lower(), "^<esc") == nil then
      local value = state.resolved_mappings[key]
        or { text = "<error mapping for key " .. key .. ">", handler = function() end }
      popup:map("n", key_minus_prefix(key, prefix_key), function()
        popup:unmount()
        vim.api.nvim_set_current_win(state.winid)
        value.handler()
      end)
    end
  end

  for i, line in ipairs(lines) do
    line:render(popup.bufnr, -1, i)
  end

  -- Refresh this display in place when ToggleLanguage fires. Existing handlers,
  -- source state, focus and the selected help row survive the language change.
  local refresh_id = vim.api.nvim_create_autocmd("User", {
    pattern = "GlowLanguageChanged",
    callback = function()
      if not popup.bufnr or not vim.api.nvim_buf_is_valid(popup.bufnr) then return true end
      local updated, updated_width = render_lines()
      local updated_title = popups.popup_options(T(title_source), updated_width).border.text
      popup.border:set_text("top", updated_title.top, updated_title.top_align)
      popup:update_layout({ size = { width = math.min(updated_width, vim.o.columns - 2),
        height = math.min(#keys + 5, popup_max_height()) } })
      for i, line in ipairs(updated) do line:render(popup.bufnr, -1, i) end
    end,
  })
  -- Nui removes its own buffer autocmd group before deleting its buffer, so
  -- use a buffer-scoped listener outside that group for reliable cleanup.
  vim.api.nvim_create_autocmd("BufWipeout", { buffer = popup.bufnr, once = true,
    callback = function() pcall(vim.api.nvim_del_autocmd, refresh_id) end })
end

return M
