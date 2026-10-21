-- Translate rendered diagnostics, never the diagnostic store or LSP/code-action payloads.
local M = {}
local catalog = require("config.platform.diagnostic_messages")
local state_key = "config.platform.diagnostic_locale_state"
local state = package.loaded[state_key] or { originals = {}, floats = {}, lists = {} }
package.loaded[state_key] = state
state.impl = M

local aliases = {
  mypy = "mypy", pyright = "pyright", basedpyright = "pyright", pylance = "pyright",
  ruff = "ruff", ruff_lsp = "ruff", lua_ls = "lua_ls", ["lua diagnostics."] = "lua_ls", ["lua diagnostics"] = "lua_ls",
  ["lua language server"] = "lua_ls", ["lua-language-server"] = "lua_ls", luals = "lua_ls",
  clang = "clangd", clangd = "clangd", ["clang-tidy"] = "clangd",
  gopls = "go", compiler = "go", ["go list"] = "go", typecheck = "go", unusedparams = "go",
  json = "json", jsonls = "json", ["json language server"] = "json",
  texlab = "texlab", latex = "texlab", bibtex = "texlab", chktex = "texlab",
  marksman = "marksman", neocmake = "neocmake", neocmakelsp = "neocmake", cmake = "neocmake",
  yamllint = "yamllint", shellcheck = "shellcheck", ltex = "ltex", ["ltex-ls"] = "ltex",
}

local function language()
  local locale = package.loaded["config.platform.locale"]
  return locale and locale.current() or (vim.g.glow_ui_language == "zh" and "zh" or "en")
end

local function escape(s)
  return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

