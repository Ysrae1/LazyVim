-- Native Notebook editing: Jupytext owns .ipynb serialization; Molten owns
-- execution and output. Opening a document never starts a kernel or runs code.
local M = {}
local sessions, configured = {}, false
local namespace = vim.api.nvim_create_namespace("glow.notebook.cells")
local label_signatures = {}
local label_icons = {}
local uv = vim.uv or vim.loop

function M.status(buf)
  local session = sessions[buf or vim.api.nvim_get_current_buf()]
  return session and { kernel = session.kernel, ready = session.ready == true,
    starting = session.starting == true, owned = session.owned == true, save_error = session.save_error == true,
    kernel_name = session.selected and session.selected.name, display_name = session.selected and session.selected.display_name,
    environment = session.selected and session.selected.executable } or nil
end

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.WARN, { title = "Notebook" })
end

function M.supports(path)
  return type(path) == "string" and path:lower():match("%.ipynb$") ~= nil
end

local function execute(command, args, bang)
  if (command == "MoltenImportOutput" or command == "MoltenExportOutput") and args and args[1] then
    local definition = vim.api.nvim_get_commands({ builtin = false })[command]
    -- Neovim's remote-plugin bootstrap replays <q-args> as an Ex string on its
    -- very first invocation. Escape the file only across that bootstrap; the
    -- registered command thereafter accepts exact structured argv directly.
    if definition and definition.definition:find("CommandBootstrap", 1, true) then
      -- These are generic remote-command arguments, not Ex filename syntax:
      -- fnameescape() also escapes apostrophes/$/% that <f-args> keeps literal.
      args = { args[1]:gsub("([\\ \t])", "\\%1"), args[2] }
    end
  end
  return vim.cmd({ cmd = command, args = args or {}, bang = bang or false })
end

local function in_buffer(buf, callback)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then return end
  return vim.api.nvim_buf_call(buf, callback)
end

local function local_kernels()
  if vim.fn.exists("*MoltenRunningKernels") == 0 then return {} end
  local ok, kernels = pcall(vim.fn.MoltenRunningKernels, true)
  return ok and kernels or {}
end

function M.cells(buf)
  local lines = vim.api.nvim_buf_get_lines(buf or 0, 0, -1, false)
  local cells = {}
  for index, line in ipairs(lines) do
    if line:match("^# %%%%") then
      cells[#cells + 1] = { header = index, first = index + 1,
        kind = line:match("%[markdown%]") and "markdown" or line:match("%[raw%]") and "raw" or "code" }
    end
  end
  if #cells == 0 then cells[1] = { header = 0, first = 1, kind = "code" } end
  for index, cell in ipairs(cells) do
    cell.last = (cells[index + 1] and cells[index + 1].header - 1) or #lines
    cell.finish = cell.last
    while cell.first <= cell.last and lines[cell.first]:match("^%s*$") do cell.first = cell.first + 1 end
    while cell.last >= cell.first and lines[cell.last]:match("^%s*$") do cell.last = cell.last - 1 end
  end
  return cells
end

local function current_cell(buf)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local selected
  for _, cell in ipairs(M.cells(buf)) do
    if row >= math.max(1, cell.header) then selected = cell else break end
  end
  return selected
end

function M.content_line(cell, line_count)
  if cell.first <= cell.last then return cell.first end
  return math.max(1, math.min(cell.header + 1, cell.finish, line_count))
end

function M.label_chunks(kind, language, playing)
  local filetype = kind == "markdown" and "markdown" or kind == "raw" and "text" or language
  if not label_icons[filetype] then
    local ok, icons = pcall(require, "nvim-web-devicons")
    local icon = ok and icons.get_icon_by_filetype(filetype, { default = false }) or nil
    label_icons[filetype] = icon or ({ python = "", markdown = "", text = "" })[filetype] or ""
  end
  local group = kind == "markdown" and "GlowNotebookMarkdown" or kind == "raw" and "GlowNotebookRaw" or "GlowNotebookLanguage"
  local chunks = {}
  if kind == "code" then
    -- This font's Material Design symbols share the capsule caps' ink center;
    -- generic Unicode play/return fell back to fonts with different baselines.
    vim.list_extend(chunks, { { "", "GlowNotebookRunCap" },
      { (playing and "󰐊" or "󰼛") .. " ", "GlowNotebookRun" },
      { " 󰘶󰌑", "GlowNotebookRunValue" }, { "", "GlowNotebookRunValueCap" },
      { "   ", "GlowNotebookBar" } })
  end
  -- Keep the type capsule last so all cell kinds align at the right edge.
  vim.list_extend(chunks, { { "", group .. "Cap" },
    { label_icons[filetype], group }, { "", group .. "Cap" } })
  return chunks
end

