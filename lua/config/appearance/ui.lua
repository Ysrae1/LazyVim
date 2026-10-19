local M = {}

local function apply_mini_icons(colors)
  if type(package.loaded["mini.icons"]) ~= "table" then
    return
  end

  -- Its devicons mock returns these shared color groups and reads them live.
  -- Preserve each icon's chosen group, including the neutral default fallback.
  local palette = {
    Azure = "nord_blue",
    Blue = "blue",
    Cyan = "cyan",
    Green = "green",
    Grey = "light_grey",
    Orange = "orange",
    Purple = "purple",
    Red = "red",
    Yellow = "yellow",
  }
  for name, color in pairs(palette) do
    vim.api.nvim_set_hl(0, "MiniIcons" .. name, { fg = colors[color] })
  end
end

local function apply_devicons(base46)
  local devicons = package.loaded["nvim-web-devicons"]
  if type(devicons) ~= "table" then
    return
  end

  local by_extension = devicons.get_icons_by_extension()
  local by_filename = devicons.get_icons_by_filename()
  local legacy = base46.get_integration("devicons")
  local groups = vim.tbl_keys(legacy)
  table.sort(groups)

  for _, group in ipairs(groups) do
    local name = group:match("^DevIcon(.+)$")
    local key = name and name:lower()
    local icon = key and (by_extension[key] or by_filename[key])
    if icon and icon.name and icon.name ~= "Default" then
      local target = "DevIcon" .. icon.name
      if target:lower() ~= group:lower() then
        local attributes = vim.api.nvim_get_hl(0, { name = group, link = false, create = false })
        if attributes.fg then
          -- Tabufline reads fg directly, so the compatibility group must not link.
          attributes.default = nil
          vim.api.nvim_set_hl(0, target, attributes)
        end
      end
    end
  end
end

local function apply_neo_tree_status(colors)
  if not package.loaded["neo-tree.ui.highlights"] then
    return
  end

  -- Keep state colors local to Neo-tree and preserve each group's styles.
  -- Unstaged already links to Conflict.
  local palette = {
    NeoTreeModified = colors.vibrant_green, -- [+]: unsaved buffer changes
    NeoTreeGitUntracked = colors.yellow,
    NeoTreeGitModified = colors.orange,
    NeoTreeGitConflict = colors.orange,
  }
  for name, color in pairs(palette) do
    local attrs = vim.api.nvim_get_hl(0, { name = name, link = false, create = false })
    attrs.fg = color
    vim.api.nvim_set_hl(0, name, attrs)
  end
end

local function refresh_todo_comments()
  local todo = package.loaded["todo-comments.config"]
  if type(todo) ~= "table" or not todo.loaded then
    return
  end

  -- Todo uses `hi def`: existing colors survive Base46's reload without hi clear.
  -- Rebuild only its generated groups from the configured keyword/color rules.
  for keyword in pairs(todo.options.keywords) do
    for _, prefix in ipairs({ "TodoFg", "TodoBg", "TodoSign" }) do
      vim.api.nvim_set_hl(0, prefix .. keyword, {})
    end
  end
  todo.colors()
end

local function apply_window_picker(colors)
  if type(package.loaded["window-picker"]) ~= "table" then
    return
  end

  for _, group in ipairs({ "WindowPickerStatusLine", "WindowPickerWinBar" }) do
    vim.api.nvim_set_hl(0, group, { fg = colors.black, bg = colors.blue, bold = true })
    vim.api.nvim_set_hl(0, group .. "NC", { fg = colors.white, bg = colors.one_bg2, bold = true })
  end
end

local function apply_dashboard(base46)
  local syntax = base46.get_theme_tb("base_16")
  local palette = {
    Header = syntax.base0A, -- NEOVIM 大标题
    Title = syntax.base0D, -- Keymaps / Recent Files / Projects 栏目名
    Desc = syntax.base0E, -- 菜单关键词、file / directory 标签
    File = syntax.base0E, -- 文件名与项目名
    Icon = syntax.base0E,
    Key = syntax.base0B, -- 右侧快捷键提示
    Footer = syntax.base0D,
    Special = syntax.base0E,
  }
  for name, color in pairs(palette) do
    local group = "SnacksDashboard" .. name
    local attrs = vim.api.nvim_get_hl(0, { name = group, link = false, create = false })
    attrs.fg = color
    attrs.default = nil
    vim.api.nvim_set_hl(0, group, attrs)
  end
  -- 浅色路径前缀跟随相对行号的灰度；深色使用原来的 NonText。
  vim.api.nvim_set_hl(0, "SnacksDashboardDir", {
    link = vim.o.background == "light" and "LineNr" or "NonText",
  })
end

function M.apply_selection_style()
  for _, name in ipairs({ "Visual", "VisualNOS", "MultiCursor", "MultiCursorMain" }) do
    local attrs = vim.api.nvim_get_hl(0, { name = name, link = false, create = false })
    -- Let unloaded plugins define their colors first; keep all existing color/style fields.
    if next(attrs) then
      attrs.bold = true
      if attrs.cterm then
        attrs.cterm.bold = true
      end
      vim.api.nvim_set_hl(0, name, attrs)
    end
  end
end

function M.apply()
  local base46 = package.loaded.base46
  if type(base46) ~= "table" then
    return
  end

  -- System theme changes bypass Base46's click counter. Show the active mode.
  vim.g.icon_toggled = vim.o.background == "light"
  vim.g.toggle_theme_icon = vim.g.icon_toggled and "   " or "   "
  vim.cmd("redrawtabline")

  local colors = base46.get_theme_tb("base_30")
  require("config.appearance.capsules").apply()
  M.apply_selection_style()
  apply_dashboard(base46)
  apply_mini_icons(colors)
  apply_devicons(base46)
  apply_window_picker(colors)
  apply_neo_tree_status(colors)
  refresh_todo_comments()
  require("config.appearance.yank").apply()

  if package.loaded["volt.highlights"] then
    package.loaded["volt.highlights"] = nil
    require("volt.highlights")
  end
end

return M
