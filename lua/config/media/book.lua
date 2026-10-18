-- Jupyter Book project builds are independent from .ipynb saved-output viewing.
local M = {}
local uv = vim.uv or vim.loop
local projects, latest, configured = {}, nil, false
local max_log_lines = 4000

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Jupyter Book" })
end

function M.find_root(path)
  path = path and path ~= "" and path or vim.api.nvim_buf_get_name(0)
  if path == "" then path = uv.cwd() end
  path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  local stat = uv.fs_stat(path)
  local dir = stat and stat.type == "directory" and path or vim.fs.dirname(path)
  local config = vim.fs.find({ "_config.yml", "myst.yml", "myst.yaml" }, { path = dir, upward = true, type = "file", limit = 1 })[1]
  return config and vim.fs.dirname(config) or nil, config
end

local function log(project, value)
  if not vim.api.nvim_buf_is_valid(project.log_buf) then return end
  local lines = vim.split(tostring(value):gsub("\r", ""), "\n", { plain = true })
  if lines[#lines] == "" then table.remove(lines) end
  if #lines == 0 then return end
  vim.bo[project.log_buf].modifiable = true
  vim.api.nvim_buf_set_lines(project.log_buf, -1, -1, false, lines)
  local count = vim.api.nvim_buf_line_count(project.log_buf)
  if count > max_log_lines then vim.api.nvim_buf_set_lines(project.log_buf, 0, count - max_log_lines, false, {}) end
  vim.bo[project.log_buf].modifiable = false
  vim.bo[project.log_buf].modified = false
end

local function new_project(root)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "glow-book-log://" .. root)
  vim.bo[buf].filetype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = "log", "hide", false
  vim.bo[buf].modifiable = false
  local project = { root = root, log_buf = buf, status = "idle", generation = 0, streams = {} }
  projects[root] = project
  vim.keymap.set("n", "q", "<Cmd>close<CR>", { buffer = buf, silent = true, desc = "关闭构建日志" })
  vim.keymap.set("n", "<C-c>", function() M.cancel(root) end, { buffer = buf, desc = "取消此项目构建" })
  return project
end

local function stream(project, name, data)
  if not data or data == "" then return end
  local combined = (project.streams[name] or "") .. data
  local last = combined:match(".*()\n")
  if last then log(project, combined:sub(1, last)); combined = combined:sub(last + 1) end
  -- Bound a builder emitting an unbroken line as well as the visible log buffer.
  if #combined > 65536 then log(project, combined:sub(1, 65536)); combined = combined:sub(-65536) end
  project.streams[name] = combined
end

local function artifact(root)
  for _, relative in ipairs({ "_build/html/index.html", "_build/site/index.html", "_build/index.html" }) do
    local path = vim.fs.joinpath(root, relative)
    local stat = uv.fs_stat(path)
    if stat and stat.type == "file" then return path end
  end
end

function M.cancel(root)
  local project = projects[root or latest]
  if not project or not project.process then notify("当前没有本模块启动的构建。"); return false end
  project.cancelled = true
  log(project, "\n正在取消构建（向本次构建进程发送终止信号）…")
  project.process:kill(15)
  return true
end

function M.log(root)
  local project = projects[root or latest]
  if not project or not vim.api.nvim_buf_is_valid(project.log_buf) then notify("尚无构建日志。"); return false end
  vim.cmd("botright 12split")
  vim.api.nvim_win_set_buf(0, project.log_buf)
  vim.wo.wrap, vim.wo.number, vim.wo.relativenumber = false, false, false
  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(project.log_buf), 0 })
  return true
end

local function show(project)
  if not project.pending_preview then return end
  if not vim.api.nvim_tabpage_is_valid(project.origin_tab) or not vim.api.nvim_win_is_valid(project.origin_win) then
    project.pending_preview = false
    log(project, "原窗口已关闭；保留站点产物，没有创建预览。")
    return
  end
  if vim.api.nvim_get_current_tabpage() ~= project.origin_tab then return end
  project.pending_preview = false
  local opts = project.view_opts
  local view_opts = vim.tbl_extend("force", opts, { kind = "web", title = vim.fs.basename(project.root) .. " · Jupyter Book",
    command = opts.command or "rightbelow vnew", win = project.origin_win, on_close = function()
      project.preview_open = false
      if project.process then M.cancel(project.root) end
      if opts.on_close then pcall(opts.on_close) end
    end })
  local opened, value = pcall(require("config.media.preview").open, project.html, view_opts)
  project.preview_open = opened and value ~= false
  if not project.preview_open then
    log(project, "HTML 已生成，打开原生网页预览失败：" .. tostring(value))
    notify("构建成功，内嵌预览未能打开；产物为 " .. project.html, vim.log.levels.WARN)
  end
end