local function compile(template)
  local parts, names, offset = {}, {}, 1
  while true do
    local first, last, name = template:find("{([%w_]+)}", offset)
    if not first then break end
    parts[#parts + 1] = escape(template:sub(offset, first - 1))
    parts[#parts + 1], names[#names + 1] = "(.-)", name
    offset = last + 1
  end
  parts[#parts + 1] = escape(template:sub(offset))
  return { pattern = "^" .. table.concat(parts) .. "$", names = names, literal = template }
end

local function match(rule, text)
  if #rule.names == 0 then return text == rule.literal and {} or nil end
  local matches = { text:match(rule.pattern) }
  if #matches == 0 then return end
  local values = {}
  for i, name in ipairs(rule.names) do
    if values[name] and values[name] ~= matches[i] then return end
    values[name] = matches[i]
  end
  return values
end

local function render(template, values)
  return (template:gsub("{([%w_]+)}", function(name) return values[name] or "{" .. name .. "}" end))
end

local compiled = {}
for source, rows in pairs(catalog) do
  compiled[source] = {}
  for _, row in ipairs(rows) do
    local codes
    if row[3] then
      codes = {}
      for _, code in ipairs(type(row[3]) == "table" and row[3] or { row[3] }) do codes[tostring(code)] = true end
    end
    local rule = { en = compile(row[1]), zh = compile(row[2]), codes = codes, alias = row[4] and compile(row[4]) }
    compiled[source][#compiled[source] + 1] = rule
  end
  -- Specific templates must precede broad placeholder templates.
  table.sort(compiled[source], function(a, b)
    return #a.en.literal - #a.en.names * 4 > #b.en.literal - #b.en.names * 4
  end)
end

local function source_for(diagnostic)
  local source = tostring(diagnostic.source or ""):lower()
  local name = aliases[source]
  if (source == "compiler" or source == "typecheck") and diagnostic.bufnr and vim.api.nvim_buf_is_valid(diagnostic.bufnr) then
    if vim.bo[diagnostic.bufnr].filetype ~= "go" then return end
  end
  return name
end

local function line(text, rules, code, lang)
  local prefix, body, suffix = text:match("^(%s*)(.-)(%s*)$")
  for _, rule in ipairs(rules) do
    if not rule.codes or not code or rule.codes[tostring(code)] then
      local values = match(rule.en, body) or match(rule.zh, body) or (rule.alias and match(rule.alias, body))
      if values then return prefix .. render(rule[lang].literal, values) .. suffix end
    end
  end
  return text
end

---@param diagnostic vim.Diagnostic
---@param lang? 'en'|'zh'
---@return string
function M.message(diagnostic, lang)
  local text = diagnostic.message
  if type(text) ~= "string" then return text end
  local rules = compiled[source_for(diagnostic)]
  if not rules then return text end
  lang = lang or language()
  lang = lang == "zh" and "zh" or "en"
  -- Keep line breaks, nesting, raw detail, identifiers, URLs and excerpts verbatim.
  return (text:gsub("[^\r\n]+", function(part) return line(part, rules, diagnostic.code, lang) end))
end

local function formatted(diagnostic, original)
  local copy = vim.tbl_extend("force", {}, diagnostic, { message = M.message(diagnostic) })
  if original then return original(copy) end
  return copy.message
end

function M.format(diagnostic)
  return M.message(diagnostic)
end

local function virtual_lines_default(diagnostic)
  return diagnostic.code and (tostring(diagnostic.code) .. ": " .. diagnostic.message) or diagnostic.message
end

local function handler(kind)
  local target = vim.diagnostic.handlers[kind]
  if not target or state.originals[kind] then return end
  state.originals[kind] = target.show
  target.show = function(namespace, bufnr, diagnostics, opts)
    local prepared = vim.tbl_extend("force", {}, opts)
    prepared[kind] = vim.tbl_extend("force", {}, type(opts[kind]) == "table" and opts[kind] or {})
    local previous = prepared[kind].format or (kind == "virtual_lines" and virtual_lines_default or nil)
    prepared[kind].format = function(d) return formatted(d, previous) end
    return state.originals[kind](namespace, bufnr, diagnostics, prepared)
  end
end

local function float_options(first, second)
  local opts = vim.deepcopy((type(first) == "table" and first or second) or {})
  local buf = type(first) == "number" and first or opts.bufnr or vim.api.nvim_get_current_buf()
  local global = vim.diagnostic.config().float
  if type(global) == "function" then global = global(opts.namespace, buf) end
  opts = vim.tbl_extend("keep", opts, type(global) == "table" and global or {})
  return opts, buf
end

local refresh_floats

local function install_float()
  if state.originals.open_float then return end
  state.originals.open_float = vim.diagnostic.open_float
  vim.diagnostic.open_float = function(first, second)
    local opts, buf = float_options(first, second)
    local original = opts.format
    local records = {}
    opts.format = function(d)
      local text = formatted(d, original)
      records[#records + 1] = { diagnostic = vim.deepcopy(d), format = original, text = text }
      for _, related in ipairs(vim.tbl_get(d, "user_data", "lsp", "relatedInformation") or {}) do
        records[#records + 1] = { diagnostic = { source = d.source, message = related.message }, text = related.message }
      end
      return text
    end
    local own_header = opts.header == nil
    if own_header then opts.header = language() == "zh" and "诊断：" or "Diagnostics:" end
    local float_buf, win = state.originals.open_float(buf, opts)
    if float_buf and win then
      state.floats[win] = { buf = float_buf, records = records, header = own_header and opts.header or nil }
      refresh_floats()
    end
    return float_buf, win
  end
end

local function replace_once(text, old, new)
  if old == "" or old == new then return text end
  local first, last = text:find(old, 1, true)
  if first then return text:sub(1, first - 1) .. new .. text:sub(last + 1) end
  return text
end

refresh_floats = function()
  for win, entry in pairs(state.floats) do
    if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= entry.buf then
      state.floats[win] = nil
    else
      local lines = vim.api.nvim_buf_get_lines(entry.buf, 0, -1, false)
      local replacements, edits = {}, {}
      for _, record in ipairs(entry.records) do
        local next_text = formatted(record.diagnostic, record.format)
        if record.text and next_text then
          local before, after = vim.split(record.text, "\n", { plain = true }), vim.split(next_text, "\n", { plain = true })
          if #before == #after then
            for i, text in ipairs(before) do
              if replacements[text] and replacements[text] ~= after[i] then replacements[text] = false
              elseif replacements[text] == nil then replacements[text] = after[i] end
            end
          end
        end
        record.text = next_text
      end
      local ordered = vim.tbl_keys(replacements)
      table.sort(ordered, function(a, b) return #a > #b end)
      for i, text in ipairs(lines) do
        if entry.header and text == entry.header then
          lines[i] = language() == "zh" and "诊断：" or "Diagnostics:"
          if lines[i] ~= text then edits[i - 1] = { 0, #text, #lines[i] } end
        else
          for _, before in ipairs(ordered) do
            if replacements[before] and before ~= "" and text:find(before, 1, true) then
              local first, last = text:find(before, 1, true)
              lines[i] = replace_once(text, before, replacements[before])
              if lines[i] ~= text then edits[i - 1] = { first - 1, last, #replacements[before] } end
              break
            end
          end
        end
      end
      if entry.header then entry.header = language() == "zh" and "诊断：" or "Diagnostics:" end
      if next(edits) then
        -- The native float highlights have byte ranges. Reposition those ranges
        -- together with the translated text; a full buffer replacement would
        -- otherwise collapse the marks or leave suffix highlighting at old offsets.
        local marks = vim.api.nvim_buf_get_extmarks(entry.buf, -1, 0, -1, { details = true })
        local function column(row, col, ending)
          local edit = edits[row]
          if not edit or col <= edit[1] then return col end
          if col >= edit[2] then return col + edit[3] - (edit[2] - edit[1]) end
          return edit[1] + (ending and edit[3] or 0)
        end
        local modifiable = vim.bo[entry.buf].modifiable
        vim.bo[entry.buf].modifiable = true
        for row in pairs(edits) do
          -- nvim_buf_add_highlight(..., -1, ...) uses an internal anonymous
          -- namespace which can be cleared but cannot receive public extmarks.
          vim.api.nvim_buf_clear_namespace(entry.buf, 2147483647, row, row + 1)
          vim.api.nvim_buf_set_lines(entry.buf, row, row + 1, false, { lines[row + 1] })
        end
        for _, mark in ipairs(marks) do
          local details = mark[4]
          if details.hl_group and details.ns_id and (edits[mark[2]] or edits[details.end_row]) then
            local anonymous = details.ns_id == 2147483647
            state.float_ns = state.float_ns or vim.api.nvim_create_namespace("GlowDiagnosticLocaleFloat")
            vim.api.nvim_buf_set_extmark(entry.buf, anonymous and state.float_ns or details.ns_id, mark[2], column(mark[2], mark[3], false), {
              id = not anonymous and mark[1] or nil, end_row = details.end_row,
              end_col = details.end_col and column(details.end_row, details.end_col, true),
              hl_group = details.hl_group, priority = details.priority, hl_eol = details.hl_eol,
              right_gravity = details.right_gravity, end_right_gravity = details.end_right_gravity,
            })
          end
        end
        vim.bo[entry.buf].modifiable = modifiable
      end
    end
  end
end

local function list_key(item)
  return table.concat({ item.bufnr or 0, item.lnum or 0, item.col or 0, item.text or "" }, "\0")
end

local function register_list(id, win, captured)
  if not id or id == 0 then return end
  local query = { id = id, items = 0 }
  local items = (win and vim.fn.getloclist(win, query) or vim.fn.getqflist(query)).items
  local by_index = {}
  for i, item in ipairs(items) do by_index[i] = captured[list_key(item)] end
  local key = (win and ("loc:" .. win .. ":") or "qf:") .. id
  state.lists[key] = { id = id, win = win, records = by_index, originals = vim.deepcopy(items) }
  local what = { id = id, quickfixtextfunc = "v:lua.require'config.platform.diagnostic_locale'.quickfix_text" }
  -- List items retain their original message, positions, IDs and user_data.
  if win then vim.fn.setloclist(win, {}, "a", what) else vim.fn.setqflist({}, "a", what) end
end

local function install_list(name, location)
  if state.originals[name] then return end
  state.originals[name] = vim.diagnostic[name]
  vim.diagnostic[name] = function(options)
    local opts, captured = vim.deepcopy(options or {}), {}
    local win = opts.winnr or 0
    if location and win == 0 then win = vim.api.nvim_get_current_win() end
    if location and not vim.api.nvim_win_is_valid(win) then win = vim.fn.win_getid(win) end
    local previous = opts.format
    opts.format = function(d)
      local text = d.message
      if previous then text = previous(d) end
      if text ~= nil then
        local raw = vim.deepcopy(d)
        local item = { bufnr = d.bufnr, lnum = d.lnum + 1, col = (d.col or 0) + 1, text = text }
        captured[list_key(item)] = { diagnostic = raw, format = previous }
      end
      return text
    end
    state.originals[name](opts)
    local id
    if location then
      id = vim.fn.getloclist(win, { id = 0 }).id
    else
      for nr = 1, vim.fn.getqflist({ nr = "$" }).nr do
        local list = vim.fn.getqflist({ nr = nr, title = 0, id = 0 })
        if list.title == (opts.title or "Diagnostics") then id = list.id; break end
      end
    end
    register_list(id, location and win or nil, captured)
  end
end

function M.quickfix_text(info)
  local entry = state.lists[(info.quickfix == 1 and "qf:" or ("loc:" .. info.winid .. ":")) .. info.id]
  if not entry then return {} end
  local query = { id = info.id, items = 0 }
  local items = (info.quickfix == 1 and vim.fn.getqflist(query) or vim.fn.getloclist(info.winid, query)).items
  local output = {}
  for i = info.start_idx, info.end_idx do
    local item, record = items[i], entry.records[i]
    local text = item.text
    if record and vim.deep_equal(item, entry.originals[i]) then text = formatted(record.diagnostic, record.format) or text end
    local filename = item.bufnr > 0 and vim.api.nvim_buf_get_name(item.bufnr) or ""
    filename = vim.fn.fnamemodify(filename, ":~:.")
    output[#output + 1] = ("%s|%d col %d %s| %s"):format(filename, item.lnum, item.col, item.type, (text:gsub("\n", " ")))
  end
  return output
end

function M.install_plugins()
  if package.loaded["snacks"] and not state.originals.snacks then
    local ok, format = pcall(require, "snacks.picker.format")
    if ok then
      state.originals.snacks = format.diagnostic
      format.diagnostic = function(item, picker)
        local copy = vim.tbl_extend("force", {}, item, {
          item = vim.tbl_extend("force", {}, item.item, { message = M.message(item.item) }),
        })
        return state.originals.snacks(copy, picker)
      end
      local core = package.loaded["snacks.picker.core.picker"]
      if core then
        for _, picker in ipairs(core.get({ tab = false })) do
          if picker.format == state.originals.snacks then picker.format = format.diagnostic end
        end
      end
      local actions = require("snacks.picker.actions")
      for _, name in ipairs({ "qflist", "qflist_all", "loclist" }) do
        local original = actions[name]
        actions[name] = function(picker, ...)
          if picker.opts.format ~= "diagnostic" then return original(picker, ...) end
          local captured, win = {}, name == "loclist" and picker.main or nil
          for _, item in ipairs(picker:items()) do
            if item.item and item.item.message then
              captured[list_key({ bufnr = item.buf, lnum = item.pos[1], col = item.pos[2] + 1, text = item.comment })] = {
                diagnostic = vim.deepcopy(item.item),
              }
            end
          end
          local result = original(picker, ...)
          local id = (win and vim.fn.getloclist(win, { id = 0 }) or vim.fn.getqflist({ id = 0 })).id
          register_list(id, win, captured)
          return result
        end
      end
    end
  end
  if package.loaded["trouble"] and not state.originals.trouble then
    local format = require("trouble.format")
    local original = format.formatters.message
    state.originals.trouble = original or true
    format.formatters.message = function(ctx)
      if ctx.item.source == "diagnostics" and type(ctx.item.item) == "table" then
        return { text = M.message(ctx.item.item) }
      end
      return original and original(ctx) or { text = tostring(ctx.item.message or "") }
    end
  end
end

function M.refresh()
  M.install_plugins()
  -- show() reads the original cache; do not set(), publish or fake DiagnosticChanged.
  vim.diagnostic.show()
  refresh_floats()
  local core = package.loaded["snacks.picker.core.picker"]
  if core then
    for _, picker in ipairs(core.get({ tab = false })) do
      if picker.opts.format == "diagnostic" then picker.list.dirty = true; picker.list:render() end
    end
  end
  if package.loaded["trouble.api"] then
    for _, view in ipairs(require("trouble.api")._find({ mode = "diagnostics" })) do
      for _, section in ipairs(view.sections) do
        for _, item in ipairs(section.items or {}) do
          if item.source == "diagnostics" then
            for key in pairs(item.cache.data or {}) do
              if key:match("^render:") then item.cache[key] = nil end
            end
          end
        end
      end
      view:refresh()
    end
  end
  for _, entry in pairs(state.lists) do
    local what = { id = entry.id, quickfixtextfunc = "v:lua.require'config.platform.diagnostic_locale'.quickfix_text" }
    if entry.win then
      if vim.api.nvim_win_is_valid(entry.win) then pcall(vim.fn.setloclist, entry.win, {}, "a", what) end
    else pcall(vim.fn.setqflist, {}, "a", what) end
  end
end

function M.setup()
  handler("virtual_text")
  handler("virtual_lines")
  install_float()
  install_list("setqflist", false)
  install_list("setloclist", true)
  M.install_plugins()
  local group = vim.api.nvim_create_augroup("GlowDiagnosticLocale", { clear = true })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "GlowLanguageChanged", callback = function() state.impl.refresh() end })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "LazyLoad", callback = function() state.impl.install_plugins() end })
end

return M
