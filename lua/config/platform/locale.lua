-- Live product UI language. This preference does not change keyboard/input sources.
local M = {}
local state_dir = vim.fn.stdpath("state") .. "/preferences"
local lang_file = state_dir .. "/language.txt"
local legacy_file = vim.fn.stdpath("config") .. "/archive/legacy/lang_setting.txt"
local locales = { en = "en_US.UTF-8", zh = "zh_CN.UTF-8" }
local commands = {}
local function language(value)
  if type(value) ~= "string" then return nil end
  if value:lower():match("^zh") then return "zh" end
  if value:lower():match("^en") then return "en" end
end
function M.current()
  return language(vim.g.glow_ui_language) or language(vim.env.LANG) or "en"
end
function M.reload_messages()
  local catalog = require("config.platform.locale_catalog").new(M.current, { reload = true })
  M.t, M.known = catalog.t, catalog.known
end
M.reload_messages()
local function which_key_text(text) return M.t(text) end
function M.setup_which_key(opts)
  require("config.platform.which_key_locale").setup()
  opts.replace = opts.replace or {}
  opts.replace.desc = opts.replace.desc or {}
  if not vim.tbl_contains(opts.replace.desc, which_key_text) then
    table.insert(opts.replace.desc, which_key_text)
  end
  return opts
end
function M.input(opts, callback)
  opts = vim.tbl_extend("force", opts or {}, { prompt = M.t(opts and opts.prompt) })
  return vim.ui.input(opts, callback)
end
function M.select(items, opts, callback)
  opts = vim.tbl_extend("force", opts or {}, { prompt = M.t(opts and opts.prompt) })
  -- Selection values and format_item output may contain user names/paths.
  -- Callers translate only their own static menu labels explicitly.
  return vim.ui.select(items, opts, callback)
end
function M.command(name, callback, opts)
  commands[name] = { callback = callback, opts = vim.deepcopy(opts or {}) }
  local translated = vim.tbl_extend("force", opts or {}, { desc = M.t(opts and opts.desc) })
  return vim.api.nvim_create_user_command(name, callback, translated)
end
local function refresh()
  for name, value in pairs(commands) do
    local opts = vim.tbl_extend("force", value.opts, { desc = M.t(value.opts.desc), force = true })
    vim.api.nvim_create_user_command(name, value.callback, opts)
  end
  local dashboard = package.loaded["snacks.dashboard"]
  if dashboard and dashboard.update then dashboard.update() end
  require("config.platform.locale_ui").refresh(M)
  vim.api.nvim_exec_autocmds("User", { pattern = "GlowLanguageChanged", modeline = false, data = { language = M.current() } })
  vim.cmd("redraw")
end
function M.save_language_settings()
  vim.fn.mkdir(state_dir, "p")
  vim.fn.writefile({ locales[M.current()] }, lang_file)
end
function M.set_lang(value, opts)
  local chosen = assert(language(value), "Language must be en or zh")
  vim.g.glow_ui_language = chosen
  -- Preserve the existing environment contract; UI localization no longer relies on it.
  vim.env.LANG, vim.env.LC_ALL = locales[chosen], locales[chosen]
  opts = opts or {}
  if opts.save ~= false then M.save_language_settings() end
  refresh()
  if not opts.silent then vim.notify(M.t("Language switched to English."), vim.log.levels.INFO) end
  return chosen
end
function M.toggle_lang()
  return M.set_lang(M.current() == "en" and "zh" or "en")
end
function M.load_language_settings()
  if vim.fn.filereadable(lang_file) == 0 and vim.fn.filereadable(legacy_file) == 1 then
    vim.fn.mkdir(state_dir, "p")
    vim.fn.writefile(vim.fn.readfile(legacy_file), lang_file)
  end
  local saved = vim.fn.filereadable(lang_file) == 1 and vim.fn.readfile(lang_file)[1]
  local chosen = language(saved) or M.current()
  vim.g.glow_ui_language = chosen
  vim.env.LANG, vim.env.LC_ALL = locales[chosen], locales[chosen]
end
function M.audit()
  local missing, seen = {}, {}
  for _, mode in ipairs({ "n", "x", "i", "t" }) do
    for _, map in ipairs(vim.list_extend(vim.api.nvim_get_keymap(mode), vim.api.nvim_buf_get_keymap(0, mode))) do
      if map.desc and map.lhs:sub(1, 1) == (vim.g.mapleader or "\\") and not M.known(map.desc) and not seen[map.desc] then
        seen[map.desc] = true
        missing[#missing + 1] = { lhs = map.lhs, desc = map.desc }
      end
    end
  end
  table.sort(missing, function(a, b) return a.desc < b.desc end)
  return missing
end
M.load_language_settings()
M.command("GlowLanguage", function(opts)
  if opts.args == "" or opts.args == "toggle" then M.toggle_lang() else M.set_lang(opts.args) end
end, { nargs = "?", desc = "Toggle Language", complete = function() return { "en", "zh", "toggle" } end })
local language_key
function M.setup()
  -- glass.setup can load this module before LazyVim configures mapleader.
  -- Rebind only this module's own earlier key when the final leader is known.
  local lhs = (vim.g.mapleader or " ") .. "<C-l>"
  -- Retire the old pre-LazyVim backslash alias; retain unrelated user mappings.
  if lhs ~= "\\<C-l>" then
    local old = vim.fn.maparg("\\<C-l>", "n", false, true)
    local source = type(old.callback) == "function" and debug.getinfo(old.callback, "S").source or ""
    if source:match("config[/\\]platform[/\\]locale%.lua$") then
      pcall(vim.keymap.del, "n", "\\<C-l>")
    end
  end
  if language_key and language_key ~= lhs then
    local old = vim.fn.maparg(language_key, "n", false, true)
    if old.callback == M.toggle_lang then pcall(vim.keymap.del, "n", language_key) end
  end
  vim.keymap.set("n", lhs, M.toggle_lang, { noremap = true, silent = true, desc = "Toggle Language" })
  language_key = lhs
  require("config.platform.locale_ui").setup(M)
  require("config.platform.diagnostic_locale").setup()
  require("config.platform.notebook_chrome_locale").setup()
  require("config.platform.vimtex_locale").setup()
  require("config.platform.native_menu_locale").setup(M)
end
M.setup()
return M
