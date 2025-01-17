-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- vim.api.nvim_create_autocmd("OptionSet", {
--     pattern = "background",
--     callback = function()
--         if vim.o.background == "dark" then
--             vim.cmd("colorscheme onehalf-lush-dark")
--         else
--             vim.cmd("colorscheme onehalf-lush")
--         end
--     end
-- })

-- vim.api.nvim_create_autocmd("OptionSet", {
--   pattern = "background",
--   callback = function()
--     local lualine = require("lualine")
--     -- 获取当前配置
--     local config = lualine.get_config()
--     -- 更新主题
--     config.options.theme = vim.o.background == "dark" and "onehalf-lush" or "ayu_light"
--     -- 重新加载配置
--     lualine.setup(config)
--   end,
-- })

vim.api.nvim_create_autocmd("TermOpen", {
  pattern = "*",
  callback = function()
    local path = vim.fn.expand("%:p:h")
    if vim.fn.isdirectory(path) == 1 then
      vim.cmd("lcd " .. path)
    else
      vim.cmd("lcd ~") -- 如果目标路径不存在，切换到用户主目录
    end
  end,
})

-- 当 Neovim 进入终端模式时，自动进入插入模式
vim.api.nvim_create_autocmd("TermOpen", {
  pattern = "*",
  command = "startinsert",
})

-- vim.cmd([[
--   autocmd TermOpen term://*toggleterm#* lcd %:p:h
-- ]])

vim.api.nvim_create_autocmd("BufEnter", {
  pattern = "*",
  command = "silent! lcd %:p:h",
})
