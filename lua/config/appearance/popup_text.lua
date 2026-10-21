-- 弹窗文字集中调色：选择器、插件管理器、快捷键提示和右上角消息。
-- 保存后执行 :lua require('config.appearance.popup_text').reload()
-- 支持 UI 色槽（light_grey）、语法色槽（base05）、#RRGGBB；false 不覆盖当前配色。
-- Light / Dark 可独立调整；这里只映射元素，不改 Ayu 色板或代码注释。
local M = {}

M.config = {
  body = { light = "base05", dark = "base05" }, -- 普通弹窗正文、文件名、插件名。
  path_prefix = { light = "base05", dark = "base05" }, -- Recent 等文件列表的目录前缀。
  secondary = { light = "base05", dark = "base05" }, -- 耗时、标签、说明和弱化文字。
  count = { light = "base05", dark = "base05" }, -- 选择器右上角 23/23 等计数。
  notification_body = { light = "base05", dark = "base05" }, -- 右上角消息正文。
  notification_detail = { light = "base05", dark = "base05" }, -- 消息内嵌的 Comment / NonText 文字，仅作用于消息窗口。
  notification_title = { light = false, dark = false }, -- false 沿用原来的消息等级色；可改为 green / base05 等。
}

-- 同类元素共用上面的颜色。想单独调某一组，在 overrides 中添加同名条目。
M.overrides = {
  -- SnacksPickerDir = { light = "folder_bg", dark = "base05" },
  -- LazyComment = { light = "base05", dark = "light_grey" },
  -- SnacksNotifierTitleInfo = { light = "green", dark = "green" },
}

local groups = {
  body = {
    "LazyNormal",
    "LazyButton",
    "MasonNormal",
    "WhichKeyNormal",
    "TelescopeNormal",
    "TelescopePromptNormal",
    "TelescopeResultsNormal",
    "TelescopePreviewNormal",
    "SnacksPicker",
    "SnacksPickerInput",
    "SnacksPickerList",
    "SnacksPickerPreview",
    "SnacksPickerFile",
    "SnacksInputNormal",
    "FFFFileInfoValue",
    "GlowPopupBody",
  },
  path_prefix = { "SnacksPickerDir", "SnacksPickerLink", "TelescopeResultsComment", "GlowPopupPath" },
  secondary = {
    "LazyComment",
    "LazyDimmed",
    "LazyProp", -- 总数、耗时、任务消息、属性名。
    "MasonMuted",
    "WhichKeySeparator",
    "WhichKeyValue",
    "SnacksPickerComment",
    "SnacksPickerDesc",
    "SnacksPickerDimmed",
    "SnacksPickerPathHidden",
    "SnacksPickerPathIgnored",
    "SnacksPickerBufFlags",
    "SnacksPickerKeymapRhs",
    "FFFFileInfoLabel",
    "FFFFileInfoValueDim",
    "GlowPopupSecondary",
    "NoiceFormatEvent",
    "NoiceFormatKind",
    "NoiceLspProgressTitle",
  },
  count = { "SnacksPickerTotals", "TelescopePromptCounter" },
  notification_body = { "NoicePopup", "NoiceMini", "NoiceSplit", "SnacksNotifierMinimal", "SnacksNotifierHistory" },
  notification_title = { "SnacksNotifierHistoryTitle" },
}
for _, level in ipairs({ "Trace", "Debug", "Info", "Warn", "Error" }) do
  table.insert(groups.notification_body, "SnacksNotifier" .. level)
  table.insert(groups.notification_title, "SnacksNotifierTitle" .. level)
end

local function color(value, palette)
  if type(value) == "table" then
    value = value[vim.o.background]
  end
  if not value then
    return nil
  end
  local base46 = package.loaded.base46
  if not base46 then
    return nil
  end
  -- One ephemeral palette per apply batch. Base46's legacy getter also probes
  -- missing user-theme modules, so repeating it for every group blocks the UI.
  palette = palette or {}
  if not palette.ui then
    palette.ui, palette.syntax = base46.get_theme_tb("base_30"), base46.get_theme_tb("base_16")
  end
  local resolved = palette.ui[value] or palette.syntax[value] or value
  assert(
    type(resolved) == "string" and resolved:match("^#%x%x%x%x%x%x$"),
    "未知弹窗文字颜色：" .. tostring(value)
  )
  return tonumber(resolved:sub(2), 16)
end

function M.apply()
  if not package.loaded.base46 then
    return
  end
  local palette = {}
  for role, names in pairs(groups) do
    for _, name in ipairs(names) do
      local setting = M.overrides[name]
      if setting == nil then
        setting = M.config[role]
      end
      local fg = color(setting, palette)
      -- 不提前创建尚未加载插件的组，以免遮住插件 default=true 的背景／样式。
      if fg and (name:match("^GlowPopup") or vim.fn.hlexists(name) == 1) then
        local source = name == "GlowPopupBody" and "NormalFloat" or name
        local attrs = vim.fn.hlexists(source) == 1 and vim.api.nvim_get_hl_by_id(vim.fn.hlID(source), true) or {}
        attrs.foreground = fg
        vim.api.nvim_set_hl(0, name, attrs)
      end
    end
  end
end

-- :Inspect 等消息可能嵌用全局弱色；仅在通知 namespace 内替换，不影响代码预览中的注释。
function M.window_overrides(filetype, mapping)
  local notification = filetype:match("^snacks_notif") or filetype == "noice" or filetype == "notify"
  for _, target in pairs(mapping) do
    notification = notification
      or target:match("^SnacksNotifier")
      or target:match("^NoicePopup$")
      or target:match("^NoiceMini$")
      or target:match("^NoiceSplit$")
  end
  -- Window overrides form their own batch; never retain colors across themes.
  local fg = notification and color(M.config.notification_detail, {})
  return fg and { NonText = { fg = fg }, Comment = { fg = fg } } or {}
end

function M.reload()
  package.loaded["config.appearance.popup_text"] = nil
  -- 先完成底材/默认链接的刷新，再应用文字并更新现有浮窗 namespace。
  require("config.appearance.transparency").apply()
  vim.cmd("redraw!")
end

return M
