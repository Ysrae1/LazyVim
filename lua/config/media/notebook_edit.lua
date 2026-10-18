-- Native Notebook editing: Jupytext owns .ipynb serialization; Molten owns
-- execution and output. Opening a document never starts a kernel or runs code.
local M = {}
local sessions, configured = {}, false
local namespace = vim.api.nvim_create_namespace("glow.notebook.cells")
local uv = vim.uv or vim.loop

function M.status(buf)
  local session = sessions[buf or vim.api.nvim_get_current_buf()]
  return session and { kernel = session.kernel, ready = session.ready == true,
    starting = session.starting == true, owned = session.owned == true, save_error = session.save_error == true } or nil
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

local function decorate(buf)
  if not sessions[buf] or not vim.api.nvim_buf_is_loaded(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  for _, cell in ipairs(M.cells(buf)) do
    if cell.header > 0 then
      vim.api.nvim_buf_set_extmark(buf, namespace, cell.header - 1, 0, {
        line_hl_group = "GlowNotebookCell", hl_eol = true,
        virt_text = { { cell.kind == "markdown" and " Markdown " or cell.kind == "raw" and " 原始内容 " or " 代码 · ⇧↵ 运行 ", "GlowNotebookLabel" } },
        virt_text_pos = "right_align", priority = 80,
      })
    end
  end
end

local function title(buf)
  local session = sessions[buf]
  if not session then return end
  local status = session.ready and ("内核 " .. session.kernel) or session.starting and "内核启动中…" or "未启动内核"
  if session.save_error then status = status .. " · 输出保存失败" end
  local name = vim.fs.basename(session.path):gsub("%%", "%%%%")
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_is_valid(win) then
      vim.wo[win].winbar = " " .. name .. "  ·  " .. status .. "%=%< ⇧↵ 运行  ]c/[c 单元格  <LocalLeader>no 输出 "
    end
  end
end

local function fail(session, message)
  session.starting, session.pending = false, nil
  title(session.buf)
  notify(message, vim.log.levels.ERROR)
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

function M.kernel(name)
  local session = sessions[vim.api.nvim_get_current_buf()]
  if not session then notify("请先打开 .ipynb Notebook。"); return end
  if session.kernel and name and name ~= "" then
    notify("当前 Notebook 已连接内核；关闭后重新打开再选择其他内核，或使用 Molten 管理已有连接。")
    return
  end
  ensure_ready(function() end, name ~= "" and name or nil)
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
  end)
end

function M.run() run_cells(false) end
function M.run_all() run_cells(true) end

function M.jump(direction)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local cells = M.cells(0)
  if direction > 0 then
    for _, cell in ipairs(cells) do
      if cell.header > row then vim.api.nvim_win_set_cursor(0, { cell.header, 0 }); return end
    end
  else
    for index = #cells, 1, -1 do
      local header = math.max(1, cells[index].header)
      if header < row then vim.api.nvim_win_set_cursor(0, { header, 0 }); return end
    end
  end
end

function M.add(kind)
  local buf = vim.api.nvim_get_current_buf()
  if not sessions[buf] then notify("请先打开 .ipynb Notebook。"); return end
  local cell = current_cell(buf)
  local row = cell and cell.finish or vim.api.nvim_buf_line_count(buf)
  local markdown = kind == "markdown"
  vim.api.nvim_buf_set_lines(buf, row, row, false, { "", markdown and "# %% [markdown]" or "# %%", markdown and "# " or "", "" })
  vim.api.nvim_win_set_cursor(0, { row + 3, markdown and 2 or 0 })
  decorate(buf)
end

function M.output()
  local session = sessions[vim.api.nvim_get_current_buf()]
  if not session or not session.ready then notify("先运行单元格或启动内核以读取保存输出。"); return end
  -- Molten's BufLeave hook clears its output window. Suppress that hook during
  -- the deliberate source-to-output focus transition, as upstream recommends.
  local ok, err = pcall(vim.cmd, { cmd = "MoltenEnterOutput", mods = { noautocmd = true } })
  if not ok then notify("无法打开单元格输出：" .. tostring(err)) end
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
  if not session or not session.ready then return end
  -- Upstream compares cell contents through Treesitter. Fail visibly before
  -- export if the parser is missing; never claim fresh outputs were saved.
  local parser_ok, parser_error = pcall(vim.treesitter.get_string_parser, "x = 1\n", "python")
  if not parser_ok then
    session.save_error = true
    title(buf)
    notify("代码已写入 Notebook，但新输出未保存：Python Treesitter 解析器不可用。" .. tostring(parser_error), vim.log.levels.ERROR)
    return
  end
  local ok, err = pcall(execute, "MoltenExportOutput", { session.path, session.kernel }, true)
  session.save_error = not ok
  title(buf)
  if not ok then notify("Notebook 新输出保存失败：" .. tostring(err), vim.log.levels.ERROR) end
end

