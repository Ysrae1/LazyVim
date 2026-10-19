-- 编辑区行、同名项、Visual 与多光标高亮的手动调节入口。这里只改元素映射，不修改 Ayu 调色板。
-- 保存后重载颜色/透明度：:lua require('config.appearance.editor_highlights').reload()
-- 开关、模式、延迟、选区范围等行为设置在下次打开 Neovim 时完整生效。
-- 查看结果：:hi CursorLine | hi LspReferenceText | hi Visual | hi MultiCursorMain | hi MultiCursor
local M = {}

-- style 中可用：bg 背景、fg 文字、bold 加粗、underline 下划线、italic 斜体。
-- 颜色写 "one_bg" 等 UI 色槽、"base02" 等语法色槽、"#RRGGBB" 或 "NONE"。
-- 色槽随 Light/Dark 变化；十六进制固定颜色；"NONE" 取消该层颜色、露出下层。
-- 不设置 fg 可保留原语法文字色；bold/underline 写 true 开启、false 关闭。
-- 深浅色板见同目录 themes/；只想改高亮强度时优先换下面的槽位，别改公共色板。
M.config = {
  cursorline = {
    enabled = true, -- 光标所在行开关，对应 :set cursorline / nocursorline。
    area = "both", -- both=整行含行号；line=正文整行；number=只有行号；screenline=换行后的当前屏幕行。
    style = { bg = "one_bg2" }, -- 当前：Dark #1C1F25，Light #EBEBEB；one_bg2/one_bg3 对比更强。
    neovide_blend = 20, -- 仅 Neovide 的行背景透明度：0=不混合，100=全透明；文字不受影响。
    -- 普通终端不应用 blend；最终背景透明度由终端自身设置决定。
  },

  references = {
    -- 同名项来自 Snacks.words + LSP documentHighlight：语义引用，不是全文同字搜索。
    -- 语言服务不支持该能力时不出现；[[ / ]] 跳上/下一引用，Alt+p / Alt+n 循环跳转。
    enabled = true,
    debounce = 200, -- 光标停留多久后更新，毫秒；越小响应越快、请求越频繁。
    modes = { "n", "i", "c" }, -- n=普通、i=插入、c=命令行；加 "v" 可在 Visual 时也显示。
    outline = true, -- 新版 Neovide 绘制 1 像素细框；false 关闭。终端及旧前端保留原底色。
    style = { bg = "grey", sp = "blue" }, -- 三类引用共用样式；sp 调节细框颜色。
    text = {}, -- 普通引用 LspReferenceText；例如 { underline = true }。
    read = {}, -- 读取引用 LspReferenceRead；例如 { bg = "one_bg2" }。
    write = {}, -- 写入引用 LspReferenceWrite；例如 { underline = true, sp = "orange" }。
    -- read/write/text 覆盖共用 style；sp 同时控制细框和下划线颜色。LSP 决定引用分类。
  },

  visual = {
    selection = "inclusive", -- inclusive=包含光标字符；exclusive=不含末端字符。
    style = { bg = "visual_selection", bold = true }, -- Visual 选区：Dark #24272D，Light #EEEEEE。
    inactive_style = { fg = "base08", bold = true }, -- VisualNOS：未持有系统选区时的备用样式，是否显示由前端决定。
    -- 修改 selection 只改变选区边界规则，不改变拖拽、复制和多光标的快捷键。
  },

  multicursor = {
    -- 主选区与附加选区独立于 Visual；点光标覆盖一个字符，拖选则覆盖整个所选范围。
    -- 以下保留插件原配色与现有加粗；可改用 "light_grey"、"base02" 等随主题变化的色槽。
    style = { bg = "visual_selection", bold = true }, -- 两组共用样式；可加 fg、underline、italic、sp。
    main = { fg = "yellow" }, -- 当前主选区：MultiCursorMain。
    others = { fg = "yellow" }, -- 其他已添加的选区：MultiCursor。
    -- main / others 的字段覆盖共用 style；例如 others = { bg = "base02", bold = false }。
    neovide_blend = 0, -- 仅 Neovide 的选区背景：0=不混合，100=全透明；普通终端不应用 blend。
    -- 这里只控制显示；添加/撤销光标、Command+拖选和编辑快捷键仍由 multicursors.lua 管理。
  },
}

