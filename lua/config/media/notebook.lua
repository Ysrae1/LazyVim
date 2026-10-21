local function T(text) return require("config.platform.locale").t(text) end
-- Static .ipynb viewer. Reading, writes and refresh are asynchronous; no kernel runs.
local M = {}
local uv = vim.uv or vim.loop
local sessions, configured, sequence = {}, false, 0
local max_bytes, max_cells = 32 * 1024 * 1024, 4000
local asset_dir = vim.fs.joinpath(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)), "assets")
local assets

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.WARN, { title = T("Notebook Preview") })
end

local function escape(value)
  return tostring(value):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
end

local function load_assets()
  if assets then return assets end
  assets = {}
  for _, name in ipairs({ "markdown-it.min.js", "katex.min.js", "katex-fonts.min.css", "notebook.css", "notebook.js" }) do
    local file, err = io.open(vim.fs.joinpath(asset_dir, name), "rb")
    if not file then assets = nil; error(T("Missing local Notebook resource: ") .. tostring(err)) end
    assets[name] = file:read("*a")
    file:close()
  end
  return assets
end

-- Exposed for fixture tests and callers that already have a parsed notebook.
function M.render(document, path)
  if type(document) ~= "table" or document.nbformat ~= 4 or type(document.cells) ~= "table" then
    error(T("An .ipynb file in nbformat 4 is required."))
  end
  if #document.cells > max_cells then error(T("This Notebook exceeds the preview limit of 4,000 cells.")) end
  for _, cell in ipairs(document.cells) do
    if type(cell) ~= "table" or type(cell.cell_type) ~= "string" or (type(cell.source) ~= "string" and type(cell.source) ~= "table") then
      error(T("The Notebook contains an invalid cell."))
    end
  end
  local a = load_assets()
  local payload = vim.json.encode(document):gsub("<", "\\u003c"):gsub("\226\128\168", "\\u2028"):gsub("\226\128\169", "\\u2029")
  local function script(value) return "<script>" .. value:gsub("</script", "<\\/script") .. "</script>" end
  return table.concat({
    '<!doctype html><html lang="' .. (require("config.platform.locale").current() == "zh" and "zh-CN" or "en") .. '"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">',
    '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; script-src \'unsafe-inline\'; style-src \'unsafe-inline\'; font-src data:; img-src data: file:; frame-src \'self\'; base-uri file:; form-action \'none\';">',
    '<base href="', escape(vim.uri_from_fname(vim.fs.dirname(path)) .. "/"), '"><title>', escape(vim.fs.basename(path)), '</title><style>',
    a["katex-fonts.min.css"], a["notebook.css"], '</style></head><body><header><h1>', escape(vim.fs.basename(path)),
    '</h1><div id="count"></div><p class="notice">', escape(T("View saved cells and outputs only. Saving the source refreshes this preview. No kernel is connected, no code is executed, and scripts in HTML outputs are disabled.")), '</p></header><main id="cells"></main>',
    '<script type="application/json" id="notebook-data">', payload, '</script>',
    '<script type="application/json" id="notebook-ui">', vim.json.encode({ png = T("Saved PNG chart"), svg = T("Saved SVG chart"), html = T("Saved static HTML output (scripts disabled)"), empty = T("This output has no saved static content to display."), code = T("Code"), raw = T("Raw text"), count = T("%d cells · Saved outputs") }):gsub("<", "\\u003c"), '</script>',
    script(a["markdown-it.min.js"]), script(a["katex.min.js"]), script(a["notebook.js"]), '</body></html>',
  })
end

function M.supports(path)
  return type(path) == "string" and path:lower():match("%.ipynb$") ~= nil
end

local function close(session)
  if session.closed then return end
  session.closed, session.generation = true, session.generation + 1
  sessions[session.id] = nil
  vim.fn.delete(session.dir, "rf")
  if session.opts.on_close then pcall(session.opts.on_close) end
end

local function fail(session, generation, err)
  vim.schedule(function()
    if session.closed or session.generation ~= generation then return end
    notify(T("Unable to preview Notebook: ") .. tostring(err))
    if not session.opened then close(session) end
  end)
end

local function show(session)
  if session.closed or not session.ready then return end
  if not vim.api.nvim_tabpage_is_valid(session.origin_tab) or not vim.api.nvim_win_is_valid(session.origin_win) then
    close(session)
    return
  end
  if vim.api.nvim_get_current_tabpage() ~= session.origin_tab then return end
  session.ready = false
  local preview = require("config.media.preview")
  local opts = vim.tbl_extend("force", session.opts, {
    kind = "web", title = vim.fs.basename(session.path) .. T(" · Saved Outputs"), command = session.opts.command or "rightbelow vnew",
    win = session.origin_win, on_close = function() close(session) end,
  })
  local ok, result = pcall(preview.open, session.html, opts)
  if not ok or result == false then
    notify(T("Unable to open Notebook web preview: ") .. tostring(ok and T("This GUI does not provide an embedded WebView.") or result))
    close(session)
  else session.opened = true end