function M.open(path, opts)
  opts = opts or {}
  M.setup()
  local root, config = M.find_root(path)
  if not root then notify("未找到 Jupyter Book 项目；请指定含 _config.yml 或 myst.yml 的目录。", vim.log.levels.WARN); return false end
  local project = projects[root]
  if project and project.process then notify("此项目正在构建；使用 :GlowBookLog 查看，:GlowBookCancel 取消。", vim.log.levels.WARN); return false end
  local modern = vim.fs.basename(config):match("^myst%.") ~= nil
  -- opts.builder is an argv prefix for a chosen environment, never shell source.
  local command = vim.deepcopy(opts.builder or (modern and { "jupyter", "book" } or { "jupyter-book" }))
  if type(command) ~= "table" or type(command[1]) ~= "string" or vim.fn.executable(command[1]) ~= 1 then
    notify("找不到 Jupyter Book 命令。请先在所需环境安装 Jupyter Book，并让 Neovim 的 PATH 可访问它；本模块不会安装或升级环境。", vim.log.levels.ERROR)
    return false
  end
  command[#command + 1] = "build"
  if modern then command[#command + 1] = "--html" else command[#command + 1] = root end
  project = project or new_project(root)
  project.origin_tab, project.origin_win = vim.api.nvim_get_current_tabpage(), opts.win or vim.api.nvim_get_current_win()
  project.view_opts = opts
  latest, project.generation = root, project.generation + 1
  local generation = project.generation
  project.cancelled, project.status, project.streams = false, "building", {}
  log(project, "\n开始构建：" .. root .. "\n命令参数：" .. vim.inspect(command))
  notify("开始构建 " .. vim.fs.basename(root) .. "；:GlowBookLog 查看日志。")
  local function output(name)
    return function(err, data)
      vim.schedule(function()
        if project.generation ~= generation then return end
        if err then log(project, name .. ": " .. tostring(err)) end
        stream(project, name, data)
      end)
    end
  end
  local ok, process = pcall(vim.system, command, { cwd = root, text = true, stdout = output("stdout"), stderr = output("stderr") }, function(result)
    vim.schedule(function()
      if project.generation ~= generation then return end
      project.process = nil
      for _, value in pairs(project.streams) do if value ~= "" then log(project, value) end end
      project.streams = {}
      if project.cancelled then
        project.status = "cancelled"
        log(project, "构建已取消；未刷新站点。")
        notify("构建已取消。")
      elseif result.code ~= 0 then
        project.status = "failed"
        log(project, ("构建失败：退出码 %s，信号 %s。"):format(result.code, result.signal))
        notify("构建失败；:GlowBookLog 查看完整反馈。", vim.log.levels.ERROR)
      else
        local html = artifact(root)
        if not html then
          project.status = "failed"
          log(project, "构建命令成功，但未找到 _build/html/index.html、_build/site/index.html 或 _build/index.html。")
          notify("没有找到 HTML 站点产物；:GlowBookLog 查看反馈。", vim.log.levels.ERROR)
          return
        end
        project.status, project.html = "ready", html
        log(project, "构建成功：" .. html)
        local preview = require("config.media.preview")
        if project.preview_open then
          preview.refresh_source(html)
        else
          project.pending_preview = true
          show(project)
        end
        if project.pending_preview then
          notify("构建成功；返回原标签页时打开站点预览。")
        elseif project.preview_open then
          notify("构建成功，站点预览已刷新。")
        else
          notify("构建成功；HTML 产物已保留。")
        end
      end
    end)
  end)
  if not ok then
    project.status = "failed"
    log(project, "无法启动构建：" .. tostring(process))
    notify("无法启动构建；:GlowBookLog 查看原因。", vim.log.levels.ERROR)
    return false
  end
  project.process = process
  return true
end

function M.status(root)
  local project = projects[root or latest]
  return project and { root = project.root, status = project.status, html = project.html, running = project.process ~= nil } or nil
end

function M.setup()
  if configured then return end
  configured = true
  vim.api.nvim_create_user_command("GlowBook", function(args) M.open(args.args ~= "" and args.args or nil) end,
    { nargs = "?", complete = "dir", desc = "构建 Jupyter Book 项目并预览 HTML 站点" })
  vim.api.nvim_create_user_command("GlowBookLog", function() M.log() end, { desc = "查看最近一次 Jupyter Book 构建日志" })
  vim.api.nvim_create_user_command("GlowBookCancel", function() M.cancel() end, { desc = "取消本模块启动的 Jupyter Book 构建" })
  local group = vim.api.nvim_create_augroup("GlowBook", { clear = true })
  vim.api.nvim_create_autocmd({ "TabEnter", "WinClosed" }, { group = group, callback = function()
    for _, project in pairs(projects) do show(project) end
  end })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = function()
    for root, project in pairs(projects) do if project.process then M.cancel(root) end end
  end })
end

return M
