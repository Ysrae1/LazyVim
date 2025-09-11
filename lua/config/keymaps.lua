-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local M = {}

M.on_attach = function(client, bufnr)
  local opts = { buffer = bufnr }
  vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
  vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
  vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
  vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
  -- 其他快捷键绑定...
  vim.g.diagnostics_active = true
end

function M.toggle_diagnostics()
  if vim.g.diagnostics_active then
    vim.g.diagnostics_active = false
    vim.diagnostic.disable(nil)
  else
    vim.g.diagnostics_active = true
    vim.diagnostic.enable(nil)
  end
end

local map = vim.keymap.set

local del = vim.keymap.del

map(
  "n",
  "<leader>tn",
  "<cmd>lua require('toggles').toggle_null_ls()<CR>",
  { noremap = true, silent = true, desc = "Toggle null_ls" }
)

-- 键位绑定设置在模块的顶层
map(
  "n",
  "<leader>td",
  '<cmd>lua require("config.keymaps").toggle_diagnostics()<CR>',
  { noremap = true, silent = true, desc = "Toggle diagnostic Visibility" }
)

-- To avoid the confliction to vimtex keymaps.
map("n", "<leader>\\", ":Neotree reveal<cr>", { noremap = true, silent = true })

-- remove some of default setting

-- del("n", "<leader>D")

map("n", "<leader>D", function()
  Snacks.dashboard.open()
  vim.schedule(function()
    vim.cmd("stopinsert")
  end)
end, { desc = "Open Snacks' dashboard" })


-- telescope

local builtin = require("telescope.builtin")

map("n", "<leader>tg", function()
  builtin.live_grep()
end, { desc = "telescope live grep" })
map("n", "<leader>tb", function()
  builtin.buffers()
end, { desc = "telescope find buffers" })
map("n", "<leader>t?", function()
  builtin.help_tags()
end, { desc = "telescope help page" })
map("n", "<leader>tm", function()
  builtin.marks()
end, { desc = "telescope find marks" })
map("n", "<leader>tr", function()
  builtin.oldfiles()
end, { desc = "telescope find oldfiles" })
map("n", "<leader>tz", function()
  builtin.current_buffer_fuzzy_find()
end, { desc = "telescope find in current buffer" })

map("n", "<leader>th", function()
  require("nvchad.themes").open()
end, { desc = "telescope nvchad themes" })

map("n", "<leader>tf", function()
  builtin.find_files()
end, { desc = "telescope find files" })
map("n", "<leader>ta", function()
  builtin.find_files({ follow = true, no_ignore = true, hidden = true })
end, { desc = "telescope find all files" })

-- 定义一个函数来切换窗口并将其高度设置为当前窗口的一半
local function switch_window_and_set_half_height(direction)
  -- 获取 Neovim 的总高度
  local total_height = vim.o.lines
  local cmdheight = vim.o.cmdheight
  local statusline = vim.o.laststatus > 0 and 1 or 0 -- 简单估算状态栏高度
  local total_available_height = total_height - cmdheight - statusline

  -- 计算新的高度（取整）
  local new_height = math.floor(total_available_height / 2)

  -- 设置当前窗口的高度

  -- 切换窗口方向
  if direction == "left" then
    vim.cmd("wincmd H")
  elseif direction == "right" then
    vim.cmd("wincmd L")
  elseif direction == "up" then
    vim.cmd("wincmd K")
    vim.api.nvim_win_set_height(0, new_height)
  elseif direction == "down" then
    vim.cmd("wincmd J")
    vim.api.nvim_win_set_height(0, new_height)
  else
    return -- 无效的方向，退出函数
  end
end

-- 获取 Neovim 的键位映射 API
local keymap = vim.keymap.set

-- 定义键位映射的选项
local opts = { noremap = true, silent = true }

-- 普通模式（Normal Mode）
keymap("n", "<C-S-Left>", function()
  switch_window_and_set_half_height("left")
end, opts)

keymap("n", "<C-S-Right>", function()
  switch_window_and_set_half_height("right")
end, opts)

keymap("n", "<C-S-Up>", function()
  switch_window_and_set_half_height("up")
end, opts)

keymap("n", "<C-S-Down>", function()
  switch_window_and_set_half_height("down")
end, opts)

-- 插入模式（Insert Mode）
keymap("i", "<C-S-Left>", function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-\\><C-n>", true, false, true), "n", true)
  switch_window_and_set_half_height("left")
end, opts)

keymap("i", "<C-S-Right>", function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-\\><C-n>", true, false, true), "n", true)
  switch_window_and_set_half_height("right")
end, opts)

keymap("i", "<C-S-Up>", function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-\\><C-n>", true, false, true), "n", true)
  switch_window_and_set_half_height("up")
end, opts)

keymap("i", "<C-S-Down>", function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-\\><C-n>", true, false, true), "n", true)
  switch_window_and_set_half_height("down")
end, opts)

-- 可视模式（Visual Mode）
keymap("v", "<C-S-Left>", function()
  switch_window_and_set_half_height("left")
end, opts)

keymap("v", "<C-S-Right>", function()
  switch_window_and_set_half_height("right")
end, opts)

keymap("v", "<C-S-Up>", function()
  switch_window_and_set_half_height("up")
end, opts)

keymap("v", "<C-S-Down>", function()
  switch_window_and_set_half_height("down")
end, opts)

-- 终端模式（Terminal Mode）
keymap("t", "<C-S-Left>", function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-\\><C-n>", true, false, true), "n", true)
  switch_window_and_set_half_height("left")
end, opts)

keymap("t", "<C-S-Right>", function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-\\><C-n>", true, false, true), "n", true)
  switch_window_and_set_half_height("right")
end, opts)

keymap("t", "<C-S-Up>", function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-\\><C-n>", true, false, true), "n", true)
  switch_window_and_set_half_height("up")
end, opts)

keymap("t", "<C-S-Down>", function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-\\><C-n>", true, false, true), "n", true)
  switch_window_and_set_half_height("down")
end, opts)

return M
