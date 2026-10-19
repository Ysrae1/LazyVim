-- Ayu Dark：当前配色的本地配置，与另一个主题保持相同字段顺序。
-- 由 chadrc.base46.changed_themes.ayu_dark 加载；只影响 Dark。
-- 来源：Ike Ku 的 ayu 配色（https://github.com/dempfi/ayu，MIT），经 NvChad Base46 的 ayu 主题；各颜色由 Ysrae1 逐一调整。
-- syntax 管语法色；ui 管插件/UI 色；polish_hl 管元素映射。
-- 保存后执行 :lua package.loaded["config.appearance.themes.ayu_dark_customed"]=nil; require("nvconfig").base46.changed_themes.ayu_dark=require("config.appearance.themes.ayu_dark_customed"); require("base46").load_all_highlights()
-- 将光标放在元素上执行 :Inspect，可查看实际生效的高亮组。

local syntax = {
  base00 = "#0B0E14", -- 编辑区背景
  base01 = "#1C1F25", -- 次级背景、搜索文字
  base02 = "#24272D", -- 选区背景
  base03 = "#2B2E34", -- 非文本符号、弱化文字
  base04 = "#33363C", -- 次要前景
  base05 = "#C9C7BE", -- 普通变量、正文
  base06 = "#E6E1CF", -- 较亮前景
  base07 = "#D9D7CE", -- 强调前景
  base08 = "#FF8080", -- 成员字段、模块名
  base09 = "#B87AF5", -- 数字、常量、参数
  base0A = "#2EABFF", -- 类型，如 int
  base0B = "#C5F760", -- 字符串
  base0C = "#60F0B2", -- 构造器、转义
  base0D = "#96D7F3", -- 函数定义/调用、文件夹
  base0E = "#FF9D52", -- 关键字、Lua 成员
  base0F = "#F5BE6C", -- 括号、标点、复制反馈
}

-- UI 色槽可独立调节；引用 syntax 的项目会随对应语法色一起变化。
local ui = {
  red = "#FF5A52", -- 错误、删除、文件胶囊
  baby_pink = "#FF8A8A", -- 调试停止、diff 旧文件、终端亮红
  pink = "#FFBEB5", -- Lazy issue、终端亮洋红
  green = "#67D12E", -- LSP 状态、成功、新增
  vibrant_green = "#B5F297", -- Avante 标题、[+] 未保存标记、终端亮绿
  blue = syntax.base0A, -- NORMAL、TABS、匹配文字
  nord_blue = "#49AFE6", -- Lua 图标、GitHub 区域、Avante 副标题
  yellow = "#FFD68A", -- 行列位置、警告、Neo-tree 未跟踪文件
  sun = "#F5B65A", -- Lazy 命令说明、终端亮黄
  purple = syntax.base09, -- Hint、NOTE、紫色图标
  dark_purple = "#9148D9", -- INSERT 模式
  teal = "#40C599", -- 确认模式、补全 Class、终端亮青
  orange = syntax.base0E, -- 项目目录、Neo-tree Git 修改、REPLACE 模式
  cyan = "#52E6B5", -- VISUAL 模式、青色图标
  pmenu_bg = "#95E6CB", -- 补全选中行背景
  white = "#CED4DF", -- 主要 UI 前景
  darker_black = "#05080E", -- 侧栏、浮窗背景
  black = "#0B0E14", -- 主要 UI 背景
  black2 = "#14171D", -- 光标行、次级背景
  one_bg = "#1C1F25", -- 胶囊文字区、菜单背景
  one_bg2 = "#24272D", -- 高一层的背景
  one_bg3 = "#2B2E34", -- 按钮背景
  grey = "#33363C", -- 默认行号、缩进范围提示
  grey_fg = "#3D4046", -- 浮窗边框等弱化前景
  grey_fg2 = "#46494F", -- 辅助背景
  light_grey = "#54575D", -- 注释、未激活文字、灰色图标
  line = "#24272D", -- 分隔线、默认缩进点
  statusline_bg = "#12151B", -- 底栏背景
  lightbg = "#24272D", -- 辅助背景
  folder_bg = "#98A3AF", -- 旧文件树集成的文件夹色
}

return {
  base_16 = syntax,
  base_30 = ui,
  polish_hl = {
    defaults = {
      LineNr = { fg = ui.grey }, -- 相对行号
      Comment = { fg = ui.light_grey }, -- 普通语法注释，与 Treesitter 注释统一。
    },
    blankline = {
      IblChar = { fg = ui.line }, -- 缩进点
    },
    treesitter = {
      -- 显式列出共同映射，便于 Light / Dark 对照调试。
      ["@comment"] = { fg = ui.light_grey }, -- 普通注释；TODO / warning / note / danger 保留各自强调色。
      ["@function"] = { fg = syntax.base0D },
      ["@function.call"] = { fg = syntax.base0D },
      ["@function.builtin"] = { fg = syntax.base0D },
      ["@function.method"] = { fg = syntax.base0D },
      ["@function.method.call"] = { fg = syntax.base0D },
      ["@variable.parameter"] = { fg = syntax.base09 },
      ["@constructor"] = { fg = syntax.base0C },
      ["@tag.delimiter"] = { fg = syntax.base0F },
      ["@tag.attribute"] = { fg = syntax.base08 },
      -- Lua 成员使用关键字色；其他语言保留通用成员色。
      ["@variable.member.lua"] = { fg = syntax.base0E },
      ["@property.lua"] = { fg = syntax.base0E },
      ["@lsp.type.property.lua"] = { link = "@property.lua" },
      PmenuSel = { fg = ui.black, bg = ui.pmenu_bg },
    },
  },
}
