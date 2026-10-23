-- Neo-tree 的“（1个隐藏项目）”等提示文字，对应 NeoTreeMessage。
-- Mac / Windows 都编辑各自 ~/.config/nvim 下的本文件，配色相互独立。
-- 保存后执行 :lua require('config.appearance.tree_message').reload()
local M = {}

M.config = {
  light = "light_grey", -- false 沿用现有颜色；可填 "#RRGGBB"、"light_grey" 或 "base05"。
  dark = "light_grey", -- 两种模式独立设置；这里只改字色，保留斜体、背景和透明度。
}

local original, applied
local group = "NeoTreeMessage"

local function attributes(link)
  -- 直接用全局 ID，避免树窗口的 winhighlight 改变读取结果。
  return vim.api.nvim_get_hl(0, { id = vim.fn.hlID(group), link = link })
end

local function restore()
  if not applied then
    return
  end
  local current = attributes(false)
  if vim.deep_equal(current, applied) then
    vim.api.nvim_set_hl(0, group, original)
  elseif current.fg == applied.fg then
    -- 外部只改了样式时保留它，仅撤回本模块持有的字色。
    local previous = original.link and vim.api.nvim_get_hl(0, { name = original.link, link = false }) or original
    current.fg = previous.fg
    vim.api.nvim_set_hl(0, group, current)
  end
  original, applied = nil, nil
end

local function color(value)
  if not value then
    return nil
  end
  local base46 = package.loaded.base46
  if type(value) == "string" and value:sub(1, 1) ~= "#" and base46 then
    value = base46.get_theme_tb("base_30")[value] or base46.get_theme_tb("base_16")[value] or value
  end
  assert(
    type(value) == "string" and value:match("^#%x%x%x%x%x%x$"),
    "未知 Neo-tree 提示文字颜色：" .. tostring(value)
  )
  return tonumber(value:sub(2), 16)
end

function M.apply()
  -- 插件未加载时不创建组，以免遮住其默认字色／斜体。
  if not package.loaded["neo-tree.ui.highlights"] or vim.fn.hlexists(group) ~= 1 then
    return
  end
  local fg = color(M.config[vim.o.background])
  restore()
  if not fg then
    return
  end
  original = attributes(true)
  local attrs = attributes(false)
  attrs.fg = fg
  vim.api.nvim_set_hl(0, group, attrs)
  applied = attributes(false)
end

function M.reload()
  restore()
  package.loaded["config.appearance.tree_message"] = nil
  require("config.appearance.tree_message").apply()
  vim.cmd("redraw!")
end

return M
