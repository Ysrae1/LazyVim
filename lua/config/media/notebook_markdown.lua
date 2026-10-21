local function T(text) return require("config.platform.locale").t(text) end
-- A public render-markdown custom handler. Parsing uses decommented strings;
-- all decoration coordinates map back to the authoritative Python buffer.
local M = {}
local states, configured, handler_ready = {}, false, false
local api = vim.api
local queries = {}

local function group(name, sources, extra)
  local attributes = {}
  for _, source in ipairs(sources) do
    local value = api.nvim_get_hl(0, { name = source, link = false, create = false })
    if value.fg then attributes.fg = value.fg; break end
  end
  for key, value in pairs(extra or {}) do attributes[key] = value end
  api.nvim_set_hl(0, 'GlowNotebookMD' .. name, attributes)
end
local function colors()
  group('Text', { 'Normal' }, { nocombine = true })
  group('Bold', { 'Normal' }, { bold = true })
  group('Italic', { 'Normal' }, { italic = true })
  group('Code', { '@markup.raw.markdown_inline', '@markup.raw', 'String', 'Normal' })
  group('Link', { '@markup.link.label.markdown_inline', '@markup.link', 'Underlined', 'Normal' }, { underline = true })
  group('Bullet', { 'RenderMarkdownBullet', '@markup.list', 'Normal' })
  for level = 1, 6 do
    group('Heading' .. level, { '@markup.heading.' .. level .. '.markdown', '@markup.heading.' .. level, 'Title', 'Normal' }, { bold = true })
  end
end

function M.options(options)
  options = options or {}
  options.custom_handlers = options.custom_handlers or {}
  local previous = options.custom_handlers.python
  options.custom_handlers.python = { parse = function(ctx)
    if states[ctx.buf] then return M.parse(ctx) end
    return previous and previous.parse(ctx) or {}
  end }
  options.on = options.on or {}
  local rendered = options.on.render
  options.on.render = function(ctx)
    if rendered then rendered(ctx) end
    local state = states[ctx.buf]
    if state and state.fingerprint ~= state.presented then
      state.presented = state.fingerprint
      state.revision = state.revision + 1
      vim.schedule(function()
        if states[ctx.buf] ~= state then return end
        local ui = package.loaded['config.media.notebook_ui']
        if ui then ui.refresh() end
      end)
    end
  end
  handler_ready = true
  return options
end

local source_queries = {
  markdown = [[
    [(atx_heading) (setext_heading)] @heading
    [(atx_h1_marker) (atx_h2_marker) (atx_h3_marker) (atx_h4_marker)
      (atx_h5_marker) (atx_h6_marker) (setext_h1_underline) (setext_h2_underline)] @heading_marker
    [(list_marker_minus) (list_marker_star) (list_marker_plus)
      (list_marker_dot) (list_marker_parenthesis)] @bullet
    [(fenced_code_block) (indented_code_block)] @code
    [(fenced_code_block_delimiter) (info_string)] @delimiter
  ]],
  markdown_inline = [[
    (strong_emphasis) @bold
    (emphasis) @italic
    (code_span) @code
    [(emphasis_delimiter) (code_span_delimiter)] @delimiter
    (inline_link) @link
  ]],
}

