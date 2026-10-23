-- VimTeX a50f407 / WhichKey 3aab2147. Description-only metadata for existing
-- buffer-local mappings; no keymap, compiler, viewer or VimTeX state changes.
local M = {}
local registered = {}
local labels = {
  ["info"] = { "VimTeX Project Information", "VimTeX 项目信息" },
  ["info-full"] = { "VimTeX Full Project Information", "VimTeX 完整项目信息" },
  ["reload"] = { "Reload VimTeX Scripts", "重新加载 VimTeX 脚本" },
  ["reload-state"] = { "Reload VimTeX Buffer State", "重新加载 VimTeX 缓冲区状态" },
  ["toggle-main"] = { "Switch Main or Current LaTeX File", "切换 LaTeX 主文件／当前文件" },
  ["log"] = { "VimTeX Message Log", "VimTeX 消息日志" },
  ["context-menu"] = { "LaTeX Context Actions", "LaTeX 上下文操作" },
  ["compile"] = { "Toggle Continuous LaTeX Compilation", "切换 LaTeX 持续编译" },
  ["compile-ss"] = { "Compile LaTeX Once", "单次编译 LaTeX" },
  ["compile-output"] = { "LaTeX Compiler Output", "查看 LaTeX 编译器输出" },
  ["compile-selected"] = { "Compile Selected LaTeX Lines", "编译选中的 LaTeX 行" },
  ["stop"] = { "Stop Current LaTeX Compilation", "停止当前 LaTeX 项目编译" },
  ["stop-all"] = { "Stop All LaTeX Compilations", "停止所有 LaTeX 项目编译" },
  ["errors"] = { "LaTeX Errors and Warnings", "查看 LaTeX 错误和警告" },
  ["clean"] = { "Clean LaTeX Auxiliary Files", "清理 LaTeX 辅助文件" },
  ["clean-full"] = { "Clean LaTeX Auxiliary and Output Files", "清理 LaTeX 辅助及输出文件" },
  ["status"] = { "Current LaTeX Compilation Status", "查看当前 LaTeX 项目编译状态" },
  ["status-all"] = { "All LaTeX Compilation Statuses", "查看所有 LaTeX 项目编译状态" },
  ["toc-open"] = { "Open LaTeX Table of Contents", "打开 LaTeX 文档目录" },
  ["toc-toggle"] = { "Toggle LaTeX Table of Contents", "显示／隐藏 LaTeX 文档目录" },
  ["view"] = { "View LaTeX PDF and Forward Search", "查看 LaTeX PDF／正向定位" },
  ["reverse-search"] = { "LaTeX Inverse Search", "LaTeX 反向定位" },
  ["imaps-list"] = { "LaTeX Insert-Mode Shortcuts", "查看 LaTeX 插入模式快捷键" },
}

local function prefix()
  local value = vim.g.vimtex_mappings_prefix or "<localleader>l"
  value = value:gsub("<[Ll][Oo][Cc][Aa][Ll][Ll][Ee][Aa][Dd][Ee][Rr]>", function()
    return vim.g.maplocalleader or "\\"
  end)
  value = value:gsub("<[Ll][Ee][Aa][Dd][Ee][Rr]>", function() return vim.g.mapleader or "\\" end)
  return vim.api.nvim_replace_termcodes(value, true, true, true)
end

local function map_at(buf, mode, lhs)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if map.lhs == lhs then return map end
  end
end

local function description(buf, mode, lhs, rhs, row)
  return function()
    local actual = map_at(buf, mode, lhs)
    -- A later user remapping/description always wins over this old metadata.
    if not actual then return "" end
    if actual.desc and actual.desc ~= "" then return actual.desc end
    if actual.rhs ~= rhs then return actual.rhs or "" end
    return row[require("config.platform.locale").current() == "zh" and 2 or 1]
  end
end

function M.refresh(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local wk = package.loaded["which-key"]
  if not wk or not vim.api.nvim_buf_is_loaded(buf) or vim.b[buf].vimtex == nil then return 0 end
  local ft = vim.bo[buf].filetype
  if ft ~= "tex" and ft ~= "plaintex" and ft ~= "bib" then return 0 end
  local start, spec, count, modes = prefix(), {}, 0, {}
  registered[buf] = registered[buf] or {}
  for _, mode in ipairs({ "n", "x" }) do
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
      local lhs = vim.api.nvim_replace_termcodes(map.lhs, true, true, true)
      local name = map.rhs and map.rhs:match("^<[Pp][Ll][Uu][Gg]>%(vimtex%-(.-)%)$")
      local row = name and labels[name]
      if name == "compile-selected" and mode == "n" then
        row = { "Compile LaTeX Lines (Next Motion)", "编译指定的 LaTeX 行（接动作）" }
      end
      if row and lhs:sub(1, #start) == start then
        modes[mode] = true
        count = count + 1
        local id = mode .. ":" .. map.lhs
        if not registered[buf][id] then
          spec[#spec + 1] = { map.lhs, buffer = buf, mode = mode, real = true,
            desc = description(buf, mode, map.lhs, map.rhs, row) }
          registered[buf][id] = true
        end
      end
    end
  end
  for mode in pairs(modes) do
    local id = mode .. ":group:" .. start
    if not registered[buf][id] then
      spec[#spec + 1] = { start, buffer = buf, mode = mode, group = function()
        local locale = require("config.platform.locale")
        if type(locale.translate) == "function" then return locale.translate("LaTeX", "LaTeX功能") end
        return locale.current() == "zh" and "LaTeX功能" or "LaTeX"
      end }
      registered[buf][id] = true
    end
  end
  if #spec > 0 then wk.add(spec, { create = false }) end
  -- VimTeX adds its maps at the end of FileType initialization, after WhichKey
  -- may have cached this buffer. Rebuild just its tree/trigger metadata.
  local cache = package.loaded["which-key.buf"]
  if cache then cache.clear({ buf = buf }) end
  return count
end

function M.refresh_all()
  local count = 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then count = count + M.refresh(buf) end
  end
  return count
end

function M.setup()
  local group = vim.api.nvim_create_augroup("GlowVimtexLocale", { clear = true })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "VimtexEventInitPost",
    callback = function(ev) M.refresh(ev.buf) end })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "LazyLoad", callback = function(ev)
    if ev.data == "which-key.nvim" then M.refresh_all() end
  end })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "GlowLanguageChanged", callback = function()
    -- Descriptions are getters, so language changes do not register duplicates.
    local state = package.loaded["which-key.state"]
    if state and state.state then state.update() end
  end })
  vim.api.nvim_create_autocmd("BufWipeout", { group = group, callback = function(ev) registered[ev.buf] = nil end })
  return M.refresh_all()
end
return M