function M.cell_labels(buf)
  if not buf or buf == 0 then buf = vim.api.nvim_get_current_buf() end
  if not sessions[buf] or not vim.api.nvim_buf_is_loaded(buf) then return {} end
  local cells, running_rows = M.cells(buf), {}
  local molten_namespace = vim.api.nvim_get_namespaces()["molten-extmarks"]
  if molten_namespace then
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, molten_namespace, 0, -1, { details = true })) do
      -- Read only the FIRST NONEMPTY Molten status line, then stop; never search
      -- printed results. Skipping empty rows also accepts older saved layout.
      -- The current native UI does not rewrite Molten output virtual lines.
      local header
      for _, line in ipairs(mark[4].virt_lines or {}) do
        local chunks = {}
        for _, chunk in ipairs(line) do chunks[#chunks + 1] = chunk[1] end
        local text = table.concat(chunks)
        if not text:match("^%s*$") then header = text; break end
      end
      if header and header:match("^Out%[[^%]]*%]: %.%.%. Running") then
        running_rows[#running_rows + 1] = mark[2]
      end
    end
  end
  local language = vim.bo[buf].filetype ~= "" and vim.bo[buf].filetype or "python"
  local labels = {}
  local line_count = vim.api.nvim_buf_line_count(buf)
  for index, cell in ipairs(cells) do
    if cell.header > 0 then
      local playing = false
      if cell.kind == "code" then
        for _, row in ipairs(running_rows) do
          if row >= cell.header and row < cell.finish then playing = true; break end
        end
      end
      local row = M.content_line(cell, line_count) - 1
      local chunks = M.label_chunks(cell.kind, language, playing)
      local width = 0
      for _, chunk in ipairs(chunks) do width = width + vim.fn.strdisplaywidth(chunk[1]) end
      labels[#labels + 1] = { cell = cell, index = index, row = row, chunks = chunks, width = width,
        accent = M.cell_accent(), running = playing }
    end
  end
  return labels
end

function M.refresh_labels(buf)
  if not buf or buf == 0 then buf = vim.api.nvim_get_current_buf() end
  local labels = M.cell_labels(buf)
  -- A text-border UI may own its complete top line. Native frame presentation
  -- keeps the source-line fallback; the renderer declares ownership explicitly.
  local ui = package.loaded["config.media.notebook_ui"]
  if vim.g.neovide_native_notebook == true and ui and (ui.text_borders == true or ui.border_labels == true) then
    if label_signatures[buf] then vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1) end
    label_signatures[buf] = nil
    return labels
  end
  local signature = {}
  for _, label in ipairs(labels) do signature[#signature + 1] = vim.json.encode(label) end
  local current_signature = table.concat(signature, "\n")
  if label_signatures[buf] == current_signature then return labels end
  label_signatures[buf] = current_signature
  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  for _, label in ipairs(labels) do
      vim.api.nvim_buf_set_extmark(buf, namespace, label.row, 0, {
        virt_text = label.chunks,
        virt_text_pos = "eol_right_align", priority = 80,
      })
  end
  return labels
end

local function decorate(buf)
  M.refresh_labels(buf)
  local ok, ui = pcall(require, "config.media.notebook_ui")
  if ok then ui.refresh(buf) end
end

function M.leader_label()
  local leader = vim.g.mapleader or "\\"
  leader = vim.api.nvim_replace_termcodes(leader, true, false, true)
  return leader == " " and "␣" or vim.fn.keytrans(leader)
end

local function theme_color(kind, key)
  local ok, palette = pcall(function() return require("base46").get_theme_tb(kind) end)
  local color = ok and palette and palette[key]
  if type(color) == "string" then color = tonumber(color:gsub("^#", ""), 16) end
  if type(color) == "number" then return color end
end

local function theme_cell_accent()
  local color = theme_color("base_16", "base0D")
  if color then return color end
  local defined = vim.api.nvim_get_hl(0, { name = "Function", link = false, create = false })
  return defined.fg or (vim.o.background == "dark" and 0x96d7f3 or 0x55b4d4)
end

function M.cell_accent()
  local group = vim.api.nvim_get_hl(0, { name = "GlowNotebookCell", link = false, create = false })
  return group.bg or theme_cell_accent()
end

function M.output_accent()
  return theme_color("base_30", "vibrant_green")
    or (vim.o.background == "dark" and 0xb5f297 or 0x94e76b)
end

function M.refresh_title_colors()
  local function highlight(name)
    return vim.api.nvim_get_hl(0, { name = name, link = false, create = false })
  end
  local normal = highlight("Normal")
  local solid_ink = highlight("St_NormalMode").fg or theme_color("base_30", "black")
    or normal.bg or (vim.o.background == "dark" and 0x0b0e14 or 0xfafafa)
  vim.api.nvim_set_hl(0, "GlowNotebookBar", { fg = normal.fg, bg = "NONE" })
  local dark = vim.o.background == "dark"
  local surface = dark and (highlight("St_file_txt").bg or highlight("NormalFloat").bg or normal.bg or 0x20242b) or 0xffffff
  local accents = {}
  local function on_surface(color)
    color = color or 0x405f8f
    local red, green, blue = math.floor(color / 65536), math.floor(color / 256) % 256, color % 256
    local function linear(channel)
      channel = channel / 255
      return channel <= 0.04045 and channel / 12.92 or ((channel + 0.055) / 1.055) ^ 2.4
    end
    local sr, sg, sb = math.floor(surface / 65536), math.floor(surface / 256) % 256, surface % 256
    local base = 0.2126 * linear(sr) + 0.7152 * linear(sg) + 0.0722 * linear(sb)
    -- Keep each capsule on one theme hue, adapting text contrast to its surface.
    for _ = 1, 60 do
      local luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
      if (math.max(luminance, base) + 0.05) / (math.min(luminance, base) + 0.05) >= 4.5 then break end
      if dark then
        red, green, blue = math.min(255, math.ceil(red + (255 - red) * 0.08)), math.min(255, math.ceil(green + (255 - green) * 0.08)), math.min(255, math.ceil(blue + (255 - blue) * 0.08))
      else red, green, blue = math.floor(red * 0.93), math.floor(green * 0.93), math.floor(blue * 0.93) end
    end
    return red * 65536 + green * 256 + blue
  end
  for _, palette in ipairs({
    { "Kernel", "St_NormalMode", "DiagnosticInfo" },
    { "Cells", "St_TerminalMode", "DiagnosticOk", "St_VisualMode" },
    { "Menu", "St_InsertMode", "DiagnosticWarn" },
  }) do
    local source, fallback = highlight(palette[2]), highlight(palette[3])
    if not source.bg and palette[4] then source = highlight(palette[4]) end
    local accent = palette[1] == "Cells" and theme_color("base_16", "base0B")
      or on_surface(source.bg or fallback.fg or normal.fg)
    accents[palette[1]] = accent
    local group = "GlowNotebook" .. palette[1]
    vim.api.nvim_set_hl(0, group, { fg = solid_ink, bg = accent, bold = true })
    vim.api.nvim_set_hl(0, group .. "Value", { fg = accent, bg = surface, bold = false })
    -- One segmented capsule: accent label, adaptive value, transparent outer ends.
    vim.api.nvim_set_hl(0, group .. "Cap", { fg = accent, bg = "NONE" })
    vim.api.nvim_set_hl(0, group .. "ValueCap", { fg = surface, bg = "NONE" })
  end
  vim.api.nvim_set_hl(0, "GlowNotebookPrev", { fg = accents.Cells, bg = surface })
  vim.api.nvim_set_hl(0, "GlowNotebookNext", { fg = accents.Cells, bg = surface })
  local cell_accent = theme_cell_accent()
  vim.api.nvim_set_hl(0, "GlowNotebookCell", { fg = solid_ink, bg = cell_accent })
  for _, name in ipairs({ "Language", "Markdown", "Raw", "Run" }) do
    vim.api.nvim_set_hl(0, "GlowNotebook" .. name, { fg = solid_ink, bg = cell_accent })
    vim.api.nvim_set_hl(0, "GlowNotebook" .. name .. "Cap", { fg = cell_accent, bg = "NONE" })
  end
  vim.api.nvim_set_hl(0, "GlowNotebookRunValue", { fg = cell_accent, bg = surface })
  vim.api.nvim_set_hl(0, "GlowNotebookRunValueCap", { fg = surface, bg = "NONE" })
  -- 输出底边控件与绿色边框使用同一 RGB，独立于顶栏 CELLS 的配色。
  -- 普通字号；图标段实心，按键段保留原胶囊底材。
  local output_accent = M.output_accent()
  vim.api.nvim_set_hl(0, "GlowNotebookExpand", { fg = solid_ink, bg = output_accent, bold = true })
  vim.api.nvim_set_hl(0, "GlowNotebookExpandCap", { fg = output_accent, bg = "NONE" })
  vim.api.nvim_set_hl(0, "GlowNotebookExpandValue", { fg = output_accent, bg = surface })
  vim.api.nvim_set_hl(0, "GlowNotebookExpandValueCap", { fg = surface, bg = "NONE" })
end

local function fit_text(text, width)
  text = text:gsub("[\r\n\t]", " ")
  if vim.fn.strdisplaywidth(text) <= width then return text end
  local ret = ""
  for index = 0, vim.fn.strchars(text) - 1 do
    local char = vim.fn.strcharpart(text, index, 1)
    if vim.fn.strdisplaywidth(ret .. char) > width - 1 then break end
    ret = ret .. char
  end
  return ret .. "…"
end

local function capsule(group, label, value)
  local body = "%#GlowNotebook" .. group .. "Value# "
  local text = ""
  if type(value) == "table" then
    local trimmed, tail = {}, true
    for index = #value, 1, -1 do
      local part = value[index][1]
      if tail then part = part:gsub("%s+$", ""); tail = part == "" end
      trimmed[index] = part
    end
    for index, part in ipairs(value) do
      body = body .. "%#" .. part[2] .. "#" .. trimmed[index]:gsub("%%", "%%%%")
      text = text .. trimmed[index]
    end
  else text = value:gsub("%s+$", ""); body = body .. text:gsub("%%", "%%%%") end
  return "%#GlowNotebook" .. group .. "Cap#%#GlowNotebook" .. group .. "#" .. label .. " " .. body
    .. "%#GlowNotebook" .. group .. "ValueCap#%#GlowNotebookBar#",
    vim.fn.strdisplaywidth("" .. label .. "  " .. text .. "")
end

-- Pure formatting keeps long names bounded without starting or querying a
-- kernel; actual session state still supplies the status symbol.
function M.render_title(session, width, layout)
  local prefix = M.leader_label()
  local selected = session.selected and session.selected.display_name or session.kernel
  local status = session.starting and ("◌ " .. (selected or session.requested or ""))
    or session.ready and selected or session.selected and ("■ " .. selected)
    or (" " .. prefix .. "jk")
  local compact = width < 64
  local kernel_label = width < 40 and "K" or "KERNEL"
  local cells_label, menu_label = width < 56 and "C" or "CELLS", width < 56 and "M" or "MENU"
  local previous, following, gap = compact and "[c" or "↑ [c", compact and "]c" or "↓ ]c", compact and "  " or "   "
  local menu = prefix .. "j"
  local cells, cells_width = capsule("Cells", cells_label,
    { { previous, "GlowNotebookPrev" }, { gap, "GlowNotebookCellsValue" }, { following, "GlowNotebookNext" } })
  local menu_capsule, menu_width = capsule("Menu", menu_label, menu)
  local _, kernel_width = capsule("Kernel", kernel_label, "")
  local left_padding, right_padding = 1, 1
  if vim.g.neovide_native_notebook == true then
    layout = layout or {}
    -- Match the input frame, rather than its inset language capsule. Winbar
    -- uses whole cells and cannot draw beyond the actual resized text grid.
    left_padding = math.max(0, math.floor(math.max(0.12, (layout.textoff or 2) - 0.8) + 0.5))
    local frame_right = (layout.host_width or width) - 1.12
    right_padding = math.max(0, math.floor(width - frame_right + 0.5))
  end
  local outer_spacing = left_padding + 1 + right_padding
  status = fit_text(status, math.max(1, width - cells_width - menu_width - kernel_width - outer_spacing))
  return "%#GlowNotebookBar#" .. string.rep(" ", left_padding) .. capsule("Kernel", kernel_label, status) .. "%="
    .. cells .. " " .. menu_capsule .. string.rep(" ", right_padding)
end

local function title(buf)
  local session = sessions[buf]
  if not session then return end
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_is_valid(win) then
      local info = vim.fn.getwininfo(win)[1]
      local host_width = vim.api.nvim_win_get_width(win)
      vim.wo[win].winbar = M.render_title(session, info and info.width or host_width,
        { textoff = info and info.textoff or 0, host_width = host_width })
    end
  end
end

local function fail(session, message)
  session.starting, session.pending = false, nil
  title(session.buf)
  notify(message, vim.log.levels.ERROR)
end

local function import_saved_outputs(session)
  if session.imported then return end
  local restored = session.restore_path
  local ok, err = pcall(execute, "MoltenImportOutput", { restored or session.path, session.kernel })
  if not ok then
    notify("读取保存输出失败：" .. tostring(err))
    return
  end
  session.imported = true
  require("config.media.notebook_saved").clear(session.buf, true)
  if restored then
    vim.fn.delete(restored)
    session.restore_path = nil
  end
end

local function ensure_ready(callback, kernel_name)
  local buf = vim.api.nvim_get_current_buf()
  local session = sessions[buf]
  if not session then notify("请先打开 .ipynb Notebook。"); return false end
  if session.ready then callback(session); return true end
  if callback then session.pending = callback end
  if session.starting then return true end
  if vim.fn.exists(":MoltenInit") ~= 2 then fail(session, "Molten 未加载；请先安装 Notebook 运行环境并注册远程插件。"); return false end
  local kernels = local_kernels()
  if #kernels > 0 then
    -- A kernel attached manually belongs to the user. Use it without claiming
    -- ownership, so hiding this Notebook never stops an unrelated session.
    session.kernel, session.ready, session.owned = kernels[1], true, false
    session.pending = nil
    import_saved_outputs(session)
    title(buf)
    if callback then callback(session) end
    return true
  end
  session.starting, session.requested = true, kernel_name or require("config.media.runtime").default_kernel
  title(buf)
  local before = vim.fn.MoltenRunningKernels()
  local ok, err = pcall(execute, "MoltenInit", { session.requested })
  if not ok then fail(session, "无法启动内核：" .. tostring(err)); return false end
  local before_set = {}
  for _, kernel in ipairs(before) do before_set[kernel] = true end
  for _, kernel in ipairs(local_kernels()) do
    if not before_set[kernel] then session.kernel, session.owned = kernel, true; break end
  end
  if not session.kernel then fail(session, "内核未能创建，请查看 :messages。" ); return false end
  -- The first evaluation/import must wait for MoltenKernelReady. Running it
  -- immediately after MoltenInit can lose output during upstream startup.
  return true
end

local kernel_discovery = [[
import hashlib, json, os, pathlib, shutil, sys
from jupyter_client.kernelspec import KernelSpecManager
items = {}
def add(name, directory, spec):
    directory = pathlib.Path(directory).resolve()
    if name.startswith('glow-selected-'):
        return
    if not isinstance(spec, dict) or not spec.get('argv') or str(spec.get('language','')).lower() != 'python':
        return
    spec = dict(spec)
    spec['argv'] = list(spec['argv'])
    executable = spec['argv'][0]
    if not os.path.isabs(executable):
        prefix = directory.parents[3] if len(directory.parents) > 3 else pathlib.Path(sys.prefix)
        candidate = prefix / ('Scripts' if os.name == 'nt' else 'bin') / executable
        executable = str(candidate) if candidate.is_file() else (shutil.which(executable) or executable)
        spec['argv'][0] = executable
    key = str(directory)
    items[key] = dict(name=name, display_name=spec.get('display_name', name), resource_dir=key,
                      executable=executable, spec=spec)
for name, item in KernelSpecManager().get_all_specs().items():
    add(name, item['resource_dir'], item['spec'])
# Conda's own registered environments may have same-name `python3` specs that
# Jupyter's merged lookup hides. Read their real specs without running/installing
# conda or changing any environment, and create an isolated alias only on select.
home = pathlib.Path.home()
prefixes = {pathlib.Path(sys.prefix)}
for value in [os.environ.get('CONDA_PREFIX'), os.environ.get('CONDA_EXE')]:
    if value:
        path = pathlib.Path(value)
        prefixes.add(path.parent.parent if path.name.startswith('conda') else path)
registry = home / '.conda' / 'environments.txt'
if registry.is_file():
    prefixes.update(pathlib.Path(line.strip()) for line in registry.read_text().splitlines() if line.strip())
for name in ['miniconda3', 'anaconda3', 'miniforge3', 'mambaforge']:
    base = home / name
    if base.is_dir():
        prefixes.add(base)
        if (base / 'envs').is_dir():
            prefixes.update(path for path in (base / 'envs').iterdir() if path.is_dir())
for prefix in prefixes:
    directory = prefix / 'share' / 'jupyter' / 'kernels'
    if directory.is_dir():
        for file in directory.glob('*/kernel.json'):
            try:
                add(file.parent.name, file.parent, json.loads(file.read_text()))
            except (OSError, ValueError):
                pass
print(json.dumps(sorted(items.values(), key=lambda item: (item['display_name'].lower(), item['resource_dir']))))
]]

function M.available_kernels(callback)
  local python = require("config.media.runtime").python()
  vim.system({ python, "-c", kernel_discovery }, { text = true, timeout = 10000 }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then callback(nil, vim.trim(result.stderr or "无法查询 Jupyter 内核。")); return end
      local ok, items = pcall(vim.json.decode, result.stdout)
      if not ok or type(items) ~= "table" then callback(nil, "Jupyter 内核列表格式无效。"); return end
      callback(items)
    end)
  end)
end

local function preserve_outputs(session)
  if not session.ready then return true end
  local stem = vim.fn.tempname()
  local python, notebook = stem .. ".py", stem .. ".ipynb"
  local ok, err = pcall(function()
    vim.fn.writefile(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false), python)
    require("config.media.runtime").convert({ "--from", "py:percent", "--to", "ipynb", "--output", notebook, python })
    execute("MoltenExportOutput", { notebook, session.kernel }, true)
  end)
  vim.fn.delete(python)
  if not ok then
    vim.fn.delete(notebook)
    notify("为保留现有输出，已取消内核切换：" .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  if session.restore_path then vim.fn.delete(session.restore_path) end
  session.restore_path = notebook
  return true
end

local function connect_kernel(session, selected)
  if session.starting then notify("内核正在启动，请就绪后再切换。"); return end
  local kernels = local_kernels()
  if #kernels > 0 and (not session.owned or #kernels ~= 1 or kernels[1] ~= session.kernel) then
    notify("此缓冲区连接了手动或共享内核；为保留用户内核，请先用 Molten 管理该连接，再选择新内核。")
    return
  end
  if session.selected and session.selected.resource_dir == selected.resource_dir and session.ready then
    notify("当前已连接 " .. selected.display_name .. "。", vim.log.levels.INFO)
    return
  end
  if #kernels > 0 and not preserve_outputs(session) then return end
  -- The alias lives inside our isolated runtime; colliding `python3` specs from
  -- Conda retain their exact interpreter/argv without rewriting user kernels.
  local runtime = require("config.media.runtime")
  local alias = selected.name
  if selected.resource_dir:sub(1, #runtime.directory() + 1) ~= runtime.directory() .. "/" then
    alias = "glow-selected-" .. vim.fn.sha256(selected.resource_dir):sub(1, 16)
    local directory = runtime.directory() .. "/share/jupyter/kernels/" .. alias
    local ok, err = pcall(function()
      vim.fn.mkdir(directory, "p", 448)
      vim.fn.writefile({ vim.json.encode(selected.spec) }, directory .. "/kernel.json")
    end)
    if not ok then notify("无法准备所选内核：" .. tostring(err), vim.log.levels.ERROR); return end
  end
  if #kernels > 0 then
    local ok, err = pcall(execute, "MoltenDeinit")
    if not ok then notify("无法停止当前 Notebook 内核：" .. tostring(err), vim.log.levels.ERROR); return end
  end
  session.kernel, session.ready, session.starting, session.imported, session.owned = nil, false, false, false, false
  session.selected, session.requested = selected, alias
  title(session.buf)
  ensure_ready(function() end, alias)
end

function M.kernel(name)
  local buf = vim.api.nvim_get_current_buf()
  local session = sessions[buf]
  if not session then notify("请先打开 .ipynb Notebook。"); return end
  if session.selecting then return end
  session.selecting = true
  M.available_kernels(function(items, err)
    session.selecting = false
    if not sessions[buf] or not vim.api.nvim_buf_is_valid(buf) then return end
    if not items then notify("无法读取 Jupyter 内核：" .. tostring(err), vim.log.levels.ERROR); return end
    if #items == 0 then notify("未找到 Python Jupyter 内核；请先在所需环境中配置 ipykernel。", vim.log.levels.ERROR); return end
    local function choose(selected)
      if not selected then return end
      in_buffer(buf, function() connect_kernel(session, selected) end)
    end
    if type(name) == "string" and name ~= "" then
      for _, item in ipairs(items) do
        if item.name == name then choose(item); return end
      end
      notify("找不到 Python 内核：" .. name, vim.log.levels.ERROR)
      return
    end
    vim.ui.select(items, { prompt = "选择 Notebook Python 内核（确认后连接）", format_item = function(item)
      return item.display_name .. "  ·  " .. item.executable .. "  [" .. item.name .. "]"
    end }, choose)
  end)
end

local function run_cells(all)
  local buf = vim.api.nvim_get_current_buf()
  local changedtick = vim.api.nvim_buf_get_changedtick(buf)
  local targets = all and M.cells(buf) or { current_cell(buf) }
  local ranges = {}
  for _, cell in ipairs(targets) do
    if cell and cell.kind == "code" and cell.first <= cell.last then
      ranges[#ranges + 1] = { cell.first, cell.last }
    end
  end
  if #ranges == 0 then notify("当前范围没有可运行的代码单元格。", vim.log.levels.INFO); return end
  local requested = sessions[buf] and sessions[buf].requested
  ensure_ready(function(session)
    if vim.api.nvim_buf_get_changedtick(buf) ~= changedtick then
      notify("内核启动期间代码已修改，请重新运行所需单元格。")
      return
    end
    for _, range in ipairs(ranges) do
      local last = vim.api.nvim_buf_get_lines(buf, range[2] - 1, range[2], false)[1] or ""
      vim.fn.MoltenEvaluateRange(session.kernel, range[1], range[2], 1, #last + 1)
    end
    -- Molten displays Running/Done/Failed on each cell. There is no cell-finished
    -- hook, so this module deliberately does not infer or announce completion.
  end, requested)
end

function M.run()
  local buf = vim.api.nvim_get_current_buf()
  local cell = current_cell(buf)
  if cell and cell.kind == "markdown" then
    require("config.media.notebook_markdown").refresh(buf)
    return
  end
  run_cells(false)
end
function M.run_all() run_cells(true) end

function M.jump(direction)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local cells = M.cells(0)
  local current = 0
  for index, cell in ipairs(cells) do if row >= math.max(1, cell.header) then current = index end end
  local target = cells[current + direction]
  if target then vim.api.nvim_win_set_cursor(0, { M.content_line(target, vim.api.nvim_buf_line_count(0)), 0 }) end
end

function M.add(kind, placement)
  local buf = vim.api.nvim_get_current_buf()
  if not sessions[buf] then notify("请先打开 .ipynb Notebook。"); return end
  local cell = current_cell(buf)
  local row = cell and (placement == "above" and math.max(0, cell.header - 1) or cell.finish) or vim.api.nvim_buf_line_count(buf)
  local markdown = kind == "markdown"
  local lines = { markdown and "# %% [markdown]" or "# %%", markdown and "# " or "", "" }
  if placement ~= "above" then table.insert(lines, 1, "") end
  vim.api.nvim_buf_set_lines(buf, row, row, false, lines)
  vim.api.nvim_win_set_cursor(0, { row + (placement == "above" and 2 or 3), markdown and 2 or 0 })
  decorate(buf)
end

local function clear_cell_output(cell)
  local session = sessions[vim.api.nvim_get_current_buf()]
  if not session or not session.ready or cell.first > cell.last then return true end
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(session.buf, -1, { cell.first - 1, 0 }, { cell.last - 1, -1 }, { details = true })) do
    for _, line in ipairs(mark[4].virt_lines or {}) do
      for _, chunk in ipairs(line) do
        if chunk[1]:find("Out[", 1, true) and (chunk[1]:find("Running", 1, true) or chunk[1]:find("On Hold", 1, true)) then
          notify("当前单元格仍在运行，请先中断或等待结束再修改类型或删除。")
          return false
        end
      end
    end
  end
  local original = vim.api.nvim_win_get_cursor(0)
  local ok, err = pcall(function()
    vim.api.nvim_win_set_cursor(0, { cell.first, 0 })
    vim.fn.MoltenOnCursorMoved()
    execute("MoltenDelete")
  end)
  vim.api.nvim_win_set_cursor(0, original)
  if not ok then notify("无法清理当前单元格输出：" .. tostring(err), vim.log.levels.ERROR) end
  return ok
end

function M.convert_cell(kind)
  local buf = vim.api.nvim_get_current_buf()
  if not sessions[buf] then notify("请先打开 .ipynb Notebook。"); return end
  local cell = current_cell(buf)
  if not cell or cell.kind == kind then return end
  if not clear_cell_output(cell) then return end
  local first = cell.header > 0 and cell.header - 1 or 0
  local lines = vim.api.nvim_buf_get_lines(buf, first, cell.finish, false)
  local header = cell.header > 0 and table.remove(lines, 1) or "# %%"
  header = header:gsub("^(# %%%%)%s*%[markdown%]%s*", "%1 "):gsub("^(# %%%%)%s*%[raw%]%s*", "%1 ")
  if kind == "markdown" then
    header = header:gsub("^(# %%%%)(.*)$", "%1 [markdown]%2")
    if cell.kind ~= "markdown" then
      for index, line in ipairs(lines) do lines[index] = line == "" and "#" or "# " .. line end
    end
  elseif cell.kind == "markdown" or cell.kind == "raw" then
    for index, line in ipairs(lines) do lines[index] = line:gsub("^# ?", "") end
  end
  table.insert(lines, 1, vim.trim(header))
  vim.api.nvim_buf_set_lines(buf, first, cell.finish, false, lines)
  decorate(buf)
end

function M.delete_cell()
  local buf = vim.api.nvim_get_current_buf()
  if not sessions[buf] then notify("请先打开 .ipynb Notebook。"); return end
  local cell = current_cell(buf)
  if not cell or not clear_cell_output(cell) then return end
  vim.api.nvim_buf_set_lines(buf, math.max(0, cell.header - 1), cell.finish, false, {})
  decorate(buf)
end

function M.output()
  local session = sessions[vim.api.nvim_get_current_buf()]
  if not session then return end
  local ok, err = require("config.media.notebook_output").enter(function()
    if not session.ready then return require("config.media.notebook_saved").enter(session.buf) end
    -- Molten's BufLeave hook clears its output window. Suppress that hook during
    -- the deliberate source-to-output focus transition, as upstream recommends.
    vim.cmd({ cmd = "MoltenEnterOutput", mods = { noautocmd = true } })
  end)
  if not ok then notify(err and ("无法打开单元格输出：" .. err) or "当前单元格没有可查看的输出。") end
end

function M.interrupt()
  local session = sessions[vim.api.nvim_get_current_buf()]
  if session and session.ready then execute("MoltenInterrupt", { session.kernel }) end
end

function M.restart()
  local session = sessions[vim.api.nvim_get_current_buf()]
  if session and session.ready then
    session.ready, session.starting, session.pending = false, true, nil
    execute("MoltenRestart", { session.kernel })
    title(session.buf)
  end
end

local function export(buf)
  local session = sessions[buf]
  local dirty = require("config.media.notebook_dirty")
  local token = dirty.token(buf)
  if not session or not session.ready then dirty.saved(buf, token); return end
  -- Upstream compares cell contents through Treesitter. Fail visibly before
  -- export if the parser is missing; never claim fresh outputs were saved.
  local parser_ok, parser_error = pcall(vim.treesitter.get_string_parser, "x = 1\n", "python")
  if not parser_ok then
    session.save_error = true
    dirty.failed(buf)
    title(buf)
    local message = "代码已写入 Notebook，但新输出未保存：Python Treesitter 解析器不可用。" .. tostring(parser_error)
    notify(message, vim.log.levels.ERROR)
    error(message, 0)
  end
  local ok, err = pcall(execute, "MoltenExportOutput", { session.path, session.kernel }, true)
  session.save_error = not ok
  if ok then dirty.saved(buf, token) else dirty.failed(buf) end
  title(buf)
  if not ok then
    local message = "Notebook 新输出保存失败：" .. tostring(err)
    notify(message, vim.log.levels.ERROR)
    error(message, 0)
  end
end

local function describe_navigation(buf)
  local descriptions = {
    ["[["] = "上一个 Python 顶层定义", ["]]"] = "下一个 Python 顶层定义",
    ["[]"] = "上一个 Python 顶层定义结尾", ["]["] = "下一个 Python 顶层定义结尾",
    ["[m"] = "上一个 Python 定义", ["]m"] = "下一个 Python 定义",
    ["[M"] = "上一个 Python 定义结尾", ["]M"] = "下一个 Python 定义结尾",
    ["[l"] = "上一条位置列表结果", ["]l"] = "下一条位置列表结果",
    ["[L"] = "位置列表首条结果", ["]L"] = "位置列表末条结果",
    ["[q"] = "上一条 Quickfix 结果", ["]q"] = "下一条 Quickfix 结果",
    ["[Q"] = "Quickfix 首条结果", ["]Q"] = "Quickfix 末条结果",
  }
  in_buffer(buf, function()
    for _, mode in ipairs({ "n", "x", "o" }) do
      for lhs, description in pairs(descriptions) do
        local mapping = vim.fn.maparg(lhs, mode, false, true)
        if next(mapping) and (not mapping.desc or mapping.desc == "") then
          -- mapset preserves ftplugin's script-local RHS/SID, count, callback,
          -- expression and remap flags. Add only a Notebook-local description.
          mapping.desc, mapping.buffer = description, 1
          vim.fn.mapset(mode, false, mapping)
        end
      end
    end
  end)
end

local function attach(buf, reload)
  local path = vim.api.nvim_buf_get_name(buf)
  if not M.supports(path) then return end
  local runtime = require("config.media.runtime")
  if vim.b[buf].glow_notebook_read_complete and vim.bo[buf].filetype ~= "python" then
    -- A later filetype detection/session restore can see only the .ipynb
    -- filename. Revalidate converted source before restoring its language.
    runtime.complete_notebook_load(buf)
  end
  if not sessions[buf] then sessions[buf] = { buf = buf, path = path } end
  runtime.ensure_notebook_writer(buf)
  if not sessions[buf].ready then require("config.media.notebook_saved").attach(buf, path, reload) end
  if reload then require("config.media.notebook_dirty").detach(buf) end
  require("config.media.notebook_dirty").attach(buf)
  vim.b[buf].glow_notebook_edit = true
  local function map(mode, keys, action, description)
    vim.keymap.set(mode, keys, action, { buffer = buf, silent = true, desc = description })
  end
  map("n", "<S-CR>", M.run, "运行 Notebook 单元格")
  map("i", "<S-CR>", function() vim.cmd.stopinsert(); vim.schedule(M.run) end, "运行 Notebook 单元格")
  map("n", "<localleader>nr", M.run, "运行当前单元格")
  map("n", "<localleader>na", M.run_all, "运行所有代码单元格")
  map("n", "<localleader>no", M.output, "滚动查看单元格输出")
  map("n", "<localleader>ni", M.interrupt, "中断 Notebook 内核")
  map("n", "<localleader>nk", M.kernel, "启动 Notebook 内核")
  map("n", "<localleader>nc", function() M.add("code") end, "添加代码单元格")
  map("n", "<localleader>nm", function() M.add("markdown") end, "添加 Markdown 单元格")
  map("n", "<leader>jk", M.kernel, "选择 Notebook 内核")
  map("n", "<leader>jr", M.run, "运行当前单元格")
  map("n", "<leader>jA", M.run_all, "运行所有代码单元格")
  map("n", "<leader>jo", M.output, "滚动查看单元格输出")
  map("n", "<leader>ji", M.interrupt, "中断 Notebook 内核")
  map("n", "<leader>j00", M.restart, "重启 Notebook 内核")
  map("n", "<leader>ja", function() M.add("code", "above") end, "上方插入代码单元格")
  map("n", "<leader>jb", function() M.add("code") end, "下方插入代码单元格")
  map("n", "<leader>jc", function() M.add("code") end, "下方插入代码单元格")
  map("n", "<leader>jM", function() M.add("markdown") end, "下方插入 Markdown 单元格")
  map("n", "<leader>jm", function() M.convert_cell("markdown") end, "当前单元格转 Markdown")
  map("n", "<leader>jy", function() M.convert_cell("code") end, "当前单元格转代码")
  map("n", "<leader>jdd", M.delete_cell, "删除当前单元格")
  map("n", "]c", function() M.jump(1) end, "下一个 Notebook 单元格")
  map("n", "[c", function() M.jump(-1) end, "上一个 Notebook 单元格")
  describe_navigation(buf)
  local ok, which_key = pcall(require, "which-key")
  if ok then which_key.add({ { "<leader>j", group = "Jupyter Notebook", icon = "", buffer = buf } }) end
  local ui_ok, ui = pcall(require, "config.media.notebook_ui")
  if ui_ok then ui.setup(); ui.attach(buf) end
  require("config.media.notebook_markdown").attach(buf)
  decorate(buf)
  title(buf)
end

function M.resolve_path(path)
  local original = path
  path = uv.fs_realpath(original) or vim.fs.normalize(vim.fn.fnamemodify(original, ":p"))
  if vim.fn.filereadable(path) ~= 1 then
    -- User commands with nargs='?' retain fnameescape()'s backslashes in
    -- args.args. Prefer a real literal path; decode Ex escapes only on a miss.
    local decoded = original:gsub("\\(.)", "%1")
    local candidate = uv.fs_realpath(decoded) or vim.fs.normalize(vim.fn.fnamemodify(decoded, ":p"))
    if vim.fn.filereadable(candidate) == 1 then path = candidate end
  end
  return path
end

-- Choose an editable owner without replacing plugin panels or unlocking them.
-- This helper has no Notebook session state, so it can also be hot-installed.
function M.route_open(opts)
  opts = opts or {}
  local tab = vim.api.nvim_get_current_tabpage()
  local function editable(win)
    if not win or not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_tabpage(win) ~= tab
      or vim.api.nvim_win_get_config(win).relative ~= "" or vim.wo[win].winfixbuf then return false end
    local buf = vim.api.nvim_win_get_buf(win)
    local kind, ft = vim.bo[buf].buftype, vim.bo[buf].filetype:lower()
    -- A dashboard is a replaceable start page; keep its terminal animation
    -- from surviving above an unnecessary new Notebook split.
    if kind == "nofile" and not vim.bo[buf].modified
      and (ft == "snacks_dashboard" or ft == "dashboard" or ft == "alpha") then return true end
    return (kind == "" or kind == "acwrite") and not (ft:match("^avante") or ft:match("^neo%-tree")
      or ft:match("^glow_") or ft:match("^snacks_") or ft == "dashboard" or ft == "alpha"
      or ft == "trouble" or ft == "notify")
  end
  local target
  for _, win in ipairs({ opts.win or 0, vim.api.nvim_get_current_win(), vim.fn.win_getid(vim.fn.winnr("#")) }) do
    if editable(win) then target = win; break end
  end
  if not target then
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
      if editable(win) then target = win; break end
    end
  end
  if target then vim.api.nvim_set_current_win(target)
  else
    -- A split must start from a normal window even when every such window is
    -- locked; it creates a separate owner instead of replacing that buffer.
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
      if vim.api.nvim_win_get_config(win).relative == "" then vim.api.nvim_set_current_win(win); break end
    end
  end
  local command = opts.command
  if not command or command == "" then
    command = not target and (opts.fallback_command or "rightbelow vnew") or nil
  end
  if command then
    local before = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do before[win] = true end
    vim.cmd(command)
    local win = vim.api.nvim_get_current_win()
    -- :split may copy winfixbuf from an otherwise unavoidable locked base.
    -- Only the newly created destination belongs to this open operation.
    if not before[win] then vim.wo[win].winfixbuf = false end
  end
  local win = vim.api.nvim_get_current_win()
  if vim.wo[win].winfixbuf or vim.api.nvim_win_get_config(win).relative ~= "" then
    error("无法找到可编辑的 Notebook 窗口。", 0)
  end
  return win
end

function M.open(path, opts)
  opts = opts or {}
  if not M.supports(path) then notify("请选择 .ipynb 文件。"); return false end
  M.setup()
  path = M.resolve_path(path)
  if vim.fn.filereadable(path) ~= 1 then notify("无法读取 Notebook：" .. path); return false end
  if not require("config.media.runtime").ready() then notify("Notebook 运行环境尚未安装，请先执行配套安装脚本。"); return false end
  local valid, reason = pcall(require("config.media.runtime").read_notebook, path)
  if not valid then notify("无法打开 Notebook：" .. tostring(reason), vim.log.levels.ERROR); return false end
  local ok, err = pcall(function()
    M.route_open(opts)
    execute("edit", { path })
    if not require("config.media.runtime").complete_notebook_load(vim.api.nvim_get_current_buf()) then
      error("Notebook 尚未读入 percent 源码，请重新打开文件。", 0)
    end
    attach(vim.api.nvim_get_current_buf())
  end)
  if not ok then notify("无法打开 Notebook：" .. tostring(err), vim.log.levels.ERROR); return false end
  return true
end

function M.from_tree(event)
  if not M.supports(event.path) then return end
  local win = require("neo-tree.utils").get_appropriate_window(event.state)
  local command = ({ split = "split", sp = "split", vsplit = "vsplit", vs = "vsplit", tabnew = "tabnew", tabedit = "tabnew" })[event.open_cmd or "edit"]
  M.open(event.path, { win = win, command = command,
    fallback_command = event.state.current_position == "right" and "leftabove vnew" or "rightbelow vnew" })
  return { handled = true }
end

function M.setup()
  if configured then return end
  configured = true
  require("config.media.notebook_saved").setup()
  M.refresh_title_colors()
  vim.api.nvim_set_hl(0, "GlowNotebookCell", { default = true, link = "CursorLine" })
  vim.api.nvim_set_hl(0, "GlowNotebookLabel", { default = true, link = "Title" })
  local group = vim.api.nvim_create_augroup("GlowNotebookEdit", { clear = true })
  local function refresh_titles()
    M.refresh_title_colors()
    for buf in pairs(sessions) do title(buf) end
  end
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = function() vim.schedule(refresh_titles) end })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "NvThemeReload", callback = function() vim.schedule(refresh_titles) end })
  vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, { group = group, callback = function()
    for buf in pairs(sessions) do title(buf) end
  end })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "BufReadPost" }, { group = group, pattern = "*.ipynb", callback = function(event) attach(event.buf, event.event == "BufReadPost") end })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, { group = group, callback = function(event) decorate(event.buf) end })
  vim.api.nvim_create_autocmd("BufWritePost", { group = group, pattern = "*.ipynb", callback = function(event) export(event.buf) end })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "MoltenKernelReady", callback = function(event)
    local kernel = event.data and event.data.kernel_id
    for buf, session in pairs(sessions) do
      if session.kernel == kernel then
        session.ready, session.starting = true, false
        vim.schedule(function()
          in_buffer(buf, function()
            import_saved_outputs(session)
            local pending = session.pending
            session.pending = nil
            title(buf)
            if pending then pending(session) end
          end)
        end)
      end
    end
  end })
  -- Hidden buffers still own live Notebook state. Bufferline and tab switches
  -- must retain unsaved outputs, execution counters and the kernel namespace.
  -- Molten releases its kernel on BufUnload; discard only our descriptor here.
  vim.api.nvim_create_autocmd({ "BufUnload", "BufDelete", "BufWipeout" }, { group = group, callback = function(event)
    local session = sessions[event.buf]
    if session and session.restore_path then vim.fn.delete(session.restore_path) end
    require("config.media.notebook_saved").detach(event.buf)
    require("config.media.notebook_dirty").detach(event.buf)
    sessions[event.buf] = nil
    label_signatures[event.buf] = nil
  end })
  local commands = {
    GlowNotebook = { function(args) M.open(args.args ~= "" and args.args or vim.api.nvim_buf_get_name(0)) end, "?", "打开原生可编辑 Notebook" },
    GlowNotebookRun = { M.run, 0, "运行当前代码单元格" },
    GlowNotebookRunAll = { M.run_all, 0, "运行所有代码单元格" },
    GlowNotebookOutput = { M.output, 0, "滚动查看原生单元格输出" },
    GlowNotebookInterrupt = { M.interrupt, 0, "中断 Notebook 内核" },
    GlowNotebookRestart = { M.restart, 0, "重启 Notebook 内核" },
    GlowNotebookKernel = { function(args) M.kernel(args.args) end, "?", "选择或切换 Notebook Python 内核" },
    GlowNotebookAddCode = { function() M.add("code") end, 0, "添加代码单元格" },
    GlowNotebookAddMarkdown = { function() M.add("markdown") end, 0, "添加 Markdown 单元格" },
    GlowNotebookMarkdown = { function() M.convert_cell("markdown") end, 0, "当前单元格转 Markdown" },
    GlowNotebookCode = { function() M.convert_cell("code") end, 0, "当前单元格转代码" },
    GlowNotebookDeleteCell = { M.delete_cell, 0, "删除当前 Notebook 单元格" },
  }
  for name, command in pairs(commands) do
    vim.api.nvim_create_user_command(name, command[1], { nargs = command[2], desc = command[3], force = true })
  end
end

return M
