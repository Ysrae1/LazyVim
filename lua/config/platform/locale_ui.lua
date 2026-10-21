-- Localize product chrome at its rendering boundary. Never rewrite user buffers,
-- file names, shell output, diagnostics from tools, or arbitrary picker entries.
local M = {}
local installed, provider = false, nil
local function L() return provider or require("config.platform.locale") end
local function T(text) return L().t(text) end

local picker_titles = {
  autocmds = "Autocmds", buffers = "Buffers", explorer = "Explorer", cliphist = "Cliphist",
  colorschemes = "Colorschemes", command_history = "Command History", commands = "Commands",
  diagnostics = "Diagnostics", diagnostics_buffer = "Diagnostics", files = "Files",
  git_branches = "Git Branches", git_files = "Git Files", git_grep = "Git Grep", git_log = "Git Log",
  git_log_file = "Git Log File", git_log_line = "Git Log Line", git_stash = "Git Stash",
  git_status = "Git Status", git_diff = "Git Diff", grep = "Grep", grep_buffers = "Grep Buffers",
  grep_word = "Grep Word", help = "Help", highlights = "Highlights", icons = "Icons", jumps = "Jumps",
  keymaps = "Keymaps", lazy = "Lazy", lines = "Lines", loclist = "Loclist", lsp_config = "Lsp Config",
  lsp_declarations = "Lsp Declarations", lsp_definitions = "Lsp Definitions", lsp_implementations = "Lsp Implementations",
  lsp_incoming_calls = "Lsp Incoming Calls", lsp_outgoing_calls = "Lsp Outgoing Calls", lsp_references = "Lsp References",
  lsp_symbols = "Lsp Symbols", lsp_workspace_symbols = "Lsp Workspace Symbols", lsp_type_definitions = "Lsp Type Definitions",
  man = "Man", marks = "Marks", notifications = "Notifications", pickers = "Pickers", picker_actions = "Picker Actions",
  picker_format = "Picker Format", picker_layouts = "Picker Layouts", picker_preview = "Picker Preview",
  projects = "Projects", qflist = "Quickfix", recent = "Recent", registers = "Registers", scratch = "Scratch",
  search_history = "Search History", select = "Select", smart = "Smart", spelling = "Spelling", tags = "Tags",
  treesitter = "Treesitter", undo = "Undo", zoxide = "Zoxide", todo_comments = "Todo Comments",
}
M.picker_titles = picker_titles