end

local function write_html(session, generation, html)
  local temporary = session.html .. "." .. generation .. ".tmp"
  uv.fs_open(temporary, "w", 384, function(open_err, fd)
    if open_err then fail(session, generation, open_err); return end
    local function finish(err)
      uv.fs_close(fd, function()
        if err or session.closed or session.generation ~= generation then
          uv.fs_unlink(temporary, function() end)
          if err then fail(session, generation, err) end
          return
        end
        uv.fs_rename(temporary, session.html, function(rename_err)
          if rename_err then fail(session, generation, rename_err); return end
          vim.schedule(function()
            if session.closed or session.generation ~= generation then return end
            local preview = require("config.media.preview")
            if session.opened then
              preview.refresh_source(session.html)
            else
              session.ready = true
              show(session)
            end
          end)
        end)
      end)
    end
    local offset = 0
    local function write()
      uv.fs_write(fd, html:sub(offset + 1), offset, function(err, count)
        if err or not count or count == 0 then finish(err or T("Unable to write the preview file.")); return end
        offset = offset + count
        if offset < #html then write() else finish() end
      end)
    end
    write()
  end)
end

local function refresh(session)
  if session.closed then return end
  session.generation = session.generation + 1
  local generation = session.generation
  uv.fs_open(session.path, "r", 0, function(open_err, fd)
    if open_err then fail(session, generation, open_err); return end
    uv.fs_fstat(fd, function(stat_err, stat)
      if stat_err or not stat or stat.type ~= "file" or stat.size > max_bytes then
        uv.fs_close(fd, function() end)
        fail(session, generation, stat_err or T("Notebook preview supports files up to 32 MiB."))
        return
      end
      uv.fs_read(fd, stat.size + 1, 0, function(read_err, data)
        uv.fs_close(fd, function() end)
        if read_err or not data then fail(session, generation, read_err or T("Read failed.")); return end
        if #data > max_bytes then fail(session, generation, T("The Notebook exceeds 32 MiB.")); return end
        vim.schedule(function()
          if session.closed or session.generation ~= generation then return end
          local ok, result = pcall(function() return M.render(vim.json.decode(data), session.path) end)
          if not ok then fail(session, generation, result); return end
          write_html(session, generation, result)
        end)
      end)
    end)
  end)
end

function M.open(path, opts)
  opts = opts or {}
  if not M.supports(path) then notify(T("Select an .ipynb file.")); return false end
  M.setup()
  sequence = sequence + 1
  local dir = vim.fn.tempname() .. "-glow-notebook"
  vim.fn.mkdir(dir, "p", 448)
  local session = { id = sequence, path = uv.fs_realpath(path) or vim.fs.normalize(vim.fn.fnamemodify(path, ":p")), dir = dir,
    html = vim.fs.joinpath(dir, "index.html"), opts = opts, generation = 0,
    origin_tab = vim.api.nvim_get_current_tabpage(), origin_win = opts.win or vim.api.nvim_get_current_win() }
  sessions[session.id] = session
  refresh(session)
  return true
end

function M.from_tree(event)
  if not vim.g.neovide or not M.supports(event.path) then return end
  local win, is_tree = require("neo-tree.utils").get_appropriate_window(event.state)
  local cmd = event.open_cmd or "edit"
  local split = ({ split = "split", sp = "split", vsplit = "vsplit", vs = "vsplit", tabnew = "tabnew", tabedit = "tabnew" })[cmd]
  if not split and is_tree then split = event.state.current_position == "right" and "leftabove vnew" or "rightbelow vnew" end
  M.open(event.path, { win = win, command = split })
  return { handled = true }
end

function M.setup()
  if configured then return end
  configured = true
  local group = vim.api.nvim_create_augroup("GlowNotebook", { clear = true })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "GlowLanguageChanged", callback = function()
    for _, session in pairs(sessions) do refresh(session) end
  end })
  vim.api.nvim_create_autocmd("BufWritePost", { group = group, pattern = "*.ipynb", callback = function(event)
    local path = uv.fs_realpath(event.file) or vim.fs.normalize(vim.fn.fnamemodify(event.file, ":p"))
    for _, session in pairs(sessions) do if session.path == path then refresh(session) end end
  end })
  vim.api.nvim_create_autocmd({ "TabEnter", "WinClosed" }, { group = group, callback = function()
    for _, session in pairs(sessions) do show(session) end
  end })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = function()
    for _, session in pairs(sessions) do close(session) end
  end })
  require("config.platform.locale").command("GlowNotebookPreview", function(args)
    M.open(args.args ~= "" and args.args or vim.api.nvim_buf_get_name(0))
  end, { nargs = "?", complete = "file", desc = T("Preview Notebook Cells and Saved Outputs") })
end

return M
