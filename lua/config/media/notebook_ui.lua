-- Presentation only: real Neovim text and Molten outputs stay authoritative.
-- Skia draws the rounded strokes; empty virtual rows supply their inner padding.
local M = { border_labels = true }
local states, windows, configured, pending, previous, timer = {}, {}, false, false, nil, nil
local api = vim.api
local padding_ns = api.nvim_create_namespace('glow.notebook.layout')
local separator_ns = api.nvim_create_namespace('glow.notebook.separator')
local metadata_ns = api.nvim_create_namespace('glow.notebook.metadata')
local markers_ns = api.nvim_create_namespace('glow.notebook.markers')
local molten_ns = api.nvim_create_namespace('molten-extmarks')
local blank = { { '', 'Normal' } }
local right_inset = 1
local next_epoch, popup_models = 0, {}

local function available()
  return vim.g.neovide_native_notebook == true and type(vim.g.neovide_channel_id) == 'number'
end
local function copy(value) return vim.deepcopy(value) end
local function emit(frames, viewports)
  viewports = viewports or {}
  local snapshot = { frames, viewports }
  if available() and not vim.deep_equal(previous, snapshot) then
    previous = copy(snapshot)
    if vim.g.neovide_native_notebook_viewport == true then
      pcall(vim.rpcnotify, vim.g.neovide_channel_id, 'neovide.notebook.frames', frames, viewports)
    else
      pcall(vim.rpcnotify, vim.g.neovide_channel_id, 'neovide.notebook.frames', frames)
    end
    -- Local redraw supplies the matching UI flush after this notification. It
    -- never requests or waits for anything from Neovide, including during scroll.
    pcall(vim.cmd.redraw)
  end
end
local function cells(buf)
  local ok, editor = pcall(require, 'config.media.notebook_edit')
  return ok and editor.cells(buf) or {}
end
local function is_output(lines)
  for _, line in ipairs(lines or {}) do
    local text = ''
    for _, chunk in ipairs(line) do text = text .. chunk[1] end
    if text:find('Out[', 1, true) then return true end
  end
  return false
end
local function outputs(buf)
  local result = {}
  local count = api.nvim_buf_line_count(buf)
  for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, molten_ns, 0, -1, { details = true })) do
    local lines = mark[4].virt_lines
    if mark[2] >= 0 and mark[2] < count and not mark[4].invalid and lines and is_output(lines) then
      -- Molten is the sole writer of its output. While running it replaces this
      -- mark every tick; adding padding here used to make its height oscillate.
      result[#result + 1] = { id = mark[1], row = mark[2], lines = #lines,
        namespace = molten_ns, above = mark[4].virt_lines_above == true }
    end
  end
  local images = package.loaded['config.media.molten_images']
  if images and images.inline_output_marks then vim.list_extend(result, images.inline_output_marks(buf)) end
  return result
end
local function cell_start(cell, count, show_source)
  if show_source and cell.header > 0 then return cell.header end
  if cell.first <= cell.last then return cell.first end
  -- An empty cell needs a real editable line. A trailing marker with no such
  -- line stays visible until text is inserted instead of hiding the cursor.
  return math.max(1, math.min(cell.header + 1, cell.finish, count))
end
local function metadata(buf, state)
  local lines = api.nvim_buf_get_lines(buf, 0, math.min(200, api.nvim_buf_line_count(buf)), false)
  local first, last = 1, nil
  -- Recovery and ordinary edits can leave blank lines before the Jupytext
  -- preamble. They do not turn its serialization metadata into cell content.
  while lines[first] and lines[first]:match('^%s*$') do first = first + 1 end
  if lines[first] and lines[first]:match('^# %-%-%-%s*$') then
    for index = first + 1, #lines do
      if lines[index]:match('^# %-%-%-%s*$') then last = index; break end
    end
  end
  -- A whole-buffer reload can move extmarks even when the metadata has exactly
  -- the same shape. Its text generation must invalidate the stored positions.
  local signature = tostring(state.show_metadata) .. ':' .. tostring(last)
    .. ':' .. tostring(api.nvim_buf_get_changedtick(buf))
  if signature ~= state.metadata then
    state.metadata = signature
    api.nvim_buf_clear_namespace(buf, metadata_ns, 0, -1)
    if last and not state.show_metadata then
      -- One mark per physical metadata line gives unambiguous conceal coverage.
      for row = 0, last - 1 do
        api.nvim_buf_set_extmark(buf, metadata_ns, row, 0, { conceal_lines = '' })
      end
      -- A newly opened Notebook starts at its first editable cell, rather than
      -- leaving the real cursor inside metadata that has just become hidden.
      local first = cells(buf)[1]
      local target = first and math.max(last + 1, first.first) or last + 1
      target = math.min(target, api.nvim_buf_line_count(buf))
      for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        if api.nvim_win_get_cursor(win)[1] <= last then api.nvim_win_set_cursor(win, { target, 0 }) end
      end
    end
  end