local function attach(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  if not M.supports(path) then return end
  if not sessions[buf] then sessions[buf] = { buf = buf, path = path } end
  vim.b[buf].glow_notebook_edit = true
  local function map(mode, keys, action, description)
    vim.keymap.set(mode, keys, action, { buffer = buf, silent = true, desc = description })
  end
  map("n", "<S-CR>", M.run, "运行 Notebook 单元格")
  map("i", "<S-CR>", function() vim.cmd.stopinsert(); vim.schedule(M.run) end, "运行 Notebook 单元格")
  map("n", "<localleader>nr", M.run, "运行当前单元格")
  map("n", "<localleader>na", M.run_all, "运行所有代码单元格")
  map("n", "<localleader>no", M.output, "查看单元格输出")
  map("n", "<localleader>ni", M.interrupt, "中断 Notebook 内核")
  map("n", "<localleader>nk", M.kernel, "启动 Notebook 内核")
  map("n", "<localleader>nc", function() M.add("code") end, "添加代码单元格")
  map("n", "<localleader>nm", function() M.add("markdown") end, "添加 Markdown 单元格")
  map("n", "]c", function() M.jump(1) end, "下一个 Notebook 单元格")
  map("n", "[c", function() M.jump(-1) end, "上一个 Notebook 单元格")
  decorate(buf)
  title(buf)
end

function M.open(path, opts)
  opts = opts or {}
  if not M.supports(path) then notify("请选择 .ipynb 文件。"); return false end
  M.setup()
  path = uv.fs_realpath(path) or vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  if vim.fn.filereadable(path) ~= 1 then notify("无法读取 Notebook：" .. path); return false end
  if not require("config.media.runtime").ready() then notify("Notebook 运行环境尚未安装，请先执行配套安装脚本。"); return false end
  local ok, err = pcall(function()
    if opts.win and vim.api.nvim_win_is_valid(opts.win) then vim.api.nvim_set_current_win(opts.win) end
    if opts.command then vim.cmd(opts.command) end
    execute("edit", { path })
    attach(vim.api.nvim_get_current_buf())
  end)
  if not ok then notify("无法打开 Notebook：" .. tostring(err), vim.log.levels.ERROR); return false end
  return true
end

function M.from_tree(event)
  if not M.supports(event.path) then return end
  local win, is_tree = require("neo-tree.utils").get_appropriate_window(event.state)
  local command = ({ split = "split", sp = "split", vsplit = "vsplit", vs = "vsplit", tabnew = "tabnew", tabedit = "tabnew" })[event.open_cmd or "edit"]
  if not command and is_tree then command = event.state.current_position == "right" and "leftabove vnew" or "rightbelow vnew" end
  M.open(event.path, { win = win, command = command })
  return { handled = true }
end

function M.setup()
  if configured then return end
  configured = true
  vim.api.nvim_set_hl(0, "GlowNotebookCell", { default = true, link = "CursorLine" })
  vim.api.nvim_set_hl(0, "GlowNotebookLabel", { default = true, link = "Title" })
  local group = vim.api.nvim_create_augroup("GlowNotebookEdit", { clear = true })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "BufReadPost" }, { group = group, pattern = "*.ipynb", callback = function(event) attach(event.buf) end })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, { group = group, callback = function(event) decorate(event.buf) end })
  vim.api.nvim_create_autocmd("BufWritePost", { group = group, pattern = "*.ipynb", callback = function(event) export(event.buf) end })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "MoltenKernelReady", callback = function(event)
    local kernel = event.data and event.data.kernel_id
    for buf, session in pairs(sessions) do
      if session.kernel == kernel then
        session.ready, session.starting = true, false
        vim.schedule(function()
          in_buffer(buf, function()
            if not session.imported then
              session.imported = true
              local ok, err = pcall(execute, "MoltenImportOutput", { session.path, kernel })
              if not ok then notify("读取保存输出失败：" .. tostring(err)) end
            end
            local pending = session.pending
            session.pending = nil
            title(buf)
            if pending then pending(session) end
          end)
        end)
      end
    end
  end })
  vim.api.nvim_create_autocmd("BufHidden", { group = group, pattern = "*.ipynb", callback = function(event)
    vim.schedule(function()
      local session = sessions[event.buf]
      if not session or not session.owned or not session.kernel or #vim.fn.win_findbuf(event.buf) > 0 then return end
      in_buffer(event.buf, function()
        local kernels = local_kernels()
        if #kernels == 1 and kernels[1] == session.kernel then
          pcall(execute, "MoltenDeinit")
          session.kernel, session.ready, session.starting, session.imported = nil, false, false, false
          title(event.buf)
        end
      end)
    end)
  end })
  vim.api.nvim_create_autocmd("BufWipeout", { group = group, callback = function(event) sessions[event.buf] = nil end })
  local commands = {
    GlowNotebook = { function(args) M.open(args.args ~= "" and args.args or vim.api.nvim_buf_get_name(0)) end, "?", "打开原生可编辑 Notebook" },
    GlowNotebookRun = { M.run, 0, "运行当前代码单元格" },
    GlowNotebookRunAll = { M.run_all, 0, "运行所有代码单元格" },
    GlowNotebookOutput = { M.output, 0, "查看原生单元格输出" },
    GlowNotebookInterrupt = { M.interrupt, 0, "中断 Notebook 内核" },
    GlowNotebookRestart = { M.restart, 0, "重启 Notebook 内核" },
    GlowNotebookKernel = { function(args) M.kernel(args.args) end, "?", "启动 Notebook 内核，可指定 kernelspec" },
    GlowNotebookAddCode = { function() M.add("code") end, 0, "添加代码单元格" },
    GlowNotebookAddMarkdown = { function() M.add("markdown") end, 0, "添加 Markdown 单元格" },
  }
  for name, command in pairs(commands) do
    vim.api.nvim_create_user_command(name, command[1], { nargs = command[2], desc = command[3], force = true })
  end
end

return M