local function picker_windows(picker)
  local result, seen = {}, {}
  for _, collection in ipairs({ { picker.layout.root }, picker.layout.wins, picker.layout.box_wins }) do
    for _, win in pairs(collection or {}) do
      if not seen[win] then result[#result + 1], seen[win] = win, true end
    end
  end
  return result
end

-- Keep provider templates rather than translating rendered file names. The
-- native border uses display cells for centering; symmetrical padding avoids
-- Snacks' byte-oriented extra space after CJK labels shifting the visible text.
function M.prepare_picker_titles(picker)
  local original = picker._glow_ui_title or picker.opts._glow_ui_source_title
  if original then picker.title = T(original) end
  for _, name in ipairs({ "Prompt", "Preview", "Results" }) do
    vim.api.nvim_set_hl(0, "GlowPicker" .. name .. "Title", { link = "Telescope" .. name .. "Title", default = true })
  end
  if not picker.preview.title or picker.preview.title == "" then
    local item = picker.preview.item
    if item and item.file then picker.preview.title = item.title or vim.fn.fnamemodify(item.file, ":t") end
  end
  for _, win in ipairs(picker_windows(picker)) do
    if win.opts.title then
      local original_template = win.meta._glow_title_template or win.meta.title_tpl or win.opts.title
      win.meta._glow_title_template = vim.deepcopy(original_template)
      local chunks = type(original_template) == "string" and { { original_template, "FloatTitle" } }
        or vim.deepcopy(original_template)
      local role
      for _, chunk in ipairs(chunks) do
        local template = chunk[1]
        if template:find("{preview", 1, true) then role = "Preview"
        elseif template:find("{title}", 1, true) or template:find("{source}", 1, true) then role = "Prompt"
        elseif vim.trim(template) == "Results" or vim.trim(template) == "结果" then role = "Results" end
        if template == "{preview}" or template == "{preview:Preview}" then
          chunk[1] = "{preview:" .. T("Preview") .. "}"
        elseif not template:find("{", 1, true) then
          chunk[1] = T(template)
        end
      end
      if role then
        win.meta._glow_title_role = role
        for _, chunk in ipairs(chunks) do chunk[2] = "GlowPicker" .. role .. "Title" end
        win.meta.title_tpl, win.opts.title_pos = chunks, "center"
      end
    end
  end
end

function M.finish_picker_titles(picker)
  for _, win in ipairs(picker_windows(picker)) do
    local role = win.meta._glow_title_role
    if role and type(win.opts.title) == "table" then
      local chunks, gap = {}, false
      local token = "GlowPicker" .. role .. "Title"
      for _, source in ipairs(win.opts.title) do
        local chunk = vim.deepcopy(source)
        if chunk[2] == "FloatTitle" or chunk[2] == token then
          chunk[2] = token
        end
        -- Upstream flag chunks contain their own padding plus a separator;
        -- collapse only whitespace across chunk boundaries, not inside a file
        -- name or user-provided title. Keep each semantic flag highlight.
        local left, body, right = chunk[1]:match("^(%s*)(.-)(%s*)$")
        if body ~= "" then
          if #chunks > 0 and (gap or left ~= "") then chunks[#chunks + 1] = { " ", token } end
          chunk[1], chunks[#chunks + 1] = body, chunk
          gap = right ~= ""
        else
          gap = gap or chunk[1] ~= ""
        end
      end
      if #chunks > 0 then
        table.insert(chunks, 1, { " ", token })
        chunks[#chunks + 1] = { " ", token }
      end
      win:set_title(chunks, "center")
    end
  end
end

function M.product_buffer_name(name)
  if type(name) ~= "string" then return name end
  local source, id = name:match("^neo%-tree ([%w_]+) %[(%d+)%]$")
  if not source then return name end
  local titles = { filesystem = "NeoTree File Browser", buffers = "NeoTree buffer List", git_status = "NeoTree Git Status" }
  return titles[source] and (T(titles[source]) .. " [" .. id .. "]") or name
end

local function setup_snacks()
  if not package.loaded.snacks then return end
  local picker = require("snacks.picker.core.picker")
  if not picker._glow_ui_locale_hooks then
    local new, update_titles = picker.new, picker.update_titles
    -- Upgrade only our previous known wrappers; no plugin reload or new picker.
    if picker._glow_ui_locale then
      local function unwrap(callback, wanted)
        for index = 1, 20 do
          local name, value = debug.getupvalue(callback, index)
          if not name then break end
          if name == wanted and type(value) == "function" then return value end
        end
        error("Cannot safely upgrade the previous picker locale hook: " .. wanted)
      end
      new, update_titles = unwrap(new, "new"), unwrap(update_titles, "update_titles")
    end
    picker._glow_ui_locale_hooks = { new = new, update_titles = update_titles }
    picker._glow_ui_locale = true
    picker.new = function(opts)
      opts = vim.tbl_extend("force", opts or {}, {})
      -- Explicit titles may contain paths. Exact catalog matches are safe;
      -- default source titles come from the known, pinned picker catalog.
      local original = opts.title or picker_titles[opts.source]
      if original then opts.title = T(original) end
      opts._glow_ui_source_title = original
      local result = new(opts)
      result._glow_ui_title = original
      return result
    end
    picker.update_titles = function(self, ...)
      local active = require("config.platform.locale_ui")
      active.prepare_picker_titles(self)
      local result = vim.F.pack_len(update_titles(self, ...))
      active.finish_picker_titles(self)
      return vim.F.unpack_len(result)
    end
  end
  local win = require("snacks.win")
  if not win._glow_caption_locale then
    win._glow_caption_locale = setmetatable({}, { __mode = "k" })
    local win_opts = win.win_opts
    win.win_opts = function(self, ...)
      local opts = win_opts(self, ...)
      local translated = false
      for _, field in ipairs({ "title", "footer" }) do
        if type(opts[field]) == "table" then
          local chunks = vim.deepcopy(opts[field])
          for _, chunk in ipairs(chunks) do
            -- Scratch names determine persistent file identities, so translate
            -- only the rendered caption; never change opts.name or metadata.
            if chunk[2] == "SnacksScratchTitle" or chunk[2] == "SnacksFooterDesc" then
              local before, text, after = chunk[1]:match("^(%s*)(.-)(%s*)$")
              local name, count = text:match("^(Scratch)( %d+)$")
              chunk[1] = before .. T(name or text) .. (count or "") .. after
              translated = true
            end
          end
          opts[field] = chunks
        end
      end
      if translated then win._glow_caption_locale[self] = true end
      return opts
    end
  end
  local input = require("snacks.input")
  if not input._glow_ui_locale then
    input._glow_ui_locale = true
    local input_fn = input.input
    input.input = function(opts, callback)
      opts = vim.tbl_extend("force", opts or {}, {})
      opts.prompt = T(opts.prompt or "Input")
      return input_fn(opts, callback)
    end
  end
  local notifier = require("snacks.notifier")
  if not notifier._glow_ui_locale then
    notifier._glow_ui_locale = true
    local history = notifier.show_history
    notifier.show_history = function(...)
      local style = Snacks.config.styles.notification_history
      if style then style.title = " " .. T("Notification History") .. " " end
      return history(...)
    end
  end
end

local telescope_title_fields = { prompt = "prompt_title", results = "results_title", preview = "preview_title" }

function M.prepare_telescope_titles(picker)
  local dynamic = require("telescope.config").values.dynamic_preview_title
  picker._glow_ui_titles = picker._glow_ui_titles or {}
  for section, field in pairs(telescope_title_fields) do
    if not (section == "preview" and dynamic) and type(picker[field]) == "string" then
      picker._glow_ui_titles[field] = picker._glow_ui_titles[field] or picker[field]
      picker[field] = T(picker._glow_ui_titles[field])
    end
  end
  local previewer = picker.previewer
  if previewer and type(previewer.title) == "function" and not previewer._glow_ui_title then
    local title = previewer.title
    previewer._glow_ui_title = title
    previewer.title = function(self, entry, dynamic_title)
      local value = title(self, entry, dynamic_title)
      -- Dynamic titles are user file names. Static previewer chrome is owned by
      -- the provider, including the title recomputed after each selection.
      return dynamic_title and value or T(value)
    end
  end
end

local function setup_telescope()
  local pickers = package.loaded["telescope.pickers"]
  if not pickers or pickers._glow_ui_locale then return end
  pickers._glow_ui_locale = true
  local new = pickers._Picker.new
  pickers._Picker.new = function(self, opts)
    local result = new(self, opts)
    require("config.platform.locale_ui").prepare_telescope_titles(result)
    local window_options = result.get_window_options
    result.get_window_options = function(this, ...)
      require("config.platform.locale_ui").prepare_telescope_titles(this)
      return window_options(this, ...)
    end
    return result
  end
end

local function refresh_telescope()
  local state = package.loaded["telescope.state"]
  if not state then return end
  for _, buf in ipairs(state.get_existing_prompt_bufnrs()) do
    local picker = state.get_status(buf).picker
    if picker and picker.layout then
      M.prepare_telescope_titles(picker)
      for section, field in pairs(telescope_title_fields) do
        local window = picker.layout[section]
        if window and window.border and picker._glow_ui_titles[field] then
          window.border:change_title(picker[field])
        end
      end
    end
  end
end

-- A hot-update boundary confined to picker chrome: no language preference,
-- document, Notebook kernel, selection, query or finder is replaced.
function M.refresh_pickers(locale)
  provider = locale or provider
  setup_snacks()
  setup_telescope()
  local picker = package.loaded["snacks.picker.core.picker"]
  if picker then
    for _, active in ipairs(picker.get({ tab = false })) do active:update_titles() end
  end
  refresh_telescope()
  local materials = package.loaded["config.appearance.popups"]
  if materials then materials.apply() end
end

local function setup_statusline()
  local utils = package.loaded["nvchad.stl.utils"]
  if not utils then return end
  if not utils._glow_ui_modes then
    utils._glow_ui_modes = vim.deepcopy(utils.modes)
    local file = utils.file
    utils.file = function(...)
      local result = file(...)
      if vim.api.nvim_buf_get_name(utils.stbufnr()) == "" then result[2] = T("Empty")
      else result[2] = M.product_buffer_name(result[2]) end
      return result
    end
  end
  for mode, original in pairs(utils._glow_ui_modes) do
    if utils.modes[mode] then utils.modes[mode][1] = T(original[1]) end
  end
end

-- Adopt already-open provider captions when this module is hot-updated.
-- Only known provider chrome groups are touched; arbitrary window/file titles
-- and persistent Scratch names remain outside the translation boundary.
local function refresh_existing_captions()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local config, changes = vim.api.nvim_win_get_config(win), {}
    local sources = (vim.w[win].glow_popup_material or {}).caption_sources or {}
    for _, field in ipairs({ "title", "footer" }) do
      if type(config[field]) == "table" then
        local chunks, changed = vim.deepcopy(config[field]), false
        for _, chunk in ipairs(chunks) do
          local group = type(chunk[2]) == "number" and vim.api.nvim_get_hl_name_by_id(chunk[2]) or chunk[2]
          local names = sources[group] or { group }
          if vim.tbl_contains(names, "SnacksScratchTitle") or vim.tbl_contains(names, "SnacksFooterDesc") then
            local text = chunk[1]
            local left, body, right = text:match("^(%s*)(.-)(%s*)$")
            local name, count = body:match("^(Scratch)( %d+)$")
            if not name then name, count = body:match("^(临时笔记)( %d+)$") end
            -- Chinese "关闭" also means Disabled in a toggle. This is a known
            -- footer action, so retain its action meaning across hot refreshes.
            local canonical = { ["关闭"] = "close", ["隐藏"] = "hide", ["运行当前 buffer"] = "Source buffer",
              ["重置 buffer"] = "Reset buffer", ["临时笔记"] = "Scratch" }
            local source = canonical[name or body] or name or body
            chunk[1] = left .. T(source) .. (count or "") .. right
            changed = changed or chunk[1] ~= text
          end
        end
        if changed then changes[field], changes[field .. "_pos"] = chunks, config[field .. "_pos"] end
      end
    end
    if next(changes) then vim.api.nvim_win_set_config(win, changes) end
  end
end

function M.refresh(locale)
  provider = locale or provider
  setup_snacks()
  setup_telescope()
  setup_statusline()
  local picker = package.loaded["snacks.picker.core.picker"]
  if picker then
    for _, active in ipairs(picker.get({ tab = false })) do active:update_titles() end
  end
  refresh_existing_captions()
  refresh_telescope()
  local win = package.loaded["snacks.win"]
  if win and win._glow_caption_locale then
    for active in pairs(win._glow_caption_locale) do
      if active:valid() then active:update() end
    end
    local materials = package.loaded["config.appearance.popups"]
    if materials then materials.apply() end
  end
  local notebook = package.loaded["config.media.notebook_edit"]
  if notebook and notebook.refresh_titles then notebook.refresh_titles() end
  local tree = package.loaded["neo-tree.ui.renderer"]
  if tree then
    local manager = require("neo-tree.sources.manager")
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neo-tree" then
        local state = manager.get_state_for_window(win)
        if state and state.tree then tree.redraw(state) end
      end
    end
  end
  vim.cmd("redrawstatus")
  vim.cmd("redrawtabline")
end

function M.setup(locale)
  provider = locale or provider
  if not installed then
    installed = true
    local group = vim.api.nvim_create_augroup("GlowProductLocale", { clear = true })
    vim.api.nvim_create_autocmd("User", { group = group, pattern = "LazyLoad", callback = function()
      setup_snacks()
      setup_telescope()
      setup_statusline()
    end })
  end
  setup_snacks()
  setup_telescope()
  setup_statusline()
end
return M
