local function T(text) return require("config.platform.locale").t(text) end
-- Presentation only: real Neovim text and Molten outputs stay authoritative.
-- Skia draws the rounded strokes; empty virtual rows supply their inner padding.
local M = { border_labels = true, _glow_chrome_refresh = true }
local states, windows, configured, pending, previous, timer = {}, {}, false, false, nil, nil
local api = vim.api
local padding_ns = api.nvim_create_namespace('glow.notebook.layout')
local separator_ns = api.nvim_create_namespace('glow.notebook.separator')
local footer_ns = api.nvim_create_namespace('glow.notebook.footer')
local metadata_ns = api.nvim_create_namespace('glow.notebook.metadata')
local markers_ns = api.nvim_create_namespace('glow.notebook.markers')
local molten_ns = api.nvim_create_namespace('molten-extmarks')
local blank = { { '', 'Normal' } }
local right_inset = 1
local next_epoch, popup_models = 0, {}

-- 与输入框右上标签共用右端点；多窗口时沿用最窄可见视图，避免越界。
local function label_columns(buf)
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
  return columns
end

local function line_text(chunks)
  local text = ''
  for _, chunk in ipairs(chunks) do text = text .. chunk[1] end
  return text
end

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
    local canonical = require("config.platform.notebook_chrome_locale").canonical_lines(
      buf, molten_ns, mark[1], lines)
    if mark[2] >= 0 and mark[2] < count and not mark[4].invalid and lines and is_output(lines) then
      -- Molten is the sole writer of its output. While running it replaces this
      -- mark every tick; adding padding here used to make its height oscillate.
      local width, folded = 0, false
      for index, chunks in ipairs(lines) do
        local text = line_text(chunks)
        width = math.max(width, vim.fn.strdisplaywidth(text))
        -- Geometry uses the visible text; fold semantics use its canonical label.
        local source = line_text(canonical[index])
        -- Molten 的真实折叠标记只会出现在末行，或首个状态行之后。
        -- 不因输出行数多、状态文字或任意省略号而猜测存在隐藏内容。
        if (index == #lines and source:match('^󰁅 [1-9]%d* More lines%s*$'))
            or (index == 2 and source:match('^↑ [1-9]%d* More lines%s*$')) then folded = true end
      end
      result[#result + 1] = { id = mark[1], row = mark[2], lines = #lines,
        width = width, folded = folded,
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
  local columns = label_columns(buf)
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

local function footer_chunks(columns)
  -- 左侧实心绿色图标段与输出边框同色，右侧显示按键。
  -- 独立组不声明 enlarged_icon / notebook_actions，保持与上方端帽相同字号。
  local chunks = { { '', 'GlowNotebookExpandCap' }, { '󰕏 ', 'GlowNotebookExpand' },
    { ' ␣jo', 'GlowNotebookExpandValue' }, { '', 'GlowNotebookExpandValueCap' } }
  local width = 0
  for _, chunk in ipairs(chunks) do width = width + vim.fn.strdisplaywidth(chunk[1]) end
  if not columns or width + 4 > columns then return end
  table.insert(chunks, 1, { string.rep(' ', columns - width - 2), 'Normal' })
  return chunks, { col = columns - width - 2, width = width }
end

local function footer_labels(buf, state, columns)
  local chunks, gap = footer_chunks(columns)
  if not chunks then return end
  local marks = api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })
  for _, footer in pairs(state.footer_marks) do
    -- 同锚点空行没有可用 EOL 列作排序。Molten 删除重建输出后，只重排
    -- 我们自己的末行；输出 extmark、文本、保存内容与内核始终不变。
    local seen, after = false, false
    for _, mark in ipairs(marks) do
      local d = mark[4]
      if mark[2] == footer.row and d.virt_lines and not d.invalid
          and (d.virt_lines_above == true) == footer.above then
        if d.ns_id == footer_ns and mark[1] == footer.id then seen = true
        elseif seen then after = true end
      end
    end
    if after then
      api.nvim_buf_del_extmark(buf, footer_ns, footer.id)
      state.footer_cells[footer.id] = nil
      footer.id = nil
    end
    if after or footer.columns ~= columns or not footer.id then
      footer.id = api.nvim_buf_set_extmark(buf, footer_ns, footer.row, footer.col, {
        id = footer.id, virt_lines = { copy(chunks) }, virt_lines_above = footer.above,
        right_gravity = true, strict = false,
      })
      footer.columns = columns
      state.footer_cells[footer.id] = footer.cell
    end
    state.footer_gaps[footer.cell] = gap
  end
