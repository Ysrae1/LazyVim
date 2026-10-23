-- 浮窗底材逐项设置；保存后执行：
-- :lua require('config.appearance.popup_materials').reload()
-- mode="opaque"：沿用原来的不透明弹窗底色。
-- mode="editor"：使用主编辑区 Normal 的 RGB/blend，继承 Neovide 的窗口材质与透明度。
-- mode="custom"：独立 blend=0..100（0=实心，100=背景全透明），文字不参与混合。
-- custom 的 bg 可省略（原弹窗底色），或填现有色槽、#RRGGBB、{light=...,dark=...}；不改色板。
-- 例：snacks_picker_preview={mode="custom",blend=35,bg={light="one_bg",dark="darker_black"}}
-- Neovide 特例：显式 bg 与 Normal 同 RGB 且 blend=0 时仍会继承 normal_opacity；
-- 要独立实心请用 opaque，或保留 custom 默认的、与 Normal 不同的弹窗底色。
local M = {}

M.config = {
  default = { mode = "editor" }, -- 无法可靠识别的普通浮窗。
  notebook_output = { mode = "editor" }, -- Molten / 保存输出的可滚动浮窗。
  avante = { mode = "editor" }, -- Avante 整个侧栏（结果、选区、输入、边框与间隙）。
  lazy = { mode = "editor" }, -- 插件管理器。
  mason = { mode = "editor" }, -- 外部工具管理器。
  snacks_picker = { mode = "editor" }, -- 选择器通用/容器窗口。
  snacks_picker_box = { mode = "editor" }, -- 选择器外框容器。
  snacks_picker_input = { mode = "editor" }, -- 选择器输入框。
  snacks_picker_list = { mode = "editor" }, -- 选择器列表。
  snacks_picker_preview = { mode = "editor" }, -- 选择器预览（包括 filetype=lua/python 等代码预览）。
  snacks_notification = { mode = "editor" }, -- 右上角通知。
  snacks_notification_history = { mode = "editor" }, -- 通知历史独立窗口；若走 picker 则按其子窗分类。
  snacks_input = { mode = "editor" }, -- vim.ui.input 输入。
  snacks_terminal = { mode = "editor" }, -- Snacks 浮动终端，包含 Ctrl+T。
  noice_popup = { mode = "editor" }, -- Noice 普通消息浮窗。
  noice_cmdline = { mode = "editor" }, -- Noice 命令行浮窗。
  noice_confirm = { mode = "editor" }, -- Noice 确认浮窗。
  noice_mini = { mode = "editor" }, -- Noice mini 消息。
  noice_popupmenu = { mode = "editor" }, -- Noice 菜单。
  which_key = { mode = "editor" }, -- 快捷键提示。
  completion_menu = { mode = "editor" }, -- Blink/Cmp 菜单及内建 Pmenu（后者没有普通窗口，单独覆盖其全局底材组）。
  completion_documentation = { mode = "editor" }, -- Blink/Cmp 文档浮窗。
  completion_signature = { mode = "editor" }, -- Blink 签名浮窗。
  lsp_hover = { mode = "editor" }, -- Neovim 内建 LSP hover，以真实 focus_id 识别。
  lsp_signature = { mode = "editor" }, -- Neovim 内建 LSP signature help。
  diagnostic = { mode = "editor" }, -- Neovim 内建诊断浮窗。
  lsp_other = { mode = "editor" }, -- 其它带 lsp_floating_bufnr 的预览。
  telescope_prompt = { mode = "editor" }, -- Telescope 输入。
  telescope_results = { mode = "editor" }, -- Telescope 结果。
  telescope_preview = { mode = "editor" }, -- Telescope 预览。
  fff = { mode = "editor" }, -- FFF 搜索浮窗。
  notification = { mode = "editor" }, -- nvim-notify / notify 文件类型。
  terminal = { mode = "editor" }, -- 其它真实 terminal buffer 的浮窗。
  matrix_intro = { mode = "editor" }, -- 开屏 Matrix 覆盖层。
  matrix_dashboard = { mode = "editor" }, -- Dashboard 内嵌 Matrix 终端。
}

-- 通常只管理真实浮窗；Avante 是唯一显式受控的普通 split 适配。
-- 不根据相邻 editor 的 WinSeparator 映射判断所有权。
local avante_filetypes = {
  Avante = true, AvanteInput = true, AvanteSelectedCode = true,
  AvanteSelectedFiles = true, AvanteTodos = true, AvantePromptInput = true, AvanteConfirm = true,
}
function M.is_avante(win, mapping)
  return vim.w[win].glow_popup_profile == "avante"
    or avante_filetypes[vim.bo[vim.api.nvim_win_get_buf(win)].filetype] == true
    or mapping.Normal == "AvanteSidebarNormal" or mapping.Normal == "AvantePromptInput"
    or mapping.NormalFloat == "AvantePromptInput"
end

