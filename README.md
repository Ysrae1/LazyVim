# Neovim 配置 · Neovide Glow 固定版

这套个人配置以 [LazyVim](https://github.com/LazyVim/LazyVim) 为基础，结合 NvChad／Base46 的主题与界面，保留原有 Neo-tree 侧栏、标签栏、终端、Yazi、macOS 快捷键和 Avante AI 侧栏。上一公开总安装环境冻结为 **`glow-stack-20261020-gm1`**，其中的字母雨版本为 **`cmatrix-gm-20261017`**。

## 配色冻结与回滚

当前配色与编辑配置的发布候选为 **`glow-stack-20261023-gm1`**，Neovide 仓库中的便携配置副本使用同名标签；下载入口仍指向已公开的固定发行版，候选包以新发行页的实际资产为准。旧 `ayu-colors-20261018-v1`、2026-10-19 gm1、gm2 标签与下载均保留。

各平台的主题文件统一位于各自配置中的 `lua/config/appearance/themes/ayu_light_customed.lua` 与 `ayu_dark_customed.lua`。Mac 与 Windows 的整个 `~/.config/nvim` 分开维护，路径约定相同，参数和配色各自独立；公共功能只逐文件核对同步，不用 Mac 整份配置覆盖 Windows。两份主题使用相同字段结构；Base46 的主题标识仍为 `ayu_light`／`ayu_dark`。插件映射、自动浅深切换、Neo-tree 状态色及选区加粗一起保存。

在 LazyVim 配置仓库中，先提交或备份后续修改，再恢复这版配色：

```sh
git fetch origin --tags
git restore --source glow-stack-20261023-gm1 -- lua/config/appearance lua/chadrc.lua
```

完整版本可通过该标签单独检出；对应插件仍由 `lazy-lock.json` 和 `stable_plugins.lua` 固定。多光标入口及添加编辑点均为 `空格 m`，`Ctrl+p` 撤销新选点；Extend 中可直接使用 `gU`／`gu` 转换选区大小写。

## 安装与适用范围

优先使用 [Neovide Glow 固定发行包](https://github.com/Ysrae1/neovide/releases/tag/glow-stack-20261020-gm1)，并按 [部署说明](https://github.com/Ysrae1/neovide/blob/glow-stack-20261020-gm1/portable/DEPLOY.md) 操作。说明同时适合人工部署或交给 Codex 协助部署。

**没有安装过 Neovim 也可以使用总安装包。** 安装器会取得并校验固定版本的 Neovim、插件、Yazi、字母雨和运行库，建立独立环境；只复制本配置目录不能代替完整安装。新电脑仍需先准备部署说明列出的系统工具与引导 Python。

- Apple Silicon Mac：使用随包提供的 Glow App，仍通过 DMG 将 Neovide 拖入 Applications；保留浅色原生分层图标，不含 dark variation。
- Windows x64：原生 Neovide 窗口配合 Ubuntu 24.04 WSL2 后端。需先完成 WSL 首次用户设置；Windows 实机的编译和交互验收仍待完成，不能视为已通过。

总安装包不覆盖原来的 Neovim 配置，也不复制账号凭据。启动时使用安装器生成的专用入口，避免误用系统里的其他配置或 Neovim 版本。

## 固定依赖与日常维护

发行包记录核心下载的 SHA256、插件提交、Treesitter grammar 和 Mason 工具版本。`lazy-lock.json` 配合 `lua/config/stable_plugins.lua` 使用；插件与语言工具不在日常启动时自动升级。FFF 固定为 **v0.11.0**。

需要升级时，应在独立环境中修改清单、完成相关验证后再形成新版本；不要把手动运行 `:Lazy update` 或 `:MasonUpdate` 当作这份固定版的常规安装步骤。Mason 的顶层版本已固定，但其历史传递依赖没有完整锁定，完整复现的限制详见部署说明。冻结记录见总仓库的 [版本日志](https://github.com/Ysrae1/neovide/blob/glow-stack-20261020-gm1/portable/CHANGELOG.md)。

## 配置目录

日常调整从 `lua/config/` 查找；`lua/chadrc.lua` 负责连接主题与 NvChad 界面。文件名统一用下划线，插件按用途分组。

`init.lua` 只调用 `config.bootstrap.setup()`；启动先后顺序集中在 `config/bootstrap.lua`，媒体注册集中在 `config/media/init.lua`。内部语言实现归入 `config/locale/`，公共入口仍为 `config.platform.locale`。日常配色、材质、字体、快捷键及公开 `reload()` 路径保持原位。

```text
lua/
├── chadrc.lua
├── config/
│   ├── bootstrap.lua                                    # 应用启动顺序
│   ├── options.lua · keymaps.lua · autocmds.lua · lazy.lua  # LazyVim 约定入口
│   ├── appearance/
│   │   ├── themes/{ayu_light_customed,ayu_dark_customed}.lua                 # Light / Dark 完整调色板
│   │   └── editor_highlights.lua · ui.lua · completion.lua · fff.lua · yank.lua
│   │       base46.lua · startup.lua · terminal.lua · intro.lua
│   ├── platform/{neovide,macos_keymaps,locale}.lua    # 平台适配与稳定语言入口
│   ├── locale/                                           # 语言词典、诊断与各插件的内部适配
│   ├── media/init.lua                                    # 媒体注册；实现和参数留在媒体模块
│   ├── navigation/{project_root,neo_tree}.lua              # 项目根目录、侧栏渐隐
│   ├── latex/skim.lua                                     # PDF 双向跳转
│   ├── editor/{settings,toggles}.lua                      # 编辑选项与开关
│   ├── lsp/{pyright,clangd,texlab}.lua                     # 各语言运行环境
│   └── stable_plugins.lua                                 # 固定插件版本
└── plugins/
    ├── init.lua                                          # 按原顺序显式导入
    └── {appearance,editor,navigation,languages,tools,ai}/   # 各插件配置
archive/
├── disabled_plugins/                                     # 未启用的插件草稿
└── legacy/                                               # 原有旧文件
```

- 改语法颜色：`config/appearance/themes/`；改插件颜色映射：`config/appearance/ui.lua`、`completion.lua`、`fff.lua`；复制反馈：`yank.lua`。
- Neo-tree 的“（1个隐藏项目）”等提示字色：`config/appearance/tree_message.lua` 的 `config.light`／`config.dark`，支持 `#RRGGBB` 或主题色槽，`false` 保留原色；同组的空目录等提示一起生效。Mac／Windows 都修改各自配置中的同名文件，配色独立。保存后执行 `:lua require('config.appearance.tree_message').reload()`；只改字色，保留背景、斜体与透明度。
- 改光标行、同名引用、Visual 与多光标选区：`config/appearance/editor_highlights.lua`，颜色、透明度、样式和行为均有中文注释。`references.outline` 控制新版 Neovide 的细框，`references.style.sp` 设置框色；旧前端保留底色。它会在主题和透明处理后重新应用。
- 改光标本体颜色：两份主题的 `polish_hl.defaults.Cursor`；`bg` 为光标色，`fg` 为覆盖字符色。Neovide 已显式绑定此组，保留各模式形状和终端的 `TermCursor`。
- 浮窗材质与透明度逐类设置在 `config/appearance/popup_materials.lua`：`opaque` 使用原实心底色，`editor` 跟随主编辑区，`custom` 独立设置 `blend=0..100` 和可选背景色。Avante 整个侧栏由 `avante` 项统一管理，正文、边框、间隙及胶囊外侧随编辑区，语义实心按钮保留；Notebook 输出及其他类别按各项配置生效。保存后执行 `:lua require('config.appearance.popup_materials').reload()`；公共逻辑在 `popups.lua`，普通编辑区、Neo-tree及底栏仍由原入口管理。
- Mac 编辑区背景不透明度在 `config/platform/macos_appearance.lua`：分别设置 `light.normal_opacity`／`dark.normal_opacity`（0透明、1实心），保存后执行 `:lua require('config.platform.macos_appearance').reload()`。`:GlowGlass opacity 0.85` 临时调整并即时更新 Avante；`:GlowGlass reset` 恢复当前主题默认。Windows 独立参数不受此入口影响。
- Snacks／Telescope 的输入、结果、预览标题使用前端显式 `centered_caption` 角色，按可见文字墨迹校正水平居中；旧前端保留网格布局，字体／背景／配色不变。
- Java 语法高亮沿用现有 Ayu 映射，需固定 Java Treesitter parser；当前维护清单共57项。Mac／Windows ARM64／x64已补齐验证；语法高亮与JDK／jdtls运行或语言服务相互独立。
- Notebook 输出：点击内联输出可选中对应单元格，`空格 j o` 从原位置向下展开；`h/l` 左右滚动，`j/k` 或滚轮上下滚动，`v/V` 选中后 `y` 复制，`空格 y` 复制到系统剪贴板。`q/Esc`、点击框外或在框外滚动可收起。内联输出仅在实际折叠／裁切时显示展开快捷键胶囊；展开框右下角固定显示 `󰕎 q / Esc` 收起提示，横纵滚动时不随正文移动。Mac／Windows 使用同一布局与主题胶囊；Mac 的展开输出框不投影，其他浮窗阴影保留；底边嵌入需支持该能力的新 Neovide，旧前端安全回退。
- 弹窗文字集中在 `config/appearance/popup_text.lua`：正文、路径前缀、说明、计数、右上角消息正文／嵌入弱色／标题各自设置 Light/Dark，`overrides` 可按组单独改色。覆盖 Snacks 选择器、Lazy、Mason、FFF、WhichKey、Telescope 和 Noice；消息内的弱色只改通知窗口，不影响全局代码注释。保存后执行 `:lua require('config.appearance.popup_text').reload()`。
- 改字体、缩放和 Glow：`config/platform/neovide.lua`；改 Mac 快捷键：`macos_keymaps.lua`。
- 改具体插件：到 `plugins/` 的对应分类查找，例如 `navigation/neo_tree.lua`、`languages/vimtex.lua`、`ai/avante.lua`。增加配置后在 `plugins/init.lua` 明确登记，保留原有导入顺序。

以上 `config/`、`plugins/` 路径均位于 `lua/` 下。`archive/` 中的脚本和插件草稿不会加载；旧偏好文件只供首次迁移读取。

修改 `editor_highlights.lua` 后，执行 `:lua require('config.appearance.editor_highlights').reload()` 可立即重载颜色、加粗/下划线和行背景透明度；光标行开关/范围、同名项延迟/模式、Visual 边界规则等行为设置在下次打开 Neovim 时完整生效。同名项由 Snacks.words 调用语言服务提供语义引用，语言服务不支持时不显示；Visual 选区与搜索高亮彼此独立。

各平台的 Light / Dark 文件保存后，在 Neovim 依次执行以下两行即可重新读取并应用当前主题（主题文件顶部的单主题重载命令也适用）：

```vim
:lua for _, name in ipairs({"ayu_light", "ayu_dark"}) do local mod = "config.appearance.themes." .. name .. "_customed"; package.loaded[mod] = nil; require("nvconfig").base46.changed_themes[name] = require(mod) end
:lua require("base46").load_all_highlights()
```

Windows 日常编辑自己的 `~/.config/nvim/lua/config/appearance/themes/`，包含完整配色及高亮参数；x64／ARM64 入口共用这份 Windows 配置。加载器使用当前 `stdpath("config")` 对应的标准主题模块；已有 home 配置桥接会将它指向该用户目录，尚未迁移的独立安装则使用自己的 profile 配置。不再优先读取旧 `%LOCALAPPDATA%\NeovideGlow\appearance\themes\`，旧文件仅保留备份。同步／升级应保留 Windows 已有文件，只有新安装缺少配置时提供默认，不把 Windows 配色复制回 Mac。

Windows 两份文件保存后执行 `:lua require('config.platform.windows_themes').reload()`，重新应用当前主题。该入口在 Mac / Linux 不执行操作。嵌入式 Yazi 的后备配色也读取同一平台入口。

个人状态不写回配置目录：语言偏好保存在 `stdpath("state")/preferences/language.txt`，缩放设置继续保存在 `stdpath("state")/neovide/`。

## 字母雨

Neovide GUI 使用 [cmatrix-gm](https://github.com/Ysrae1/cmatrix-gm/tree/cmatrix-gm-20261017)，以 C 实现 Gomatrix 风格的逐串独立速度、125 个混合字符与白／银灰亮头。字符集包括大小写英文字母、数字及半角日文字符；浊音和半浊音符单独占一格，避免与前一个字符反复叠加。尾部以原字符亮度乘渐隐曲线，**不改变透明度**。

- 全屏开场：`cmatrix-gm --intro --fps 60 --fade 4 -o`。程序先在后台预演到铺开的中间帧，显示后始终按普通速度的 **2.5 倍匀速**下落；`lua/config/appearance/intro.lua` 在两秒时结束任务并清理浮窗和缓冲区。
- 六行首页：`cmatrix-gm --fps 60 --fade 4 --length 9:13 -o`，使用适合小区域的较长雨串。入口在 `lua/plugins/appearance/snacks.lua`。
- 单独运行：`cmatrix-gm --fps 60 --fade 4`。普通模式的长度参数范围为 13～21 格；`--fade 0` 关闭尾部渐隐。`--fps` 控制刷新上限，不代表每串的下落速度。

原 `cmatrix-uni` 的 Unimatrix 风格模式独立保留；终端中的 Neovim 首页继续使用原 CMatrix。这些模式不互相替代。缺少 GUI 开场程序时会跳过开场，不阻止编辑器启动。

本机 `nvidec` 入口通过 `NVIM_SKIP_MATRIX_INTRO=1` 跳过全屏开场；首页的六行字母雨仍按原设置显示。

## 常用入口

| 操作 | 入口 |
| --- | --- |
| FFF 找文件 | `空格 t f` |
| Telescope 首页入口 | `f` 找文件、`g` 找文字、`r` 最近文件、`c` 配置 |
| Telescope 全部文件 | `空格 t a` |
| Yazi | `:Yazi`，首页 `y` |
| 首页 | `:Dashboard` |

其他原有 leader、Ctrl 与 AI 侧栏快捷键保留。macOS 的 Command 映射只在 Mac 启用。主题与标签栏可从 `lua/chadrc.lua` 调整；GUI 字体及 Glow 参数见 `lua/config/platform/neovide.lua`，配套字体为 FiraCode Nerd Font Mono。

## AI 与公式

Avante 保留原侧栏与快捷键，通过固定版本 Codex ACP 接入 **部署电脑上使用者自己的 ChatGPT 登录**。首次使用按部署说明，在实际后端环境中运行 `codex login` 并完成浏览器授权；WSL 需要在 WSL 中登录。安装包和配置仓库不包含、也不分发 `auth.json`、API 密钥、账号目录或会话。

Markdown／AI 侧栏的公式转换依赖随环境安装的 `pylatexenc`。生成完整 LaTeX PDF 仍需额外安装 TeX Live／MacTeX 及可用的 PDF 查看器；公式显示与完整文档编译是两项功能。

## 致谢

- 配置以 [LazyVim](https://github.com/LazyVim/LazyVim) 和 [LazyVim starter](https://github.com/LazyVim/starter)（Apache-2.0）为基础；界面与主题机制来自 [NvChad](https://github.com/NvChad) 的 ui（GPL-3.0）和 Base46（MIT）。
- Ayu Light／Dark 配色源自 Ike Ku 的 [ayu](https://github.com/dempfi/ayu)（MIT），经由 Base46 的 ayu 主题，每个颜色再由 Ysrae1 逐一调整。
- Notebook 的编辑与执行使用 [Molten](https://github.com/benlubas/molten-nvim) 和 [jupytext.nvim](https://github.com/GCBallesteros/jupytext.nvim)。静态预览内嵌 [KaTeX](https://github.com/KaTeX/KaTeX) 与 [markdown-it](https://github.com/markdown-it/markdown-it)（均为 MIT），许可原文见 `lua/config/media/assets/THIRD-PARTY-NOTICES.md`。
- 字母雨由 [cmatrix-gm](https://github.com/Ysrae1/cmatrix-gm) 提供，改编自 [CMatrix](https://github.com/abishekvashok/cmatrix)（GPL-3.0），并参考 [Unimatrix](https://github.com/will8211/unimatrix) 与 [Gomatrix](https://github.com/GeertJohan/gomatrix) 的效果。
- 其余插件按 `lazy-lock.json` 固定的提交，从各自仓库安装，并保留各自的许可证。
