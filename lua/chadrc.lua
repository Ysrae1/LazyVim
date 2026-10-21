-- This file needs to have same structure as nvconfig.lua
-- https://github.com/NvChad/ui/blob/v3.0/lua/nvconfig.lua
-- Please read that file to know all available options :(

---@type ChadrcConfig
local M = {}
require("config.integrations.github").setup()

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
  -- 编辑区行/同名项/选区样式在 config.appearance.editor_highlights 统一调节。
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
      left_padding = "%#ST_EmptySpace# ",
    },
  },

  -- lazyload it when there are 1+ buffers
  tabufline = {
    enabled = true,
    lazyload = false,
    order = { "ntreeOffset", "buffers", "tabs", "githubprofile", "btns" },
    modules = {

      ntreeOffset = function()
        return require("config.appearance.tree_title").get()
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
        return require("config.integrations.github").badge()
      end,
    },
    bufwidth = 21,
  },
}

M.nvdash = { load_on_startup = false }

require("config.appearance.window_drag").setup()

return M