local function resolve_style(style, base46)
  local ui = base46.get_theme_tb("base_30")
  local syntax = base46.get_theme_tb("base_16")
  local result = vim.deepcopy(style)
  for _, key in ipairs({ "fg", "bg", "sp" }) do
    local value = result[key]
    if type(value) == "string" and value ~= "NONE" and value ~= "none" and value:sub(1, 1) ~= "#" then
      result[key] = assert(ui[value] or syntax[value], "未知高亮色槽：" .. value)
    end
  end
  return result
end

-- options.lua 在启动时调用；不在每次切主题时覆盖用户临时 :set 的设置。
function M.apply_options()
  vim.opt.cursorline = M.config.cursorline.enabled
  vim.opt.cursorlineopt = M.config.cursorline.area
  vim.opt.selection = M.config.visual.selection
  vim.g.snacks_words = M.config.references.enabled
  if vim.g.neovide then
    -- 显式使用主题 polish_hl.defaults.Cursor；省略组名时 GUI 会用默认反色，忽略 Cursor 配色。
    -- 仅绑定颜色，保留各模式已有形状/闪烁，以及终端模式独立的 TermCursor。
    vim.opt.guicursor:append("n-v-c-sm-i-ci-ve-r-cr-o:Cursor/lCursor")
  end
end

-- Snacks 在启动时读取，之后由它管理 LSP 请求、延迟和模式过滤。
function M.words_options()
  local references = M.config.references
  return { enabled = references.enabled, debounce = references.debounce, modes = vim.deepcopy(references.modes) }
end

function M.apply_multicursor_style()
  local base46 = package.loaded.base46
  if type(base46) ~= "table" then
    return
  end
  local config = M.config.multicursor
  for name, key in pairs({ MultiCursor = "others", MultiCursorMain = "main" }) do
    -- 插件尚未加载时不提前创建组；切主题清空组后仍为已加载的插件重建样式。
    if package.loaded.multicursors or vim.fn.hlexists(name) == 1 then
      local style = resolve_style(vim.tbl_extend("force", config.style, config[key]), base46)
      if vim.g.neovide then
        style.blend = config.neovide_blend
      end
      vim.api.nvim_set_hl(0, name, style)
    end
  end
end

function M.apply_selection_style()
  local base46 = package.loaded.base46
  if type(base46) == "table" then
    vim.api.nvim_set_hl(0, "Visual", resolve_style(M.config.visual.style, base46))
    vim.api.nvim_set_hl(0, "VisualNOS", resolve_style(M.config.visual.inactive_style, base46))
  end
  M.apply_multicursor_style()
end

function M.apply()
  local base46 = package.loaded.base46
  if type(base46) ~= "table" then
    return
  end
  -- 兼容层在 Base46 的透明处理和插件主题回调之后调用，终端也保留行背景。
  local cursorline = resolve_style(M.config.cursorline.style, base46)
  if vim.g.neovide then
    cursorline.blend = M.config.cursorline.neovide_blend
  end
  vim.api.nvim_set_hl(0, "CursorLine", cursorline)
  for suffix, key in pairs({ Text = "text", Read = "read", Write = "write" }) do
    local style = vim.tbl_extend("force", M.config.references.style, M.config.references[key])
    vim.api.nvim_set_hl(0, "LspReference" .. suffix, resolve_style(style, base46))
  end
  M.apply_selection_style()
end

function M.reload()
  package.loaded["config.appearance.editor_highlights"] = nil
  require("config.appearance.editor_highlights").apply()
  require("config.appearance.render_roles").setup()
  require("config.appearance.transparency").apply()
  vim.cmd.redraw()
end

return M