-- 优先级：w:glow_popup_profile 显式指定 > 插件 winhighlight 角色 > filetype > LSP 标记/终端 > default。
-- 插件把 LSP 内容转交 Noice/Snacks 时，按实际承载窗口分类，不能只凭 markdown 猜 hover。
function M.classify(win, mapping)
  local explicit = vim.w[win].glow_popup_profile
  if type(explicit) == "string" and M.config[explicit] then
    return explicit
  end
  if M.is_avante(win, mapping) then return "avante" end
  local function has(pattern)
    for _, target in pairs(mapping) do
      if target:match(pattern) then
        return true
      end
    end
    return false
  end
  for _, rule in ipairs({
    { "^SnacksDashboardTerminal$", "matrix_dashboard" },
    { "^SnacksPickerPreview", "snacks_picker_preview" },
    { "^SnacksPickerInput", "snacks_picker_input" },
    { "^SnacksPickerList", "snacks_picker_list" },
    { "^SnacksPickerBox", "snacks_picker_box" },
    { "^SnacksPicker", "snacks_picker" },
    { "^SnacksNotifierHistory", "snacks_notification_history" },
    { "^SnacksNotifier", "snacks_notification" },
    { "^SnacksInput", "snacks_input" },
    { "^NoiceCmdline", "noice_cmdline" },
    { "^NoiceConfirm", "noice_confirm" },
    { "^NoiceMini", "noice_mini" },
    { "^NoicePopupmenu", "noice_popupmenu" },
    { "^NoicePopup", "noice_popup" },
    { "^WhichKey", "which_key" },
    { "^BlinkCmpSignature", "completion_signature" },
    { "^BlinkCmpDoc", "completion_documentation" },
    { "^CmpDoc", "completion_documentation" },
    { "^BlinkCmpMenu", "completion_menu" },
    { "^CmpPmenu", "completion_menu" },
    { "^TelescopePrompt", "telescope_prompt" },
    { "^TelescopeResults", "telescope_results" },
    { "^TelescopePreview", "telescope_preview" },
    { "^FFF", "fff" },
    { "^Lazy", "lazy" },
    { "^Mason", "mason" },
  }) do
    if has(rule[1]) then
      return rule[2]
    end
  end
  local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
  local filetypes = {
    molten_output = "notebook_output",
    lazy = "lazy",
    mason = "mason",
    wk = "which_key",
    snacks_picker_input = "snacks_picker_input",
    snacks_picker_list = "snacks_picker_list",
    snacks_picker_preview = "snacks_picker_preview",
    snacks_layout_box = "snacks_picker_box",
    snacks_notif = "snacks_notification",
    snacks_notif_history = "snacks_notification_history",
    snacks_input = "snacks_input",
    snacks_terminal = "snacks_terminal",
    noice = "noice_popup",
    ["blink-cmp-menu"] = "completion_menu",
    ["blink-cmp-documentation"] = "completion_documentation",
    ["blink-cmp-signature"] = "completion_signature",
    TelescopePrompt = "telescope_prompt",
    TelescopeResults = "telescope_results",
    fff = "fff",
    notify = "notification",
  }
  if filetypes[ft] then
    return filetypes[ft]
  end
  if vim.w[win]["textDocument/hover"] then
    return "lsp_hover"
  end
  if vim.w[win]["textDocument/signatureHelp"] then
    return "lsp_signature"
  end
  if vim.w[win].lsp_floating_bufnr then
    if vim.w[win].line or vim.w[win].cursor or vim.w[win].buffer then
      return "diagnostic"
    end
    return "lsp_other"
  end
  if vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "terminal" then
    return "terminal"
  end
  return "default"
end

local function color(value)
  if type(value) == "table" then
    value = value[vim.o.background]
  end
  if type(value) == "number" and value >= 0 and value <= 0xffffff then
    return math.floor(value)
  end
  local base46 = package.loaded.base46
  if base46 then
    local ui, syntax = base46.get_theme_tb("base_30") or {}, base46.get_theme_tb("base_16") or {}
    value = ui[value] or syntax[value] or value
  end
  assert(type(value) == "string" and value:match("^#%x%x%x%x%x%x$"), "未知浮窗背景颜色：" .. tostring(value))
  return tonumber(value:sub(2), 16)
end

function M.resolve(profile, normal, popup)
  local setting = M.config[profile] or M.config.default
  assert(type(setting) == "table", "浮窗材质配置必须是表：" .. profile)
  local mode = setting.mode or "opaque"
  assert(mode == "opaque" or mode == "editor" or mode == "custom", "未知浮窗材质模式：" .. tostring(mode))
  if mode == "editor" then
    local blend = normal.blend or 0
    if blend == 0 then
      -- 浮窗的边框/留白也要显式继承编辑区透明度，不能依赖 Normal
      -- 同色背景的前端回退，否则内容层透明、外层底板仍可能实心。
      local opacity = tonumber(vim.g.neovide_normal_opacity) or 1
      blend = math.floor((1 - math.max(0, math.min(1, opacity))) * 100 + 0.5)
    end
    -- Avante splits inherit the actual editor material without the separate
    -- Windows floating-popup cap; normal_opacity remains platform/user owned.
    if profile ~= "avante" then
      blend = require("config.platform.windows_appearance").popup_blend(blend)
    end
    return { mode = mode, bg = normal.bg, blend = blend }
  end
  if mode == "opaque" then
    return { mode = mode, bg = popup, blend = 0 }
  end
  local blend = setting.blend or 0
  assert(
    type(blend) == "number" and blend == blend and blend >= 0 and blend <= 100,
    "浮窗 blend 必须在 0..100：" .. profile
  )
  return { mode = mode, bg = setting.bg and color(setting.bg) or popup, blend = math.floor(blend) }
end

function M.reload()
  package.loaded["config.appearance.popup_materials"] = nil
  -- 老会话可能仍缓存统一实心策略，首次重载也要读取新版处理逻辑。
  -- 该模块无定时器或会话状态；窗口自己的 namespace 来源记录继续保留。
  package.loaded["config.appearance.popups"] = nil
  require("config.appearance.transparency").apply()
  vim.cmd("redraw!")
end

return M
