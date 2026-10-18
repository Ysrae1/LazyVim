-- Leader+m enters point editing; Command+drag adds independent text selections.
-- Keep the adapter here rather than modifying the installed plugin.
local M = {}
local api = vim.api
local main_ns = api.nvim_create_namespace("multicursorsmaincursor")
local other_ns = api.nvim_create_namespace("multicursors")
local owner, anchor
local point_history = {}

local function editable(win)
  return api.nvim_win_is_valid(win)
    and vim.bo[api.nvim_win_get_buf(win)].buftype == ""
    and vim.bo[api.nvim_win_get_buf(win)].modifiable
end

local function point(win, row, col)
  api.nvim_win_set_cursor(win, { row, col })
  local cursor = api.nvim_win_get_cursor(win)
  local text = api.nvim_buf_get_lines(api.nvim_win_get_buf(win), cursor[1] - 1, cursor[1], false)[1]
  -- Neovim columns are bytes. Highlight the entire UTF-8 character, including at column zero.
  local char = vim.fn.matchstr(text:sub(cursor[2] + 1), "^.")
  return { row = cursor[1] - 1, col = cursor[2], end_row = cursor[1] - 1, end_col = cursor[2] + #char }
end

local function mouse_point()
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 or pos.line == 0 or pos.column == 0 or not editable(pos.winid) then
    return
  end
  api.nvim_set_current_win(pos.winid)
  return point(pos.winid, pos.line, pos.column - 1)
end

local function main()
  local mark = api.nvim_buf_get_extmarks(0, main_ns, 0, -1, { details = true })[1]
  if mark then
    return { row = mark[2], col = mark[3], end_row = mark[4].end_row, end_col = mark[4].end_col }, mark[1]
  end
end

local function same(a, b)
  return a.row == b.row and a.col == b.col and a.end_row == b.end_row and a.end_col == b.end_col
end

local function before(row, col, other_row, other_col)
  return row < other_row or (row == other_row and col < other_col)
end

local function set(ns, selection, id)
  return api.nvim_buf_set_extmark(0, ns, selection.row, selection.col, {
    id = id,
    end_row = selection.end_row,
    end_col = selection.end_col,
    hl_group = ns == main_ns and "MultiCursorMain" or "MultiCursor",
  })
end

local function select(selection, append)
  local old, id = main()
  if old and append and not same(old, selection) then
    set(other_ns, old)
  end
  -- The plugin's range deletion includes adjacent marks; use exact range equality instead.
  for _, mark in ipairs(api.nvim_buf_get_extmarks(0, other_ns, 0, -1, { details = true })) do
    if same(selection, { row = mark[2], col = mark[3], end_row = mark[4].end_row, end_col = mark[4].end_col }) then
      api.nvim_buf_del_extmark(0, other_ns, mark[1])
    end
  end
  -- Merge actual overlaps, while retaining adjacent independent points.
  local merged = true
  while merged do
    merged = false
    for _, mark in ipairs(api.nvim_buf_get_extmarks(0, other_ns, 0, -1, { details = true })) do
      local finish = mark[4]
      if before(selection.row, selection.col, finish.end_row, finish.end_col)
        and before(mark[2], mark[3], selection.end_row, selection.end_col) then
        if before(mark[2], mark[3], selection.row, selection.col) then
          selection.row, selection.col = mark[2], mark[3]
        end
        if before(selection.end_row, selection.end_col, finish.end_row, finish.end_col) then
          selection.end_row, selection.end_col = finish.end_row, finish.end_col
        end
        api.nvim_buf_del_extmark(0, other_ns, mark[1])
        merged = true
      end
    end
  end
  set(main_ns, selection, id)
  owner = api.nvim_get_current_buf()
  vim.b.MultiCursorPattern = ""
  require("multicursors.layers").normal_hydra:activate()
end

local function snapshot()
  local state = {
    buf = api.nvim_get_current_buf(), tick = api.nvim_buf_get_changedtick(0),
    main = main(), others = {},
    pattern = vim.b.MultiCursorPattern, multiline = vim.b.MultiCursorMultiline,
    anchor_start = vim.b.MultiCursorAnchorStart,
  }
  for _, mark in ipairs(api.nvim_buf_get_extmarks(0, other_ns, 0, -1, { details = true })) do
    state.others[#state.others + 1] = {
      row = mark[2], col = mark[3], end_row = mark[4].end_row, end_col = mark[4].end_col,
    }
  end
  return state
end

local function point_count(state)
  return #state.others + (state.main and 1 or 0)
end

function M.start()
  if not editable(api.nvim_get_current_win()) then
    return
  end
  local previous = snapshot()
  local last = point_history[#point_history]
  if point_count(previous) == 0 or (last and (last.buf ~= previous.buf or last.tick ~= previous.tick)) then
    point_history = {}
  end
  anchor = nil
  local cursor = api.nvim_win_get_cursor(0)
  select(point(api.nvim_get_current_win(), cursor[1], cursor[2]), true)
  local count = point_count(snapshot())
  if count > point_count(previous) then
    previous.after_count = count
    point_history[#point_history + 1] = previous
  end
end

function M.visual()
  point_history = {}
  local win = api.nvim_get_current_win()
  if not editable(win) then
    return
  end
  local mode = vim.fn.mode()
  local cursor, origin = api.nvim_win_get_cursor(win), vim.fn.getpos("v")
  local first = point(win, origin[2], origin[3] - 1)
  local last = point(win, cursor[1], cursor[2])
  if before(last.row, last.col, first.row, first.col) then
    first, last = last, first
  end
  if mode == "V" then
    first.col = 0
    last.end_col = #api.nvim_buf_get_lines(0, last.end_row, last.end_row + 1, false)[1]
  end
  vim.cmd("normal! " .. api.nvim_replace_termcodes("<Esc>", true, false, true))
  select({ row = first.row, col = first.col, end_row = last.end_row, end_col = last.end_col }, true)
end

function M.click()
  point_history = {}
  anchor = nil
  local selection = mouse_point()
  if selection then
    select(selection, true)
  end
end

function M.press()
  point_history = {}
  -- Preserve an existing Visual selection before beginning the next Command drag.
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" then
    M.visual()
  end
  local selection = mouse_point()
  if selection then
    local previous = {}
    for _, ns in ipairs({ main_ns, other_ns }) do
      for _, mark in ipairs(api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
        previous[#previous + 1] = { row = mark[2], col = mark[3], end_row = mark[4].end_row, end_col = mark[4].end_col }
      end
    end
    anchor = { buf = api.nvim_get_current_buf(), selection = vim.deepcopy(selection), previous = previous }
    select(selection, true)
  end
end

function M.drag()
  if not anchor or not main() or api.nvim_get_current_buf() ~= anchor.buf then
    return
  end
  local selection = mouse_point()
  if not selection or api.nvim_get_current_buf() ~= anchor.buf then
    return
  end
  local first, last = anchor.selection, selection
  if first.row > last.row or (first.row == last.row and first.col > last.col) then
    first, last = last, first
  end
  -- Rebuild from the selections that existed before this drag. An overlapping press
  -- may have merged with the old main range; shrinking the drag must not erase it.
  api.nvim_buf_clear_namespace(0, main_ns, 0, -1)
  api.nvim_buf_clear_namespace(0, other_ns, 0, -1)
  for _, previous in ipairs(anchor.previous) do
    set(other_ns, previous)
  end
  select({ row = first.row, col = first.col, end_row = last.end_row, end_col = last.end_col }, false)
end

function M.release()
  M.drag()
  anchor = nil
end

local function leave()
  local layers = require("multicursors.layers")
  local was_insert = false
  for _, name in ipairs({ "normal_hydra", "insert_hydra", "extend_hydra" }) do
    local hydra = layers[name]
    if hydra and hydra.layer and hydra.layer.active then
      was_insert = name == "insert_hydra"
      -- Sublayers normally schedule a return to Normal. Suppress that return on buffer leave,
      -- but retain Hydra's own hint/keymap cleanup callbacks.
      local callbacks = hydra.layer.config.on_exit
      local cleanup = {}
      for _, callback in pairs(callbacks or {}) do
        if callback ~= hydra.config.on_exit then
          cleanup[#cleanup + 1] = callback
        end
      end
      hydra.layer.config.on_exit = cleanup
      hydra.layer:exit()
      hydra.layer.config.on_exit = callbacks
    end
  end
  if was_insert then
    local insert = require("multicursors.insert_mode")
    insert._insert_and_clear()
    api.nvim_clear_autocmds({ group = insert._au_group })
    vim.opt.updatetime = insert._user_update_time
  end
  require("multicursors.utils").exit()
  owner, anchor = nil, nil
  point_history = {}
end

function M.undo_point()
  local previous = point_history[#point_history]
  if not previous then
    return
  end
  -- A selection undo never applies old coordinates after a text edit or a new session.
  if previous.buf ~= api.nvim_get_current_buf() or previous.tick ~= api.nvim_buf_get_changedtick(0)
    or previous.after_count ~= point_count(snapshot()) then
    point_history = {}
    return
  end
  point_history[#point_history] = nil
  anchor = nil
  api.nvim_buf_clear_namespace(0, main_ns, 0, -1)
  api.nvim_buf_clear_namespace(0, other_ns, 0, -1)
  for _, selection in ipairs(previous.others) do
    set(other_ns, selection)
  end
  if previous.main then
    set(main_ns, previous.main)
  end
  owner = previous.buf
  vim.b.MultiCursorPattern = previous.pattern
  vim.b.MultiCursorMultiline = previous.multiline
  vim.b.MultiCursorAnchorStart = previous.anchor_start
  if point_count(previous) == 0 then
    leave()
  end
end

function M.setup()
  if point_count(snapshot()) > 0 then
    owner = api.nvim_get_current_buf()
  end
  local utils = require("multicursors.utils")
  if not utils._mouse_safe_extmarks then
    -- Upstream uses an inclusive query end, which removes adjacent cursors when
    -- insert mode reduces several selections to characters. Only remove true overlaps.
    utils.create_extmark = function(selection, namespace)
      if before(selection.end_row, selection.end_col, selection.row, selection.col) then
        selection.row, selection.end_row = selection.end_row, selection.row
        selection.col, selection.end_col = selection.end_col, selection.col
      end
      local ns = namespace == utils.namespace.Main and main_ns or other_ns
      for _, mark in ipairs(api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
        local other = { row = mark[2], col = mark[3], end_row = mark[4].end_row, end_col = mark[4].end_col }
        if mark[1] ~= selection.id and (same(selection, other)
          or (before(selection.row, selection.col, other.end_row, other.end_col)
            and before(other.row, other.col, selection.end_row, selection.end_col))) then
          api.nvim_buf_del_extmark(0, ns, mark[1])
        end
      end
      return set(ns, selection, selection.id)
    end
    utils._mouse_safe_extmarks = true
  end
  local insert = require("multicursors.insert_mode")
  if not insert._mouse_safe_exit then
    local original_exit = insert.exit
    insert.exit = function()
      -- Flush before upstream removes InsertLeave, including a fast type-then-Escape.
      insert._insert_and_clear()
      original_exit()
    end
    insert._mouse_safe_exit = true
  end
  api.nvim_create_autocmd({ "BufLeave", "FocusLost" }, {
    group = api.nvim_create_augroup("MulticursorMouse", { clear = true }),
    callback = function(event)
      if event.buf == owner then
        leave()
      end
    end,
  })
end

return M
