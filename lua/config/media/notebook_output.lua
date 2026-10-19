-- Reuse Molten's output buffer and image window; only its focused view scrolls.
local M = {}
local api = vim.api
local namespace = api.nvim_create_namespace("glow.notebook.output-view")
local wheel_keys = {}
for _, direction in ipairs({ "Up", "Down", "Left", "Right" }) do
  wheel_keys[#wheel_keys + 1] = api.nvim_replace_termcodes("<ScrollWheel" .. direction .. ">", true, false, true)
end
local function wheel_key(key)
  -- Modifiers may precede the mouse key. Match its encoded suffix, not a
  -- printable key name or a user mapping, and never consume/replace the input.
  for _, value in ipairs(wheel_keys) do
    if key and key:sub(-#value) == value then return true end
  end
  return false
end

local function selected_output(win, buf)
  local row = api.nvim_win_get_cursor(win)[1]
  local selected, cell
  for index, item in ipairs(require("config.media.notebook_edit").cells(buf)) do
    if row >= math.max(1, item.header) then selected, cell = index, item else break end
  end
  local chunks, body = nil, "MoltenVirtualText"
  if cell then
    for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
      if mark[2] + 1 >= math.max(1, cell.header) and mark[2] + 1 <= cell.finish then
        for _, line in ipairs(mark[4].virt_lines or {}) do
          local text = {}
          for _, chunk in ipairs(line) do
            text[#text + 1] = chunk[1]
            if chunk[2] == "GlowNotebookOutputError" then body = chunk[2] end
          end
          local joined = table.concat(text)
          if joined:match("^Out%[") or joined:match("^%[OLD%] Out%[") then chunks = line end
        end
      end
    end
  end
  local ui = package.loaded["config.media.notebook_ui"]
  local geometry = ui and ui.output_frame_geometry and ui.output_frame_geometry(win, buf, selected)
  return { geometry = geometry, header = chunks, body = body }
end

local function highlight(buf, style)
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  local body = style.body
  if (lines[1] or ""):find("✗ Failed", 1, true) then body = "GlowNotebookOutputError" end
  -- Float text retains Molten's complete original lines. Reuse exactly the
  -- inline semantic groups instead of inheriting its unrelated popup defaults.
  if #lines > 1 then
    api.nvim_buf_set_extmark(buf, namespace, 1, 0, {
      end_row = #lines, end_col = 0, hl_group = body, priority = 200, strict = false,
    })
  end
  local header, text = style.header or {}, {}
  for _, chunk in ipairs(header) do text[#text + 1] = chunk[1] end
  if table.concat(text) ~= lines[1] then
    local old, number, tail = (lines[1] or ""):match("^(.-)(Out%[[^%]]*%]:)(.*)$")
    header = old and { { old, "MoltenVirtualText" }, { number, "GlowNotebookOutputNumber" } }
      or { { lines[1] or "", "MoltenVirtualText" } }
    if tail then
      local statuses = { { "✗ Failed", "GlowNotebookOutputFailure" }, { "✓ Done", "GlowNotebookOutputSuccess" },
        { "... Running", "GlowNotebookOutputRunning" }, { "* On Hold", "GlowNotebookOutputPending" },
        { "Never Run", "GlowNotebookOutputPending" } }
      local leading, rest = tail:match("^(%s*)(.*)$")
      header[#header + 1] = { leading, "MoltenVirtualText" }
      local matched = false
      for _, status in ipairs(statuses) do
        if rest:sub(1, #status[1]) == status[1] then
          header[#header + 1] = { status[1], status[2] }
          header[#header + 1] = { rest:sub(#status[1] + 1), "MoltenVirtualText" }
          matched = true; break
        end
      end
      if not matched then header[#header + 1] = { rest, "MoltenVirtualText" } end
    end
  end
  local col = 0
  for _, chunk in ipairs(header) do
    if #chunk[1] > 0 then api.nvim_buf_set_extmark(buf, namespace, 0, col, {
      end_col = col + #chunk[1], hl_group = chunk[2] or "MoltenVirtualText", priority = 210,
    }) end
    col = col + #chunk[1]
  end
end

local function position(win, style)
  local geometry = style.geometry
  if not geometry then return true end
  local rect, clip = geometry.rect, geometry.clip
  local top, left = math.floor(rect.row), math.floor(rect.col)
  local bottom = math.floor(clip.row + clip.height)
  local width = math.ceil(rect.col + rect.width) - left
  -- One padding row plus at least one scrollable text row must remain below
  -- the original joint. Never move the viewer upward or keep stale large bounds.
  if bottom - top < 2 or width < 3 then
    return false, "窗口下方空间不足，请先向下滚动正文或增大窗口。"
  end
  local config = {
    relative = "editor", row = top, col = left, width = width - 1, height = bottom - top - 1,
    -- Invisible top/left padding places the first output line in its original
    -- inline row/column, while the native green outline retains fractional edges.
    border = { " ", " ", "", "", "", "", "", " " },
  }
  local previous = api.nvim_win_get_config(win)
  local function border_char(index)
    local value = type(previous.border) == "table" and previous.border[index]
    return type(value) == "table" and value[1] or value or ""
  end
  local padding = border_char(1) == " " and border_char(2) == " " and border_char(8) == " "
    and border_char(3) == "" and border_char(4) == "" and border_char(5) == ""
    and border_char(6) == "" and border_char(7) == ""
  if previous.relative ~= config.relative or previous.row ~= config.row or previous.col ~= config.col
    or previous.width ~= config.width or previous.height ~= config.height or not padding then
    api.nvim_win_set_config(win, config)
  end
  vim.w[win].glow_notebook_output_frame = {
    row = rect.row - top, col = rect.col - left, width = rect.width,
    height = bottom - rect.row - 0.12,
  }
  return true
end

function M.enter(open)
  local source = api.nvim_get_current_win()
  local source_buf = api.nvim_win_get_buf(source)
  local style = selected_output(source, source_buf)
  -- Upstream's open_then_enter opens on the first request and focuses on the
  -- second. Saved outputs already focus on their first request.
  for _ = 1, 2 do
    local ok, result = pcall(open)
    if not ok then return false, tostring(result) end
    if result == false then return false end
    if api.nvim_get_current_win() ~= source then break end
  end
  local win = api.nvim_get_current_win()
  local buf = api.nvim_win_get_buf(win)
  if win == source or api.nvim_win_get_config(win).relative == ""
    or vim.bo[buf].filetype ~= "molten_output" then return false end

  -- Keep the inline output's wrapping untouched. Molten retains the original
  -- long lines in its popup buffer, so nowrap exposes horizontal scrolling.
  vim.wo[win].wrap = false
  vim.wo[win].linebreak = false
  vim.wo[win].scrolloff = 0
  vim.wo[win].sidescrolloff = 0
  vim.wo[win].number, vim.wo[win].relativenumber = false, false
  vim.wo[win].signcolumn, vim.wo[win].foldcolumn = "no", "0"
  vim.wo[win].winhighlight = "Normal:MoltenVirtualText,NormalNC:MoltenVirtualText"
  local fits, position_error = position(win, style)
  if not fits then
    if api.nvim_win_is_valid(source) then api.nvim_set_current_win(source) end
    if api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end
    return false, position_error
  end
  highlight(buf, style)
  local modifiable, readonly = vim.bo[buf].modifiable, vim.bo[buf].readonly
  vim.bo[buf].modifiable, vim.bo[buf].readonly = false, true
  local group = api.nvim_create_augroup("GlowNotebookOutputView" .. win, { clear = true })
  local wheel_namespace = api.nvim_create_namespace("glow.notebook.output-wheel." .. win)
  local function restore()
    vim.on_key(nil, wheel_namespace)
    if api.nvim_buf_is_valid(buf) then
      vim.bo[buf].modifiable, vim.bo[buf].readonly = modifiable, readonly
    end
    pcall(api.nvim_del_augroup_by_id, group)
  end
  local function map(keys, action, description)
    vim.keymap.set("n", keys, action, { buffer = buf, silent = true, desc = description })
  end
  -- j/k, Ctrl+d/u, Ctrl+f/b and the vertical wheel keep Neovim's scrolling.
  for _, keys in ipairs({ "h", "<Left>" }) do map(keys, "zh", "输出向左滚动") end
  for _, keys in ipairs({ "l", "<Right>" }) do map(keys, "zl", "输出向右滚动") end
  map("<ScrollWheelLeft>", "3zh", "输出向左滚动")
  map("<ScrollWheelRight>", "3zl", "输出向右滚动")
  map("<leader>y", '"+yy', "复制输出当前行到系统剪贴板")
  vim.keymap.set("x", "<leader>y", '"+y', { buffer = buf, silent = true, desc = "复制选中输出到系统剪贴板" })
  local function close(return_to_source)
    if not api.nvim_win_is_valid(win) then return end
    restore()
    if return_to_source and api.nvim_win_is_valid(source) then api.nvim_set_current_win(source) end
    -- Normal window events let Molten and its image provider release their
    -- existing popup normally; source cells, inline marks and kernels persist.
    if api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end
  end
  map("q", function() close(true) end, "关闭输出并返回 Notebook")
  map("<Esc>", function() close(true) end, "关闭输出并返回 Notebook")
  local wheel_pending = false
  vim.on_key(function(key, typed)
    if wheel_pending or not (wheel_key(key) or wheel_key(typed)) then return end
    -- Mouse position is already updated here, before the wheel is dispatched.
    -- Capture this event's target now; closing on the next turn lets the exact
    -- original scroll continue in that target, without changing its focus.
    local mouse = vim.fn.getmousepos()
    if mouse.winid == win or mouse.screenrow <= 0 or mouse.screencol <= 0 then return end
    wheel_pending = true
    vim.schedule(function()
      if api.nvim_win_is_valid(win) then close(false) end
    end)
  end, wheel_namespace)
  api.nvim_create_autocmd("WinLeave", { group = group, callback = function()
    if api.nvim_get_current_win() ~= win then return end
    -- Let the original mouse click/normal window switch select its target.
    -- Closing later must not redirect that click back to the Notebook source.
    vim.schedule(function()
      if api.nvim_win_is_valid(win) and api.nvim_get_current_win() ~= win then close(false) end
    end)
  end })
  api.nvim_create_autocmd("WinClosed", { group = group, pattern = tostring(win), once = true, callback = restore })
  local resize_pending = false
  api.nvim_create_autocmd({ "VimResized", "WinResized" }, { group = group, callback = function()
    if resize_pending then return end
    resize_pending = true
    vim.schedule(function()
      resize_pending = false
      if not api.nvim_win_is_valid(win) or not api.nvim_win_is_valid(source)
        or api.nvim_win_get_buf(source) ~= source_buf then return end
      local view = api.nvim_win_call(win, vim.fn.winsaveview)
      local fits, position_error = position(win, selected_output(source, source_buf))
      if not fits then
        close(true)
        vim.notify(position_error, vim.log.levels.WARN, { title = "Notebook" })
        return
      end
      api.nvim_win_call(win, function() vim.fn.winrestview(view) end)
      local ui = package.loaded["config.media.notebook_ui"]
      if ui and ui.refresh then ui.refresh() end
    end)
  end })
  local ui = package.loaded["config.media.notebook_ui"]
  if ui and ui.refresh then ui.refresh() end
  return true
end

return M