end
local function top_labels(buf, state, editor)
  local columns
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if api.nvim_win_get_config(win).relative == '' then
      local info = vim.fn.getwininfo(win)[1]
      if info then
        local width = info.width - math.max(2, info.textoff) - right_inset
        columns = math.min(columns or width, width)
      end
    end
  end
  local labels = editor.cell_labels and editor.cell_labels(buf) or {}
  local signature = { columns, labels }
  state.accent = api.nvim_get_hl(0, { name = 'GlowNotebookCell', link = false }).bg
    or editor.cell_accent()
  state.output_accent = editor.output_accent()
  if vim.deep_equal(signature, state.label_signature) then return end
  state.label_signature, state.label_gaps = copy(signature), {}
  for _, mark in pairs(state.top_marks) do
    api.nvim_buf_set_extmark(buf, padding_ns, mark.row, 0, {
      id = mark.id, virt_lines = { copy(blank) }, virt_lines_above = true,
      right_gravity = false, strict = false,
    })
  end
  for _, label in ipairs(labels) do
    local mark = state.top_marks[label.index]
    if mark then
      local width = label.width
      if not width then
        local text = ''; for _, chunk in ipairs(label.chunks) do text = text .. chunk[1] end
        width = vim.fn.strdisplaywidth(text)
      end
      if columns and width + 4 <= columns then
        local prefix = columns - width - 2 -- keep the top-right rounded corner clear
        local chunks = { { string.rep(' ', prefix), 'Normal' } }
        vim.list_extend(chunks, copy(label.chunks))
        api.nvim_buf_set_extmark(buf, padding_ns, mark.row, 0, {
          id = mark.id, virt_lines = { chunks }, virt_lines_above = true,
          right_gravity = false, strict = false,
        })
        local gaps, cursor, segment = {}, prefix, nil
        for _, chunk in ipairs(label.chunks) do
          local size = vim.fn.strdisplaywidth(chunk[1])
          if chunk[2] == 'GlowNotebookBar' and chunk[1]:match('^ +$') then
            if segment then gaps[#gaps + 1] = segment; segment = nil end
          else
            segment = segment or { col = cursor, width = 0 }
            segment.width = segment.width + size
          end
          cursor = cursor + size
        end
        if segment then gaps[#gaps + 1] = segment end
        state.label_gaps[label.index] = gaps
      end
    end
  end
end
local function prepare(buf, state)
  local editor = require('config.media.notebook_edit')
  if editor.refresh_labels then editor.refresh_labels(buf) end
  local list, out = cells(buf), outputs(buf)
  local geometry = {}
  for _, item in ipairs(out) do
    -- Mark identity and equal-height text/status changes do not change layout.
    geometry[#geometry + 1] = { row = item.row, lines = item.lines, above = item.above }
  end
  local signature = { list, geometry, api.nvim_buf_get_changedtick(buf), state.show_metadata }
  if not vim.deep_equal(signature, state.layout) then
    state.layout = copy(signature)
    state.revision = (state.revision or 0) + 1
    api.nvim_buf_clear_namespace(buf, padding_ns, 0, -1)
    api.nvim_buf_clear_namespace(buf, separator_ns, 0, -1)
    api.nvim_buf_clear_namespace(buf, markers_ns, 0, -1)
    state.top_marks, state.label_signature, state.separator_cells = {}, nil, {}
    local count = api.nvim_buf_line_count(buf)
    for index, cell in ipairs(list) do
      local first = cell_start(cell, count, state.show_metadata)
      if cell.header > 0 and first > cell.header and not state.show_metadata then
        api.nvim_buf_set_extmark(buf, markers_ns, cell.header - 1, 0, {
          conceal_lines = '',
        })
      end
      local last = math.max(first, cell.last)
      local first_output
      for _, item in ipairs(out) do
        if item.row + 1 >= math.max(1, cell.header > 0 and cell.header or first)
            and item.row + 1 <= cell.finish then first_output = item; break end
      end
      local mark = api.nvim_buf_set_extmark(buf, padding_ns, first - 1, 0, {
        virt_lines = { copy(blank) }, virt_lines_above = true, right_gravity = false, strict = false,
      })
      state.top_marks[index] = { id = mark, row = first - 1 }
      if first_output then
        -- Left gravity sorts this independent row before Molten's right-gravity
        -- mark at the same anchor, even when Molten recreates its mark each tick.
        -- Molten's original virtual lines and their height are never rewritten.
        local separator = api.nvim_buf_set_extmark(buf, separator_ns, first_output.row, 0, {
          virt_lines = { copy(blank) }, virt_lines_above = first_output.above,
          right_gravity = false, strict = false,
        })
        state.separator_cells[separator] = index
      else
        api.nvim_buf_set_extmark(buf, padding_ns, last - 1, 0, {
          virt_lines = { copy(blank) }, right_gravity = false, strict = false,
        })
      end
    end
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      local row = api.nvim_win_get_cursor(win)[1]
      for _, cell in ipairs(list) do
        if row == cell.header and not state.show_metadata then
          api.nvim_win_set_cursor(win, { cell_start(cell, count, false), 0 }); break
        end
      end
    end
  end
  top_labels(buf, state, editor)
  metadata(buf, state)
  return list, out
end
local function window_geometry(win, outer)
  local info = vim.fn.getwininfo(win)[1]
  if not info then return end
  local position = api.nvim_win_get_position(win)
  local config = api.nvim_win_get_config(win)
  local top, left = position[1] + (info.winbar or 0), position[2]
  local border_top, border_bottom, border_left, border_right = 0, 0, 0, 0
  local border = config.border
  if type(border) == 'table' then
    local function exists(indices)
      for _, index in ipairs(indices) do
        local value = border[index]
        if type(value) == 'table' then value = value[1] end
        if value and value ~= '' then return 1 end
      end
      return 0
    end
    border_top, border_bottom = exists({1,2,3}), exists({5,6,7})
    border_left, border_right = exists({1,8,7}), exists({3,4,5})
    top = top + border_top; left = left + border_left
  end
  if outer then
    -- Neovide identifies the owning floating grid by its complete bounds,
    -- including any border that an already-running Molten host still supplies.
    return { row = position[1], col = position[2],
      width = config.width + border_left + border_right,
      height = config.height + border_top + border_bottom }, info
  end
  return { row = top, col = left, width = api.nvim_win_get_width(win), height = info.height }, info
end
local function line_geometry(win, info, clip)
  local saved = api.nvim_win_call(win, vim.fn.winsaveview)
  local count = api.nvim_buf_line_count(api.nvim_win_get_buf(win))
  -- BufWinEnter can observe a reload's short intermediate buffer while its
  -- viewport/old output marks still describe the previous text generation.
  local function bounded(line) return math.max(1, math.min(line, count)) end
  local ref = bounded(info.topline)
  -- Screenpos can still describe the previous screen immediately after virtual
  -- rows change. Text-height + the saved viewport is the logical grid model and
  -- is valid before redraw as well as while the native spring is still moving.
  local skipped = 0
  if (saved.skipcol or 0) > 0 then
    skipped = api.nvim_win_text_height(win, { start_row = ref - 1, start_vcol = 0,
      end_row = ref - 1, end_vcol = saved.skipcol }).all
  end
  local ref_row = clip.row + (saved.topfill or 0) - skipped
  local cache = {}
  local function text_row(line)
    line = bounded(line)
    if cache[line] then return cache[line] end
    local a, b = math.min(ref, line), math.max(ref, line)
    local distance = 0
    if a ~= b then
      distance = api.nvim_win_text_height(win, { start_row = a - 1, start_vcol = 0, end_row = b - 1, end_vcol = 0 }).all
    end
    local row = ref_row + (line >= ref and distance or -distance)
    cache[line] = row
    return row
  end
  local function text_height(line)
    line = bounded(line)
    return api.nvim_win_text_height(win, { start_row = line - 1, start_vcol = 0, end_row = line - 1 }).all
  end
  return text_row, text_height
end
local function normal_frames(win, buf, list, out, frames)
  if not windows[win] then
    windows[win] = { buf = buf, conceallevel = vim.wo[win].conceallevel,
      concealcursor = vim.wo[win].concealcursor, signcolumn = vim.wo[win].signcolumn }
  end
  local initial = vim.fn.getwininfo(win)[1]
  if initial and initial.textoff < 2 then vim.wo[win].signcolumn = 'yes:1' end
  local clip, info = window_geometry(win)
  if not clip then return end
  local state = states[buf]
  if not state.show_metadata then vim.wo[win].conceallevel = 2; vim.wo[win].concealcursor = 'nvic'
  else vim.wo[win].conceallevel = windows[win].conceallevel; vim.wo[win].concealcursor = windows[win].concealcursor end
  local current = api.nvim_win_get_cursor(win)[1]
  local selected
  for index, cell in ipairs(list) do
    if current >= math.max(1, cell.header) then selected = index end
  end
  local cached = windows[win]
  local function style(frame)
    if frame.kind ~= 'input' then frame.color = state.output_accent; return end
    frame.color = state.accent
    frame.label_gaps = nil
    for _, gap in ipairs(state.label_gaps and state.label_gaps[frame.cell] or {}) do
      frame.label_gaps = frame.label_gaps or {}
      frame.label_gaps[#frame.label_gaps + 1] = {
        col = (info.textoff or 0) + gap.col - frame.rect.col - 0.1, width = gap.width + 0.2 }
    end
  end
  local markdown = package.loaded['config.media.notebook_markdown']
  local markdown_revision = markdown and markdown.presentation_revision(buf) or 0
  local images = package.loaded['config.media.molten_images']
  local image_revision = images and images.inline_revision(buf) or 0
  local key = { state.revision, state.metadata, markdown_revision, image_revision, clip.width, info.width, clip.height, info.textoff,
    info.winbar, vim.wo[win].wrap, vim.wo[win].foldlevel, vim.wo[win].foldenable }
  if vim.deep_equal(key, cached.model_key) then
    for _, frame in ipairs(cached.frames) do
      local item = copy(frame)
      item.active = (item.kind == 'input' or item.join == 'bottom')
        and item.cell == selected and win == api.nvim_get_current_win()
      item.dark = vim.o.background == 'dark'
      style(item)
      frames[#frames + 1] = item
    end
    return
  end
  next_epoch = next_epoch + 1
  local epoch, first_frame = next_epoch, #frames + 1
  local row_at, line_height = line_geometry(win, info, clip)
  local text_left = clip.col + (info.textoff or 0)
  -- Leave line numbers untouched: the stroke lives in the gap at their right.
  local left = math.max(clip.col + 0.12, text_left - 0.8)
  local width = clip.col + clip.width - right_inset - 0.12 - left
  local outer, dividers, image_areas = {}, {}, {}
  for index, cell in ipairs(list) do
    local first = cell_start(cell, api.nvim_buf_line_count(buf), state.show_metadata)
    local last = math.max(first, cell.last)
    local top = row_at(first) - 0.5 -- center the stroke on the label's virtual row
    local bottom = row_at(last) + line_height(last) + 0.4
    local rect = { row = top, col = left, width = width, height = math.max(1, bottom - top) }
    local frame = { kind = 'input', cell = index, rect = rect, clip = clip,
      active = index == selected and win == api.nvim_get_current_win(), dark = vim.o.background == 'dark' }
    outer[index] = frame
    frames[#frames + 1] = frame
  end
  -- Traverse the actual marks in rendering order, including other plugins' rows.
  -- This avoids guessing the location from output text length or mark IDs.
  local offset_above, offset_below = {}, {}
  local wanted = {}
  for _, item in ipairs(out) do wanted[(item.namespace or molten_ns) .. ':' .. item.id] = item end
  for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
    local d, row = mark[4], mark[2]
    if d.virt_lines and not d.invalid then
      local offsets = d.virt_lines_above and offset_above or offset_below
      local offset = offsets[row] or 0
      local output = wanted[d.ns_id .. ':' .. mark[1]]
      local separator = d.ns_id == separator_ns and state.separator_cells[mark[1]]
      if output or separator then
        local top = row_at(row + 1)
        if d.virt_lines_above then
          local total = 0
          for _, other in ipairs(api.nvim_buf_get_extmarks(buf, -1, {row,0}, {row,-1}, {details=true})) do
            if other[4].virt_lines_above then total = total + #(other[4].virt_lines or {}) end
          end
          top = top - total
        else top = top + line_height(row + 1) end
        top = top + offset
        if separator then dividers[separator] = top + 0.5
        else
          image_areas[d.ns_id .. ':' .. mark[1]] = {
            row = top, col = text_left + 0.3,
            width = math.max(1, left + width - text_left - 0.6),
          }
          -- A cell owns outputs by their source anchor, never by mark identity or
          -- screen overlap. Several marks extend the same outer envelope in their
          -- real display order; they do not create neighboring rounded boxes.
          for index, cell in ipairs(list) do
            if row + 1 >= math.max(1, cell.header > 0 and cell.header or cell.first)
                and row + 1 <= cell.finish then
              local rect = outer[index].rect
              local bottom = math.max(rect.row + rect.height, top + #d.virt_lines + 0.2)
              rect.height = bottom - rect.row
              break
            end
          end
        end
      end
      offsets[row] = offset + #d.virt_lines
    end
  end
  for index in ipairs(list) do
    if dividers[index] then
      local input, joint = outer[index], dividers[index]
      local bottom = input.rect.row + input.rect.height
      input.rect.height, input.join = joint - input.rect.row, 'top'
      frames[#frames + 1] = { kind = 'output', join = 'bottom', cell = index,
        rect = { row = joint, col = left, width = width, height = bottom - joint },
        clip = clip, active = input.active, dark = vim.o.background == 'dark' }
    end
  end
  -- Freeze document layout in owner-local coordinates. Wheel scrolling updates
  -- the renderer's viewport counter/spring, not this Lua geometry snapshot.
  -- Keep offscreen cells too so they can enter the viewport without another RPC.
  local origin = api.nvim_win_get_position(win)
  cached.model_key, cached.frames, cached.image_areas = copy(key), {}, image_areas
  for _, area in pairs(image_areas) do
    area.row, area.col = area.row - origin[1], area.col - origin[2]
    area.clip = copy(clip)
    area.clip.row, area.clip.col = area.clip.row - origin[1], area.clip.col - origin[2]
    area.anchor = { window = win, epoch = epoch, scroll = true }
  end
  for index = first_frame, #frames do
    local frame = frames[index]
    frame.rect.row, frame.rect.col = frame.rect.row - origin[1], frame.rect.col - origin[2]
    frame.clip = copy(frame.clip)
    frame.clip.row, frame.clip.col = frame.clip.row - origin[1], frame.clip.col - origin[2]
    frame.anchor = { window = win, epoch = epoch, scroll = true }
    style(frame)
    cached.frames[#cached.frames + 1] = copy(frame)
  end
end
-- The same measurement/order and output epoch used by the green frame. Image
-- positions remain document-local while the native viewport animates scrolling.
function M.virtual_output_geometry(win, buf, namespace, identifier)
  if not states[buf] or not api.nvim_win_is_valid(win) or api.nvim_win_get_buf(win) ~= buf then return end
  M.refresh()
  local cached = windows[win]
  local area = cached and cached.image_areas and cached.image_areas[namespace .. ':' .. identifier]
  return area and copy(area) or nil
end
function M.refresh()
  pending = false
  if not available() then return {} end
  for win, saved in pairs(windows) do
    if not api.nvim_win_is_valid(win) or api.nvim_win_get_buf(win) ~= saved.buf then
      if api.nvim_win_is_valid(win) then
        for _, key in ipairs({ 'conceallevel', 'concealcursor', 'signcolumn' }) do vim.wo[win][key] = saved[key] end
      end
      windows[win] = nil
    end
  end
  local frames, viewports, prepared, notebook_visible = {}, {}, {}, false
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    local buf = api.nvim_win_get_buf(win)
    if states[buf] and api.nvim_win_get_config(win).relative == '' then
      notebook_visible = true
      viewports[#viewports + 1] = { window = win, width = api.nvim_win_get_width(win) }
      if not prepared[buf] then prepared[buf] = { prepare(buf, states[buf]) } end
      normal_frames(win, buf, prepared[buf][1], prepared[buf][2], frames)
    end
  end
  if notebook_visible then
    for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
      local buf = api.nvim_win_get_buf(win)
      local config = api.nvim_win_get_config(win)
      if vim.bo[buf].filetype == 'molten_output' and config.relative ~= '' then
        local clip = window_geometry(win, true)
        if clip and clip.width > 1 and clip.height > 0.5 then
          local origin = api.nvim_win_get_position(win)
          local key = { buf, clip.width, clip.height }
          local model = popup_models[win]
          if not model or not vim.deep_equal(model.key, key) then
            next_epoch = next_epoch + 1
            model = { key = key, epoch = next_epoch }; popup_models[win] = model
          end
          local local_clip = copy(clip)
          local_clip.row, local_clip.col = clip.row - origin[1], clip.col - origin[2]
          frames[#frames + 1] = { kind = 'output', overlay = true,
            rect = { row = local_clip.row + 0.08, col = local_clip.col + 0.12, width = clip.width - 0.24, height = clip.height - 0.16 },
            clip = local_clip, anchor = { window = win, epoch = model.epoch, scroll = false },
            active = win == api.nvim_get_current_win(), dark = vim.o.background == 'dark',
            color = require('config.media.notebook_edit').output_accent() }
        end
      end
    end
  end
  for win in pairs(popup_models) do
    if not api.nvim_win_is_valid(win) then popup_models[win] = nil end
  end
  emit(frames, viewports)
  return frames
end
local function schedule()
  if pending then return end
  pending = true
  vim.schedule(M.refresh)
end
function M.attach(buf)
  buf = buf or api.nvim_get_current_buf()
  if not available() or not api.nvim_buf_is_valid(buf) then return false end
  M.setup()
  states[buf] = states[buf] or { show_metadata = false }
  schedule()
  return true
end
function M.toggle_metadata(buf)
  buf = buf or api.nvim_get_current_buf()
  if states[buf] then states[buf].show_metadata = not states[buf].show_metadata; schedule() end
end
function M.setup()
  if configured or not available() then return end
  configured = true
  -- Configure Molten before its first initialization, instead of fighting its
  -- recurring Python popup updates by changing an individual window afterward.
  vim.g.molten_output_win_border = 'none'
  local group = api.nvim_create_augroup('GlowNotebookUI', { clear = true })
  api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'TextChanged', 'TextChangedI', 'WinScrolled',
    'WinResized', 'VimResized', 'BufWinEnter', 'BufWinLeave', 'WinEnter', 'WinClosed', 'TabEnter', 'ColorScheme' },
    { group = group, callback = schedule })
  api.nvim_create_autocmd('TabLeave', { group = group, callback = function()
    -- Native bindings are cleared with the hidden tab. Returning measures a new
    -- logical viewport instead of rebinding an old cached scrolling origin.
    for _, cached in pairs(windows) do cached.model_key = nil end
    previous = nil; emit({})
  end })
  api.nvim_create_autocmd('BufWipeout', { group = group, callback = function(ev) states[ev.buf] = nil; schedule() end })
  api.nvim_create_autocmd('VimLeavePre', { group = group, callback = function()
    if timer then timer:stop(); timer:close(); timer = nil end
    emit({})
  end })
  api.nvim_create_user_command('GlowNotebookMetadata', function() M.toggle_metadata() end,
    { desc = '显示或隐藏 Notebook 序列化元数据' })
  timer = vim.uv.new_timer()
  -- Molten changes extmarks without changing buffer text or firing TextChanged.
  timer:start(150, 150, vim.schedule_wrap(function()
    if next(states) then schedule() end
  end))
end
return M
