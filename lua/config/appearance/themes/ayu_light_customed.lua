-- Ayu Light：当前配色的本地配置，与另一个主题保持相同字段顺序。 由 chadrc.base46.changed_themes.ayu_light 加载；只影响 Light。
-- 来源：Ike Ku 的 ayu 配色（https://github.com/dempfi/ayu，MIT），经 NvChad Base46 的 ayu 主题；各颜色由 Ysrae1 逐一调整。
-- syntax 管语法色；ui 管插件/UI 色；polish_hl 管元素映射。
-- 保存后执行 :lua package.loaded["config.appearance.themes.ayu_light_customed"]=nil; require("nvconfig").base46.changed_themes.ayu_light=require("config.appearance.themes.ayu_light_customed"); require("base46").load_all_highlights()
-- 将光标放在元素上执行 :Inspect，可查看实际生效的高亮组。

local syntax = {
  base00 = "#FAFAFA", -- 编辑区背景
  base01 = "#F0F0F0", -- 次级背景、搜索文字
  base02 = "#EEEEEE", -- 选区背景
  base03 = "#DFDFDF", -- 非文本符号、弱化文字
  base04 = "#D2D2D2", -- 次要前景
  base05 = "#5C6166", -- 普通变量、正文
  base06 = "#52575C", -- 较亮前景
  base07 = "#484D52", -- 强调前景
  base08 = "#F07171", -- 成员字段、模块名
  base09 = "#A37ACC", -- 数字、常量、参数
  base0A = "#399EE6", -- 类型，如 int
  base0B = "#86B300", -- 字符串
  base0C = "#4CBF99", -- 构造器、转义
  base0D = "#55B4D4", -- 函数定义/调用、文件夹
  base0E = "#FA8D3E", -- 关键字、Lua 成员
  base0F = "#F2AE49", -- 括号、标点、复制反馈
}

-- UI 色槽可独立调节；引用 syntax 的项目会随对应语法色一起变化。
local ui = {
  red = "#E65050", -- 错误、删除、文件胶囊
  baby_pink = "#FF8282", -- 调试停止、diff 旧文件、终端亮红
  pink = "#FFA5A5", -- Lazy issue、终端亮洋红
  green = "#6CBF43", -- LSP 状态、成功、新增
  vibrant_green = "#94E76B", -- Avante 标题、[+] 未保存标记、终端亮绿
  blue = syntax.base0A, -- NORMAL、TABS、匹配文字
  nord_blue = "#2C91D9", -- Lua 图标、GitHub 区域、Avante 副标题
  yellow = "#FFB62E", -- 行列位置、警告、Neo-tree 未跟踪文件
  sun = "#F3C78B", -- Lazy 命令说明、终端亮黄
  purple = "#9F40FF", -- Hint、NOTE、紫色图标
  dark_purple = "#8627E6", -- INSERT 模式
  teal = "#74C5AA", -- 确认模式、补全 Class、终端亮青
  orange = syntax.base0E, -- 项目目录、Neo-tree Git 修改、REPLACE 模式
  cyan = "#95E6CB", -- VISUAL 模式、青色图标
  pmenu_bg = "#95E6CB", -- 补全选中行背景
  white = "#26292F", -- 主要 UI 前景
  darker_black = "#F3F3F3", -- 侧栏、浮窗背景
  black = "#FAFAFA", -- 主要 UI 背景
  black2 = "#EFEFEF", -- 光标行、次级背景
  one_bg = "#EBEBEB", -- 胶囊文字区、菜单背景
  one_bg2 = "#E1E1E1", -- 高一层的背景
  one_bg3 = "#D7D7D7", -- 按钮背景
  grey = "#CDCDCD", -- 默认行号、缩进范围提示
  grey_fg = "#B9B9B9", -- 浮窗边框等弱化前景
  grey_fg2 = "#ACACAC", -- 辅助背景
  light_grey = "#A0A0A0", -- 注释、未激活文字、灰色图标
  line = "#E1E1E1", -- 分隔线、默认缩进点
  statusline_bg = "#F0F0F0", -- 底栏背景
  lightbg = "#E6E6E6", -- 辅助背景
  folder_bg = "#5C6166", -- 旧文件树集成的文件夹色
}

return {
  base_16 = syntax,
  base_30 = ui,
  polish_hl = {
    defaults = {
      LineNr = { fg = "#B0B0B0" }, -- 相对行号
    },
    blankline = {
      IblChar = { fg = "#B0B0B0" }, -- 缩进点
    },
    treesitter = {
      -- 显式列出共同映射，便于 Light / Dark 对照调试。
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
      PmenuSel = { fg = ui.white, bg = ui.pmenu_bg },
    },
  },
}