end

local function prepare(buf, state)
  local editor = require('config.media.notebook_edit')
  if editor.refresh_labels then editor.refresh_labels(buf) end
  local list, out = cells(buf), outputs(buf)
  local geometry, footers = {}, {}
  local columns = label_columns(buf)
  for _, item in ipairs(out) do
    -- Mark identity and equal-height text/status changes do not change layout.
    geometry[#geometry + 1] = { row = item.row, lines = item.lines, above = item.above }
    for index, cell in ipairs(list) do
      if item.row + 1 >= math.max(1, cell.header > 0 and cell.header or cell.first)
          and item.row + 1 <= cell.finish then
        local footer = footers[index] or { cell = index, row = item.row, above = item.above, needed = false }
        -- 实际折叠提示，或确实超出内框宽度的虚拟行，才提供展开入口。
        footer.needed = footer.needed or item.folded == true
          or (columns ~= nil and (item.width or 0) > columns)
        if item.row >= footer.row then footer.row, footer.above = item.row, item.above end
        footers[index] = footer
        break
      end
    end
  end
  local wanted_footers = {}
  if footer_chunks(columns) then
    for _, footer in pairs(footers) do
      if footer.needed then wanted_footers[#wanted_footers + 1] = footer end
    end
    table.sort(wanted_footers, function(a, b) return a.cell < b.cell end)
  end
  local signature = { list, geometry, wanted_footers, api.nvim_buf_get_changedtick(buf), state.show_metadata,
    vim.g.neovide_native_notebook_footer == true }
  if not vim.deep_equal(signature, state.layout) then
    state.layout = copy(signature)
    state.revision = (state.revision or 0) + 1
    api.nvim_buf_clear_namespace(buf, padding_ns, 0, -1)
    api.nvim_buf_clear_namespace(buf, separator_ns, 0, -1)
    api.nvim_buf_clear_namespace(buf, footer_ns, 0, -1)
    api.nvim_buf_clear_namespace(buf, markers_ns, 0, -1)
    state.top_marks, state.label_signature, state.separator_cells = {}, nil, {}
    state.footer_marks, state.footer_cells, state.footer_gaps = {}, {}, {}
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
    for _, footer in ipairs(wanted_footers) do
      footer = copy(footer)
      footer.col = #(api.nvim_buf_get_lines(buf, footer.row, footer.row + 1, false)[1] or '')
      state.footer_marks[footer.cell] = footer
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
  footer_labels(buf, state, columns)
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
    if frame.kind ~= 'input' then
      frame.color = state.output_accent
      frame.footer_gaps = nil
      local gap = state.footer_gaps and state.footer_gaps[frame.cell]
      if vim.g.neovide_native_notebook_footer == true and gap then
        frame.footer_gaps = { { col = (info.textoff or 0) + gap.col - frame.rect.col - 0.1,
          width = gap.width + 0.2 } }
      end
      return
    end
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
      local footer = d.ns_id == footer_ns and state.footer_cells[mark[1]]
      if output or separator or footer then
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
          if output then
            image_areas[d.ns_id .. ':' .. mark[1]] = {
              row = top, col = text_left + 0.3,
              width = math.max(1, left + width - text_left - 0.6),
            }
          end
          -- A cell owns outputs by their source anchor, never by mark identity or
          -- screen overlap. Several marks extend the same outer envelope in their
          -- real display order; they do not create neighboring rounded boxes.
          for index, cell in ipairs(list) do
            if footer == index or (not footer
                and row + 1 >= math.max(1, cell.header > 0 and cell.header or cell.first)
                and row + 1 <= cell.finish) then
              local rect = outer[index].rect
              -- 新原生能力把末行胶囊中心落在底边线上；旧 GUI 保持行内安全回退。
              local end_row = footer and vim.g.neovide_native_notebook_footer == true
                and top + 0.5 or top + #d.virt_lines + 0.2
              local bottom = math.max(rect.row + rect.height, end_row)
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
  local reference = math.max(1, math.min(info.topline, api.nvim_buf_line_count(buf)))
  cached.viewport = { line = reference, row = row_at(reference) - origin[1] }
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
-- 只读取得当前逻辑 viewport 中的输出外框。布局快照刻意不随滚轮重建，
-- 因此用同一个真实文本参考行校正滚动差；不移动原窗口或修改输出。
local function output_frame_geometry(win, buf, cell)
  if not api.nvim_win_is_valid(win) or api.nvim_win_get_buf(win) ~= buf or not states[buf] then return end
  local cached = windows[win]
  local clip, info = window_geometry(win)
  if not cached or not cached.viewport or not clip then return end
  local row_at = line_geometry(win, info, clip)
  local origin = api.nvim_win_get_position(win)
  local delta = row_at(cached.viewport.line) - origin[1] - cached.viewport.row
  for _, frame in ipairs(cached.frames or {}) do
    if frame.kind == 'output' and frame.cell == cell then
      local rect = copy(frame.rect)
      rect.row, rect.col = rect.row + origin[1] + delta, rect.col + origin[2]
      return { rect = rect, clip = copy(clip), cell = cell }
    end
  end
end
function M.output_frame_geometry(win, buf, cell)
  M.refresh()
  return output_frame_geometry(win, buf, cell)
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
  require("config.platform.notebook_chrome_locale").refresh()
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
          local aligned = vim.w[win].glow_notebook_output_frame
          if type(aligned) ~= 'table' or type(aligned.row) ~= 'number' or type(aligned.col) ~= 'number'
              or type(aligned.width) ~= 'number' or type(aligned.height) ~= 'number'
              or aligned.width <= 0 or aligned.height <= 0 then aligned = nil end
          if aligned then
            -- 浮窗的整数顶行从接缝上方半格开始，会遮住原输入框的末段竖边。
            -- 顶边与圆角在 clip 外，仅补该半格两侧；绿色接缝随后覆盖端点。
            frames[#frames + 1] = { kind = 'input', overlay = true, join = 'top',
              rect = { row = aligned.row - 2, col = aligned.col, width = aligned.width, height = 2 },
              clip = local_clip, anchor = { window = win, epoch = model.epoch, scroll = false },
              active = false, dark = vim.o.background == 'dark',
              color = require('config.media.notebook_edit').cell_accent() }
          end
          frames[#frames + 1] = { kind = 'output', overlay = true,
            join = aligned and 'bottom' or nil,
            rect = aligned and copy(aligned) or { row = local_clip.row + 0.08, col = local_clip.col + 0.12, width = clip.width - 0.24, height = clip.height - 0.16 },
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
local function output_mouse()
  local mouse = vim.fn.getmousepos()
  local win = mouse.winid
  if not win or win == 0 or not api.nvim_win_is_valid(win)
      or api.nvim_win_get_config(win).relative ~= '' then return false end
  local buf = api.nvim_win_get_buf(win)
  if not states[buf] then return false end
  -- 虚拟输出行的 mouse.line 会落到相邻真实行；按当前屏幕外框命中，
  -- 只选中所属单元格，不执行展开，也不改动任何输出或全局鼠标映射。
  local row, col = mouse.screenrow - 0.5, mouse.screencol - 0.5
  M.refresh()
  for index, cell in ipairs(cells(buf)) do
    local geometry = output_frame_geometry(win, buf, index)
    if geometry then
      local rect, clip = geometry.rect, geometry.clip
      if row >= math.max(rect.row, clip.row) and row <= math.min(rect.row + rect.height, clip.row + clip.height)
          and col >= math.max(rect.col, clip.col) and col < math.min(rect.col + rect.width, clip.col + clip.width) then
        local target = cell.first <= cell.last and cell.last
          or cell_start(cell, api.nvim_buf_line_count(buf), states[buf].show_metadata)
        return { win = win, buf = buf, row = target }
      end
    end
  end
  return false
end

local function select_output_mouse(selected)
  if not selected or not api.nvim_win_is_valid(selected.win)
      or api.nvim_win_get_buf(selected.win) ~= selected.buf then return end
  api.nvim_set_current_win(selected.win)
  api.nvim_win_set_cursor(selected.win, { math.min(selected.row, api.nvim_buf_line_count(selected.buf)), 0 })
  schedule()
end
function M.finish_output_mouse()
  local selected = M.pending_output_mouse
  M.pending_output_mouse = nil
  select_output_mouse(selected)
end

local function mouse_mapping(buf, state)
  if state.mouse_mapping then return end
  state.mouse_mapping = true
  for _, mode in ipairs({ 'n', 'i', 'x' }) do
    local current_mode = mode
    local previous_map
    for _, mapping in ipairs(api.nvim_buf_get_keymap(buf, mode)) do
      if mapping.lhs == '<LeftMouse>' then
        -- 模块热加载不把上一版自身映射叠进回放链。
        if mapping.desc ~= T("Select Clicked Notebook Output Cell") then previous_map = mapping end
        break
      end
    end
    if not previous_map then
      for _, mapping in ipairs(api.nvim_get_keymap(mode)) do
        if mapping.lhs == '<LeftMouse>' then previous_map = mapping; break end
      end
    end
    vim.keymap.set(mode, '<LeftMouse>', function()
      local selected = output_mouse()
      if selected then
        if current_mode == 'n' then select_output_mouse(selected); return end
        -- 点击输出退出 i/Visual 后再选源码；普通点击不退出当前模式。
        M.pending_output_mouse = selected
        local keys = '<Esc><Cmd>lua require("config.media.notebook_ui").finish_output_mouse()<CR>'
        api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), 'ni', false)
        return
      end
      -- 普通代码/其他窗口点击继续使用原映射或原生鼠标；模式与拖选保持原状。
      if previous_map and type(previous_map.callback) == 'function' then
        local result = previous_map.callback()
        if previous_map.expr ~= 1 or type(result) ~= 'string' then return end
        api.nvim_feedkeys(api.nvim_replace_termcodes(result, true, false, true), 'ni', false)
        return
      end
      local keys = previous_map and previous_map.rhs or '<LeftMouse>'
      api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), 'ni', false)
    end, { buffer = buf, silent = true, desc = T("Select Clicked Notebook Output Cell") })
  end
end

function M.attach(buf)
  buf = buf or api.nvim_get_current_buf()
  if not available() or not api.nvim_buf_is_valid(buf) then return false end
  M.setup()
  states[buf] = states[buf] or { show_metadata = false }
  mouse_mapping(buf, states[buf])
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
  require("config.platform.locale").command('GlowNotebookMetadata', function() M.toggle_metadata() end,
    { desc = T("Show or Hide Notebook Serialization Metadata") })
  timer = vim.uv.new_timer()
  -- Molten changes extmarks without changing buffer text or firing TextChanged.
  timer:start(150, 150, vim.schedule_wrap(function()
    if next(states) then schedule() end
  end))
end
return M
