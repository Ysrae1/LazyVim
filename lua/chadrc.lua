-- This file needs to have same structure as nvconfig.lua
-- https://github.com/NvChad/ui/blob/v3.0/lua/nvconfig.lua
-- Please read that file to know all available options :(

---@type ChadrcConfig
local M = {}

M.base46 = {
  theme = "ayu_dark",
  -- Neovide keeps its existing background; the terminal uses Ghostty's glass.
  transparency = not vim.g.neovide,
  theme_toggle = { "ayu_dark", "ayu_light" },
  -- Light / Dark 配色统一保存在 lua/config/appearance/themes/，插件目录只提供基础主题。
  changed_themes = {
    ayu_light = require("config.appearance.themes.ayu_light_customed"),
    ayu_dark = require("config.appearance.themes.ayu_dark_customed"),
  },
  integrations = {
    "bufferline",
    "neo-tree",
    "avante",
    "yazi",
    "dap",
  },
  hl_override = not vim.g.neovide and {
    NeoTreeNormal = { bg = "NONE" },
    NeoTreeNormalNC = { bg = "NONE" },
    NeoTreeWinSeparator = { bg = "NONE" },
  } or {},
}

M.ui = {
  cmp = {
    enabled = false,
    lspkind_text = true,
    style = "default", -- default/flat_light/flat_dark/atom/atom_colored
    format_colors = {
      tailwind = false,
    },
  },

  telescope = { style = "borderless" }, -- borderless / bordered

  statusline = {
    theme = "minimal", -- default/vscode/vscode_colored/minimal
    -- default/round/block/arrow separators work only for default statusline theme
    -- round and block will work for minimal theme only
    separator_style = "round",
    order = { "left_padding", "mode", "file", "git", "%=", "lsp_msg", "%=", "diagnostics", "lsp", "cwd", "cursor" },
    modules = {
      left_padding = "%#ST_EmptySpace#  ",
    },
  },

  -- lazyload it when there are 1+ buffers
  tabufline = {
    enabled = true,
    lazyload = false,
    order = { "ntreeOffset", "buffers", "tabs", "githubprofile", "btns" },
    modules = {

      ntreeOffset = function()
        local strep = string.rep

        local function getNeoTreeWidth()
          for _, win in pairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.bo[vim.api.nvim_win_get_buf(win)].ft == "neo-tree" then
              return vim.api.nvim_win_get_width(win)
            end
          end
          return 0
        end

        local w = getNeoTreeWidth()

        local function get_os_name()
          local sysname = vim.loop.os_uname().sysname
          return sysname
        end
        local function getNeoTreeTitle()
          local sysname = get_os_name()
          if sysname == "Darwin" then
            return "   File Explorer" -- macOS 图标
          elseif sysname == "Linux" then
            return "   File Explorer" -- Linux 图标
          elseif sysname == "Windows_NT" then
            return "   File Explorer" -- Windows 图标
          else
            return "  File Explorer" -- 默认文本
          end
        end

        local neo_tree_title = getNeoTreeTitle()
        local len_title = #neo_tree_title - 2

        local function deftitle()
          if w <= len_title then
            return string.sub(neo_tree_title, 0, w)
          else
            return neo_tree_title .. strep(" ", w - len_title)
          end
        end

        local defdtitle = deftitle()

        return w == 0 and "" or "%#NeoTreeNormal#" .. defdtitle .. "%#NeoTreeWinSeparator#" .. "│"
      end,

      btns = function()
        local btn = require("nvchad.tabufline.utils").btn
        local toggle_theme = btn(" " .. vim.g.toggle_theme_icon, "ThemeToggleBtn", "Toggle_theme")

        vim.cmd([[
          function! TbSaveAndQuit(a,b,c,d)
              silent! wa
              silent! qa
          endfunction
          ]])
        local closeAllBufs = btn("  ", "CloseAllBufsBtn", "SaveAndQuit")
        return toggle_theme .. closeAllBufs
      end,

      githubprofile = function()
        local btn = require("nvchad.tabufline.utils").btn

        vim.cmd([[
  function! TbOpenGitHubProfile(a,b,c,d)
      if has('macunix')
  
  silent !open 'https://github.com/Ysrae1' > /dev/null 2>&1
      elseif has('win32') || has('win64')
          silent !start https://github.com/Ysrae1
      else
          silent !xdg-open 'https://github.com/Ysrae1' > /dev/null 2>&1
      endif
  endfunction
  ]])

        local open_profiles = btn("  Ysrae1 ", "TabCloseBtn", "OpenGitHubProfile")

        return open_profiles
      end,
    },
    bufwidth = 21,
  },
}

M.nvdash = { load_on_startup = false }

return M
