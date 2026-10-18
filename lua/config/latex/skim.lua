local M = {}
local pending

local function app_path()
  local settings = vim.g.vimtex_view_skim or {}
  return (settings.exe or ""):match("^(.-%.app)/Contents/") or "/Applications/Skim.app"
end

local function notify(message)
  vim.notify(message, vim.log.levels.WARN, { title = "VimTeX / Skim" })
end

local function stop_timer(task)
  if task.timer and not task.timer:is_closing() then
    task.timer:stop()
    task.timer:close()
  end
end

function M.cancel()
  if not pending then
    return
  end
  local task = pending
  pending = nil
  task.cancelled = true
  stop_timer(task)
  if task.process then
    pcall(task.process.kill, task.process, 9)
  end
end

function M.check()
  if require('config.media.synctex').native_enabled() then return true end
  -- Application("Skim").id() can itself trigger a blocking macOS dialog.
  local available = vim.fn.executable(app_path() .. "/Contents/MacOS/Skim") == 1
    and vim.fn.executable("/usr/bin/osascript") == 1
  if not available then
    notify("找不到 Skim，请安装或修复后重试 PDF 预览。")
  end
  return available
end

function M.view(outfile, open, sync, activate)
  M.cancel()
  local native=require('config.media.synctex')
  if native.native_enabled() then
    if sync then return native.forward(outfile,{activate=activate}) end
    return require('config.media.preview').open(outfile,{kind='pdf'})
  end
  local pdf_path = vim.fn.fnamemodify(outfile, ":p")
  local stem = vim.fn.fnamemodify(pdf_path, ":r")
  if sync and vim.fn.filereadable(stem .. ".synctex") == 0 and vim.fn.filereadable(stem .. ".synctex.gz") == 0 then
    sync = false
    notify("当前 PDF 缺少 SyncTeX 映射，只能预览，无法定位源码。请执行 :VimtexCompileSS -g 强制重新编译后再跳转。")
  end
  if activate == nil then
    activate = vim.g.vimtex_view_skim_activate == 1
  end
  local json = vim.json.encode
  local script = {
    "var app = Application(" .. json(app_path()) .. ");",
    "var theFile = Path(" .. json(pdf_path) .. ");",
    "try { var docs = app.documents.whose({ file: { _equals: theFile }});",
    "if (docs.length > 0) app.revert(docs); } catch (e) {};",
  }
  if open then
    table.insert(script, "app.open(theFile);")
    if activate then
      table.insert(script, "app.activate();")
    end
  end
  if sync then
    local options = { "to: app.texLines[" .. (vim.fn.line(".") - 1) .. "]" }
    table.insert(options, "from: Path(" .. json(vim.fn.expand("%:p")) .. ")")
    if vim.g.vimtex_view_skim_reading_bar == 1 then
      table.insert(options, "showingReadingBar: true")
    end
    if vim.g.vimtex_view_skim_no_select == 1 then
      table.insert(options, "selecting: false")
    end
    table.insert(script, "app.documents[0].go({" .. table.concat(options, ", ") .. "});")
  end

  local task = {}
  pending = task
  local ok, process = pcall(vim.system, { "/usr/bin/osascript", "-l", "JavaScript", "-e", table.concat(script, "\n") },
    { text = true }, function(result)
      vim.schedule(function()
        stop_timer(task)
        if task.cancelled or task.timed_out then
          return
        end
        if pending == task then
          pending = nil
        end
        if result.code ~= 0 then
          local detail = vim.trim(result.stderr or ""):sub(1, 300)
          notify("Skim 预览失败：" .. (detail ~= "" and detail or ("退出码 " .. result.code)))
        end
      end)
    end)
  if not ok then
    pending = nil
    notify("无法启动 Skim 预览：" .. tostring(process))
    return false
  end
  task.process = process
  local timeout = math.max(100, tonumber(vim.g.vimtex_view_skim_timeout) or 10000)
  task.timer = vim.defer_fn(function()
    if pending ~= task or task.cancelled then
      return
    end
    task.timed_out = true
    if pending == task then
      pending = nil
    end
    pcall(task.process.kill, task.process, 9)
    notify(("Skim 超过 %g 秒未响应，已取消本次跳转；Neovide 可继续编辑。"):format(timeout / 1000))
  end, timeout)
  return true
end

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("SkimAsyncViewer", { clear = true }),
  callback = M.cancel,
})

return M