local function parsed(text)
  local result = {}
  -- A cell ends at a real line boundary before the next percent marker. The
  -- Markdown grammar needs that newline to recognize a closing fence at EOF.
  text = text .. '\n'
  local parser = vim.treesitter.get_string_parser(text, 'markdown')
  parser:parse(true)
  local function add(node, kind, extra)
    local sr, sc, er, ec = node:range()
    result[#result + 1] = { sr = sr, sc = sc, er = er, ec = ec, kind = kind, extra = extra }
  end
  parser:for_each_tree(function(tree, language)
    local name = language:lang()
    if not source_queries[name] then return end
    queries[name] = queries[name] or vim.treesitter.query.parse(name, source_queries[name])
    for id, node in queries[name]:iter_captures(tree:root(), text) do
      local capture = queries[name].captures[id]
      if capture == 'heading' then
        local level = 1
        for child in node:iter_children() do
          level = tonumber(child:type():match('h(%d)')) or level
        end
        add(node, 'Heading' .. level)
      elseif capture == 'heading_marker' then
        add(node, 'conceal', '')
      elseif capture == 'bullet' then
        local value = vim.treesitter.get_node_text(node, text)
        if value:match('^[%-%+%*]') then
          local row, col = node:range()
          result[#result + 1] = { sr = row, sc = col, er = row, ec = col + 1, kind = 'conceal', extra = '•' }
        end
        add(node, 'Bullet')
      elseif capture == 'delimiter' then
        add(node, 'conceal', '')
      elseif capture == 'link' then
        local label
        for child in node:iter_children() do if child:type() == 'link_text' then label = child; break end end
        if label then
          add(label, 'Link')
          local sr, sc, er, ec = node:range()
          local lr, lc, le, lex = label:range()
          result[#result + 1] = { sr = sr, sc = sc, er = lr, ec = lc, kind = 'conceal', extra = '' }
          result[#result + 1] = { sr = le, sc = lex, er = er, ec = ec, kind = 'conceal', extra = '' }
        end
      else
        add(node, capture:sub(1, 1):upper() .. capture:sub(2))
      end
    end
  end)
  return result
end

local function edit_options(buf, leaving)
  local state = states[buf]
  if not state or not api.nvim_buf_is_valid(buf) then return end
  local active = false
  if not leaving and api.nvim_get_current_buf() == buf and vim.fn.mode(true):match('^[iR]') then
    local row = api.nvim_win_get_cursor(0)[1]
    for _, cell in ipairs(require('config.media.notebook_edit').cells(buf)) do
      if cell.kind == 'markdown' and row > cell.header and row <= cell.finish then active = true; break end
    end
  end
  if active and not state.edit_options then
    local options = vim.bo[buf]
    state.edit_options = { comments = options.comments, formatoptions = options.formatoptions }
    options.comments = 'b:#'
    if not options.formatoptions:find('r', 1, true) then options.formatoptions = options.formatoptions .. 'r' end
  elseif not active and state.edit_options then
    vim.bo[buf].comments = state.edit_options.comments
    vim.bo[buf].formatoptions = state.edit_options.formatoptions
    state.edit_options = nil
  end
end

local function delete_key(buf, key)
  if api.nvim_get_current_buf() ~= buf or not vim.b[buf].glow_notebook_edit
    or not vim.fn.mode(true):match('^i') then return key end
  local cursor = api.nvim_win_get_cursor(0)
  local row, col = cursor[1], cursor[2]
  for _, cell in ipairs(require('config.media.notebook_edit').cells(buf)) do
    if cell.kind == 'markdown' and row > cell.header and row <= cell.finish then
      local line = api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ''
      if key == '<BS>' then
        local prefix = #(line:match('^# ?') or '')
        if col > prefix then return key end
        if row == cell.header + 1 then return '<Ignore>' end
        return string.rep('<Right>', prefix - col) .. string.rep('<BS>', prefix + 1)
      elseif col >= #line then
        if row == cell.finish then return '<Ignore>' end
        local next_line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
        return string.rep('<Del>', #(next_line:match('^# ?') or '') + 1)
      end
      return key
    end
  end
  return key
end

function M.parse(ctx)
  local state = states[ctx.buf]
  if not state or not vim.b[ctx.buf].glow_notebook_edit then return {} end
  local editor = require('config.media.notebook_edit')
  local lines, marks, keep = api.nvim_buf_get_lines(ctx.buf, 0, -1, false), {}, {}
  local mode = vim.fn.mode(true)
  local editing = mode:match('^[iRvV]') or mode:byte(1) == 22
  local current = api.nvim_get_current_buf() == ctx.buf and api.nvim_win_get_cursor(0)[1] or -1
  local function mark(row, col, options)
    options.priority = options.priority or 230
    marks[#marks + 1] = { start_row = row, start_col = col, opts = options, conceal = false }
  end
  for _, cell in ipairs(editor.cells(ctx.buf)) do
    if cell.kind == 'markdown' then
      local raw, offsets = {}, {}
      local start = cell.header + 1
      for row = start, cell.finish do
        local line = lines[row] or ''
        local prefix = line:match('^# ?') or ''
        offsets[#offsets + 1] = #prefix
        raw[#raw + 1] = line:sub(#prefix + 1)
        -- Override Python's comment color without changing stored text.
        if #line > 0 then mark(row - 1, 0, { end_col = #line, hl_group = 'GlowNotebookMDText', priority = 210 }) end
      end
      local active = editing and current >= start and current <= cell.finish
      -- Jupytext's storage wrapper stays hidden even while editing. Markdown's
      -- own heading/emphasis/link syntax is exposed by the active-cell branch.
      for index, offset in ipairs(offsets) do
        if offset > 0 then mark(cell.header + index - 1, 0, { end_col = offset, conceal = '' }) end
      end
      if not active then
        local text = table.concat(raw, '\n')
        local cached = state.cache[cell.header]
        if not cached or cached.text ~= text then
          local ok, value = pcall(parsed, text)
          cached = { text = text, marks = ok and value or {} }
          state.cache[cell.header] = cached
          if not ok and not state.warned then
            state.warned = true
            vim.notify(T("Notebook Markdown parsing is unavailable. Editable source is preserved: ") .. tostring(value), vim.log.levels.WARN)
          end
        end
        keep[cell.header] = true
        for _, item in ipairs(cached.marks) do
          local options = { end_row = cell.header + item.er, end_col = item.ec + (offsets[item.er + 1] or 0) }
          if item.kind == 'conceal' then options.conceal = item.extra; options.priority = 250
          else options.hl_group = 'GlowNotebookMD' .. item.kind end
          mark(cell.header + item.sr, item.sc + (offsets[item.sr + 1] or 0), options)
        end
      end
    end
  end
  for key in pairs(state.cache) do if not keep[key] then state.cache[key] = nil end end
  local geometry = {}
  for _, item in ipairs(marks) do
    if item.opts.conceal ~= nil then
      geometry[#geometry + 1] = { item.start_row, item.start_col, item.opts.end_row or item.start_row,
        item.opts.end_col, item.opts.conceal }
    end
  end
  state.fingerprint = vim.json.encode(geometry)
  return marks
end

function M.presentation_revision(buf)
  return states[buf] and states[buf].revision or 0
end

function M.refresh(buf)
  local state = states[buf]
  if not state or not api.nvim_buf_is_valid(buf) then return end
  state.pending = false
  edit_options(buf)
  local renderer = require('render-markdown')
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    renderer.render({ buf = buf, win = win, config = { enabled = true, render_modes = true, debounce = 0,
      anti_conceal = { enabled = false }, win_options = {
        conceallevel = { default = 2, rendered = 2 }, concealcursor = { default = 'nvic', rendered = 'nvic' },
      } } })
  end
end
local function schedule(buf)
  local state = states[buf]
  if not state or state.pending then return end
  state.pending = true
  vim.schedule(function() M.refresh(buf) end)
end

function M.attach(buf)
  if not vim.b[buf].glow_notebook_edit then return false end
  if states[buf] then schedule(buf); return true end
  local lazy_ok, lazy = pcall(require, 'lazy')
  if lazy_ok then lazy.load({ plugins = { 'render-markdown.nvim' } }) end
  local ok, renderer = pcall(require, 'render-markdown')
  if not ok then return false end
  if not renderer.initialized then renderer.setup(M.options({})) end
  if not handler_ready then return false end
  states[buf] = { cache = {}, revision = 0 }
  for _, key in ipairs({ '<BS>', '<Del>' }) do
    vim.keymap.set('i', key, function() return delete_key(buf, key) end,
      { buffer = buf, expr = true, desc = 'Delete Notebook Markdown text' })
  end
  if not configured then
    configured = true; colors()
    api.nvim_create_autocmd({ 'ColorScheme' }, { callback = function() colors(); for source in pairs(states) do schedule(source) end end })
  end
  local group_id = api.nvim_create_augroup('GlowNotebookMarkdown' .. buf, { clear = true })
  api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'CursorMoved', 'CursorMovedI', 'ModeChanged', 'InsertEnter', 'InsertLeave', 'BufWinEnter', 'WinScrolled' },
    { group = group_id, buffer = buf, callback = function() edit_options(buf); schedule(buf) end })
  api.nvim_create_autocmd('BufLeave', { group = group_id, buffer = buf, callback = function() edit_options(buf, true) end })
  api.nvim_create_autocmd('BufWipeout', { group = group_id, buffer = buf, callback = function() states[buf] = nil end })
  schedule(buf)
  return true
end

return M
