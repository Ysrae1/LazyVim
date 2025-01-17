-- ~/.config/nvim/init.lua

-- 引导 lazy.nvim，如果尚未安装
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- 使用稳定分支
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- 定义 snacks.nvim 的配置
local snacks_opts = {
  bigfile = { enabled = true },

  notifier = {
    enabled = true,
    timeont = 5000,
    style = "fancy",
  },

  dashboard = {
    enabled = false, -- 初始禁用 dashboard
    width = 80,
    row = nil,
    col = nil,
    pane_gap = 4,
    autokeys = "1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
    preset = {
      pick = nil,
      keys = {
        { icon = " ", key = "f", desc = "Find File", action = ":lua require('snacks').dashboard.pick('files')" },
        { icon = " ", key = "n", desc = "New File", action = ":ene | startinsert" },
        { icon = " ", key = "g", desc = "Find Text", action = ":lua require('snacks').dashboard.pick('live_grep')" },
        { icon = " ", key = "r", desc = "Recent Files", action = ":lua require('snacks').dashboard.pick('oldfiles')" },
        {
          icon = " ",
          key = "c",
          desc = "Config",
          action = ":lua require('snacks').dashboard.pick('files', {cwd = vim.fn.stdpath('config')})",
        },
        { icon = " ", key = "s", desc = "Restore Session", action = ":source ~/.config/nvim/session.vim" },
        { icon = "󰒲 ", key = "L", desc = "Lazy", action = ":Lazy", enabled = package.loaded.lazy ~= nil },
        { icon = " ", key = "q", desc = "Quit", action = ":qa" },
      },
      header = [[
███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗
████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║
██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║
██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║
██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║
╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝]],
    },
    formats = {
      icon = function(item)
        return { item.icon, width = 2, hl = "icon" }
      end,
      footer = { "%s", align = "center" },
      header = { "%s", align = "center" },
      file = function(item, ctx)
        local fname = vim.fn.fnamemodify(item.file, ":~")
        fname = ctx.width and #fname > ctx.width and vim.fn.pathshorten(fname) or fname
        if #fname > ctx.width then
          local dir = vim.fn.fnamemodify(fname, ":h")
          local file = vim.fn.fnamemodify(fname, ":t")
          if dir and file then
            file = file:sub(-(ctx.width - #dir - 2))
            fname = dir .. "/…" .. file
          end
        end
        local dir, file = fname:match("^(.*)/(.+)$")
        return dir and { { dir .. "/", hl = "dir" }, { file, hl = "file" } } or { { fname, hl = "file" } }
      end,
    },
    sections = {
      { section = "header", padding = 1, pane =1 },
      {
        section = "terminal",
        cmd = "cmatrix -a -b -u 3 -o",
        random = 10,
        pane = 1,
        height = 6,
        padding = 1,
      },
      { icon = " ", title = "Keymaps", section = "keys", indent = 2, padding = 1, pane =1 },
      { icon = " ", title = "Recent Files", section = "recent_files", indent = 2, padding = 1, pane =1 },
      { icon = " ", title = "Projects", section = "projects", indent = 2, padding = 1, pane =1 },
      { section = "startup" },
    },
  },

  indent = { enabled = true },
  input = { enabled = true },
  quickfile = { enabled = true },
  scroll = { enabled = true },
  statuscolumn = { enabled = true },
  words = { enabled = true },
  styles = {
    notification = {
      wo = { wrap = true },
    },
  },
}

-- 使用 lazy.nvim 设置插件
require("lazy").setup({
  {
    "snacks.nvim",
    priority = 500,
    event = "VeryLazy",
    opts = snacks_opts,

    config = function()
      local Snacks = require("snacks")

      -- 创建全局调试函数（可选）
      _G.dd = function(...)
        Snacks.debug.inspect(...)
      end
      _G.bt = function()
        Snacks.debug.backtrace()
      end
      vim.print = _G.dd -- 重写 print 函数

      -- 创建一些切换映射（可选）
      Snacks.toggle.option("spell", { name = "Spelling" }):map("<leader>us")
      Snacks.toggle.option("wrap", { name = "Wrap" }):map("<leader>uw")
      Snacks.toggle.option("relativenumber", { name = "Relative Number" }):map("<leader>uL")
      Snacks.toggle.diagnostics():map("<leader>ud")
      Snacks.toggle.line_number():map("<leader>ul")
      Snacks.toggle
        .option("conceallevel", { off = 0, on = vim.o.conceallevel > 0 and vim.o.conceallevel or 2 })
        :map("<leader>uc")
      Snacks.toggle.treesitter():map("<leader>uT")
      Snacks.toggle.option("background", { off = "light", on = "dark", name = "Dark Background" }):map("<leader>ub")
      Snacks.toggle.inlay_hints():map("<leader>uh")
      Snacks.toggle.indent():map("<leader>ug")
      Snacks.toggle.dim():map("<leader>uD")

      -- 添加延迟显示 dashboard
      vim.api.nvim_create_autocmd("VimEnter", {
        once = true,
        callback = function()
          vim.defer_fn(function()
            -- 假设 snacks.nvim 提供了 `:SnacksDashboard` 命令来显示 dashboard
            -- 请根据实际插件文档确认命令名称
            vim.cmd("SnacksDashboard")
          end, 3000) -- 延迟 3000 毫秒（3 秒）
        end,
      })
    end,
  },
})