local function T(text) return require("config.platform.locale").t(text) end
-- Saved output descriptors belong to original source spans, not current cell
-- ordinals. Molten's own renderer provides the text, popup and image layout.
local M = {}
local api = vim.api
local namespace = api.nvim_create_namespace("glow.notebook.saved-source")
local states = {}

local function available()
  return vim.fn.exists("*GlowNotebookSavedOutputs") == 1
    or vim.fn.exists("#FuncUndefined#GlowNotebookSavedOutputs") == 1
end

local function normalized(source)
  source = type(source) == "table" and table.concat(source) or (source or "")
  local lines = vim.split(source:gsub("\r\n", "\n"), "\n", { plain = true })
  while #lines > 0 and lines[1]:match("^%s*$") do table.remove(lines, 1) end
  while #lines > 0 and lines[#lines]:match("^%s*$") do table.remove(lines) end
  return table.concat(lines, "\n")
end

local function request(buf, action, ...)
  if not available() then return false end
  local args = { ... }
  local ok, result = pcall(function()
    -- nvim_buf_call restores the previous window, which would undo this
    -- deliberate focus transition into the saved output's Molten popup.
    if action == "enter" and api.nvim_get_current_buf() == buf then
      return vim.fn.GlowNotebookSavedOutputs(action, buf, unpack(args))
    end
    return api.nvim_buf_call(buf, function() return vim.fn.GlowNotebookSavedOutputs(action, buf, unpack(args)) end)
  end)
  if not ok then
    local state = states[buf]
    if state and not state.warned then
      state.warned = true
      vim.notify(T("Unable to read saved Notebook outputs: ") .. tostring(result), vim.log.levels.WARN)
    end
    return false
  end
  return result
end

local function matching(buf)
  local state, result = states[buf], {}
  if not state or state.live or not api.nvim_buf_is_loaded(buf) then return result end
  local edit = require("config.media.notebook_edit")
  local lines, cells = api.nvim_buf_get_lines(buf, 0, -1, false), edit.cells(buf)
  local anchored = {}
  for _, cell in ipairs(cells) do
    if cell.kind == "code" then anchored[edit.content_line(cell, #lines) - 1] = cell end
  end
  for _, record in ipairs(state.records) do
    local mark = api.nvim_buf_get_extmark_by_id(buf, namespace, record.mark, { details = true })
    if #mark > 0 and not mark[3].invalid then
      local cell = anchored[mark[1]]
      if cell and normalized(table.concat(vim.list_slice(lines, cell.first, cell.last), "\n")) == record.source then
        local anchor = edit.content_line(cell, #lines)
        result[#result + 1] = { key = record.key, row = math.max(anchor, cell.last) - 1, outputs = record.outputs,
          execution_count = record.execution_count, first = cell.first, last = cell.last }
      end
    end
  end
  return result
end

function M.refresh(buf)
  local state = states[buf]
  if not state or state.live or state.refreshing or not api.nvim_buf_is_loaded(buf) then return end
  state.queued, state.refreshing = false, true
  local cells, signature = matching(buf), {}
  local win = vim.fn.win_findbuf(buf)[1]
  signature[1] = win and api.nvim_win_get_width(win) or vim.o.columns
  for _, cell in ipairs(cells) do signature[#signature + 1] = cell.key .. ":" .. cell.row end
  signature = table.concat(signature, ",")
  if state.signature ~= signature then
    local pending = {}
    for _, cell in ipairs(cells) do
      if state.sent[cell.key] then cell.outputs, cell.execution_count = nil, nil
      else pending[#pending + 1] = cell.key end
      cell.first, cell.last = nil, nil
    end
    if request(buf, "render", cells) ~= false then
      for _, key in ipairs(pending) do state.sent[key] = true end
      state.signature = signature
    end
  end
  state.refreshing = false
end

local function schedule(buf)
  local state = states[buf]
  if not state or state.live or state.queued then return end
  state.queued = true
  vim.schedule(function() M.refresh(buf) end)
end

function M.clear(buf, live)
  local state = states[buf]
  if not state then return end
  state.live = live == true
  request(buf, "clear")
end

function M.detach(buf)
  if not states[buf] then return end
  M.clear(buf)
  states[buf] = nil
end

function M.attach(buf, path, reload)
  if states[buf] and not reload then schedule(buf); return end
  if states[buf] then M.detach(buf) end
  if not available() then return end
  local ok, document = pcall(require("config.media.runtime").read_notebook, path)
  if not ok then return end
  api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  local state = { records = {}, sent = {} }
  states[buf] = state
  local code = {}
  for _, cell in ipairs(document.cells) do if cell.cell_type == "code" then code[#code + 1] = cell end end
  local lines, index = api.nvim_buf_get_lines(buf, 0, -1, false), 0
  for _, cell in ipairs(require("config.media.notebook_edit").cells(buf)) do
    if cell.kind == "code" then
      index = index + 1
      local saved = code[index]
      local anchor = require("config.media.notebook_edit").content_line(cell, #lines)
      local last = math.max(anchor, cell.last)
      if saved and #(saved.outputs or {}) > 0
        and normalized(saved.source) == normalized(table.concat(vim.list_slice(lines, cell.first, cell.last), "\n")) then
        state.records[#state.records + 1] = { key = index, source = normalized(saved.source), outputs = saved.outputs,
          execution_count = saved.execution_count or vim.NIL,
          mark = api.nvim_buf_set_extmark(buf, namespace, anchor - 1, 0, { end_row = last - 1,
            end_col = #(lines[last] or ""), right_gravity = true, end_right_gravity = false,
            invalidate = true, undo_restore = true }) }
      end
    end
  end
  api.nvim_buf_attach(buf, false, {
    on_lines = function() if states[buf] == state then schedule(buf) end end,
    on_detach = function() if states[buf] == state then states[buf] = nil end end,
  })
  schedule(buf)
end

function M.enter(buf)
  local row = api.nvim_win_get_cursor(0)[1]
  for _, cell in ipairs(matching(buf)) do
    if row >= cell.first and row <= cell.last then
      return request(buf, "enter", cell.key, cell.row)
    end
  end
  return false
end

function M.setup()
  local group = api.nvim_create_augroup("GlowNotebookSavedOutputs", { clear = true })
  api.nvim_create_autocmd({ "BufWinEnter", "WinResized", "VimResized" }, { group = group, callback = function()
    local buf = api.nvim_get_current_buf()
    if states[buf] then schedule(buf) end
  end })
end

return M
