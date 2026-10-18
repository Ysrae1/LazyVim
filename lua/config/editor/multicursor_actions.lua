-- Edit a snapshot of the selected ranges. Replacing one range can reverse an
-- overlapping extmark, so never read another selection halfway through a batch.
local M = {}
local api = vim.api
local main_ns = api.nvim_create_namespace("multicursorsmaincursor")
local other_ns = api.nvim_create_namespace("multicursors")

local function before(row, col, other_row, other_col)
  return row < other_row or (row == other_row and col < other_col)
end

local function boundary(text, col, forward)
  col = math.max(0, math.min(col, #text))
  while col > 0 and col < #text do
    local byte = text:byte(col + 1)
    if byte < 128 or byte >= 192 then
      break
    end
    col = col + (forward and 1 or -1)
  end
  return col
end

local function ranges()
  local lines = api.nvim_buf_get_lines(0, 0, -1, false)
  local selections = {}
  for _, ns in ipairs({ main_ns, other_ns }) do
    for _, mark in ipairs(api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
      local row, col, end_row, end_col = mark[2], mark[3], mark[4].end_row, mark[4].end_col
      if end_row and end_col then
        if before(end_row, end_col, row, col) then
          row, col, end_row, end_col = end_row, end_col, row, col
        end
        if lines[row + 1] and lines[end_row + 1] then
          selections[#selections + 1] = {
            row = row, col = boundary(lines[row + 1], col, false),
            end_row = end_row, end_col = boundary(lines[end_row + 1], end_col, true),
            main = ns == main_ns,
          }
        end
      end
    end
  end
  table.sort(selections, function(a, b)
    if a.row == b.row and a.col == b.col then
      return before(a.end_row, a.end_col, b.end_row, b.end_col)
    end
    return before(a.row, a.col, b.row, b.col)
  end)
  local merged = {}
  for _, selection in ipairs(selections) do
    local last = merged[#merged]
    if last and (before(selection.row, selection.col, last.end_row, last.end_col)
      or (selection.row == last.row and selection.col == last.col)) then
      if before(last.end_row, last.end_col, selection.end_row, selection.end_col) then
        last.end_row, last.end_col = selection.end_row, selection.end_col
      end
      last.main = last.main or selection.main
    else
      merged[#merged + 1] = selection
    end
  end
  return merged
end

function M.change_case(uppercase)
  if not vim.bo.modifiable then
    return
  end
  local selections = ranges()
  if #selections == 0 then
    return
  end
  local has_main = false
  -- Validate and calculate every replacement before touching text or markers.
  for _, selection in ipairs(selections) do
    local text = api.nvim_buf_get_text(0, selection.row, selection.col, selection.end_row, selection.end_col, {})
    selection.text = {}
    for i, line in ipairs(text) do
      selection.text[i] = uppercase and vim.fn.toupper(line) or vim.fn.tolower(line)
    end
    selection.changed = not vim.deep_equal(text, selection.text)
    has_main = has_main or selection.main
  end
  if not has_main then
    selections[#selections].main = true
  end
  api.nvim_buf_clear_namespace(0, main_ns, 0, -1)
  api.nvim_buf_clear_namespace(0, other_ns, 0, -1)
  local edited = false
  -- Work backwards so an earlier replacement cannot shift an unprocessed range.
  for i = #selections, 1, -1 do
    local selection = selections[i]
    if selection.changed then
      if edited then
        vim.cmd("undojoin")
      end
      api.nvim_buf_set_text(0, selection.row, selection.col, selection.end_row, selection.end_col, selection.text)
      edited = true
    end
    local end_col = (#selection.text == 1 and selection.col or 0) + #selection.text[#selection.text]
    api.nvim_buf_set_extmark(0, selection.main and main_ns or other_ns, selection.row, selection.col, {
      end_row = selection.end_row, end_col = end_col,
      hl_group = selection.main and "MultiCursorMain" or "MultiCursor",
    })
  end
end

return M
