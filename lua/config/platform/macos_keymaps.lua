local o = vim.o
local env = vim.env

local M = {}

-- local lang_file = vim.fn.stdpath("config") .. "/lang_setting.txt"
--
-- function M.toggle_lang()
--   if vim.env.LANG == "en_US.UTF-8" then
--     vim.env.LANG = "zh_CN.UTF-8"
--     vim.env.LC_ALL = "zh_CN.UTF-8"
--     print("语言已切换至中文，重启以应用。")
--   else
--     vim.env.LANG = "en_US.UTF-8"
--     vim.env.LC_ALL = "en_US.UTF-8"
--     print("Switched language to English, relaunch to apply changes.")
--   end
--   M.save_language_settings()
-- end
--
-- -- 保存语言设置到文件
-- function M.save_language_settings()
--   vim.fn.writefile({ vim.env.LANG }, lang_file)
-- end
--
-- -- 从文件加载语言设置
-- function M.load_language_settings()
--   if vim.fn.filereadable(lang_file) == 1 then
--     local lang = vim.fn.readfile(lang_file)[1]
--     vim.env.LANG = lang
--     vim.env.LC_ALL = lang
--   end
-- end
--
vim.opt.clipboard = "unnamed"

-- 设置快捷键绑定

-- vim.keymap.set("n", "<leader><C-l>", M.toggle_lang, { noremap = true, silent = true, desc = "Toggle Language" })

-- 保存快捷键
vim.keymap.set("n", "<D-s>", ":w<CR>", { noremap = true, silent = true })
vim.keymap.set("i", "<D-s>", "<Esc>:w<CR>a", { noremap = true, silent = true })

-- 复制快捷键
vim.keymap.set("v", "<D-c>", '"+y', { noremap = true, silent = true })

-- 定义无事件粘贴函数
local function paste_no_autocmd_normal()
  vim.cmd('noautocmd normal! "+P')
end

local function paste_no_autocmd_visual()
  vim.cmd('noautocmd normal! "+P')
end

local function paste_no_autocmd_terminal()
  -- 构造一次性按键序列：退出终端模式 + 粘贴 + 回到插入模式
  -- 注：一定要把特殊按键转换成终端转义序列
  local keys = '<C-\\><C-n>"+Pi'
  keys = vim.api.nvim_replace_termcodes(keys, true, false, true)

  -- 'n' 表示不 remap，false 表示不将 <ESC> 等再做 CSI 处理
  vim.api.nvim_feedkeys(keys, "n", false)
end

-- 设置粘贴快捷键
vim.keymap.set("n", "<D-v>", paste_no_autocmd_normal, { noremap = true, silent = true })
vim.keymap.set("v", "<D-v>", paste_no_autocmd_visual, { noremap = true, silent = true })

vim.keymap.set("i", "<D-v>", function()
  -- 1. 保存并清空 formatoptions
  local saved_fo = vim.bo.formatoptions
  -- print("[DEBUG] <D-v> triggered!")
  -- print("[DEBUG] saved_formatoptions =", saved_fo)

  vim.bo.formatoptions = ""
  -- print("[DEBUG] after clearing, formatoptions =", vim.bo.formatoptions)

  -- 2. 从剪贴板 + 寄存器获取文本（可多行）
  local data = vim.fn.getreg("+")

  -- 3. 调用 nvim_paste 完成插入模式下粘贴
  --    参数: (text, crlf, phase)
  --    phase=1 表示“粘贴开始或继续”，多次调用可以分段粘贴
  --    phase=3 通常可直接表示“粘贴结束”（单次粘贴）
  local ret = vim.api.nvim_paste(data, false, -1)
  -- print("[DEBUG] nvim_paste return code =", ret)
  -- print("[DEBUG] after nvim_paste, formatoptions =", vim.bo.formatoptions)

  -- 4. 恢复原先的 formatoptions
  vim.bo.formatoptions = saved_fo
  -- print("[DEBUG] after restoring, formatoptions =", vim.bo.formatoptions)
end, { noremap = true, silent = true })

vim.keymap.set("c", "<D-v>", function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-R>+", true, true, true), "n", true)
end, { noremap = true, silent = true })

vim.keymap.set("t", "<D-v>", paste_no_autocmd_terminal, { noremap = true, silent = true })

-- 定义一个辅助函数来简化键位映射
local function map_comment(mode, key, action)
  vim.keymap.set(mode, key, action, { noremap = true, silent = true })
end

-- 普通模式
map_comment("n", "<D-/>", '<cmd>lua require("Comment.api").toggle.linewise.current()<CR>')

-- 视觉模式
map_comment("x", "<D-/>", "<Esc><cmd>lua require('Comment.api').toggle.linewise(vim.fn.visualmode())<CR>")

-- 插入模式
map_comment("i", "<D-/>", '<Esc><cmd>lua require("Comment.api").toggle.linewise.current()<CR>a')

-- 命令模式
map_comment("c", "<D-/>", "<C-R>=luaeval('require(\"Comment.api\").toggle.linewise.current()')<CR>")

-- 终端模式
map_comment("t", "<D-/>", '<C-\\><C-n><cmd>lua require("Comment.api").toggle.linewise.current()<CR>a')

local undo_mappings = {
  { mode = "n", key = "<D-z>", cmd = "u" },
  { mode = "i", key = "<D-z>", cmd = "<C-o>u" },
  { mode = "v", key = "<D-z>", cmd = "u`[" },
  {
    mode = "c",
    key = "<D-z>",
    cmd = function()
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-u>", true, true, true), "n", true)
    end,
  },
  { mode = "t", key = "<D-z>", cmd = "<C-\\><C-n>u<C-w>w" },
}

-- 遍历并设置撤销映射
for _, map in ipairs(undo_mappings) do
  vim.keymap.set(map.mode, map.key, map.cmd, { noremap = true, silent = true })
end

-- 定义重做映射
local redo_mappings = {
  { mode = "n", key = "<D-S-z>", cmd = "<C-r>" },
  { mode = "i", key = "<D-S-z>", cmd = "<C-o><C-r>" },
  { mode = "v", key = "<D-S-z>", cmd = "<C-r>" },
  {
    mode = "c",
    key = "<D-S-z>",
    cmd = function()
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-r>", true, true, true), "n", true)
    end,
  },
  { mode = "t", key = "<D-S-z>", cmd = "<C-\\><C-n><C-r><C-w>w" },
}

-- 遍历并设置重做映射
for _, map in ipairs(redo_mappings) do
  vim.keymap.set(map.mode, map.key, map.cmd, { noremap = true, silent = true })
end

-- 普通模式下全选
vim.keymap.set("n", "<D-a>", function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("gg0VG$", true, false, true), "n", false)
end, { noremap = true, silent = true })

-- 插入模式下全选

vim.keymap.set("i", "<D-a>", function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>gg0VG$", true, false, true), "n", false)
end, { noremap = true, silent = true })

-- 可视和可视块模式下全选
vim.keymap.set("x", "<D-a>", function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>gg0VG$", true, false, true), "x", false)
end, { noremap = true, silent = true })

vim.keymap.set("v", "<D-a>", function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>gg0VG$", true, false, true), "v", false)
end, { noremap = true, silent = true })

-- <Backspace>

vim.keymap.set("v", "<D-BS>", function()
  vim.cmd('normal! "_d')
end, { noremap = true, silent = true })

vim.keymap.set("n", "<BS>", function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("a<BS><Esc>", true, false, true), "n", false)
end, { noremap = true, silent = true })

-- 普通模式下，删除前一个单词
vim.keymap.set("n", "<A-BS>", "db", { noremap = true, silent = true })

-- 插入模式下，先返回普通模式删除单词，再回到插入模式
vim.keymap.set("i", "<A-BS>", "<C-o>db", { noremap = true, silent = true })

-- 普通模式下，删除前一个单词
vim.keymap.set("n", "<A-S-BS>", "de", { noremap = true, silent = true })

-- 插入模式下，先返回普通模式删除单词，再回到插入模式
vim.keymap.set("i", "<A-S-BS>", "<C-o>de", { noremap = true, silent = true })

-- <Enter>

vim.keymap.set("n", "<CR>", function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("o<Esc>", true, false, true), "n", false)
end, { noremap = true, silent = true })

-- <Quick Move>

vim.keymap.set("n", "<D-Right>", function()
  local keys = vim.api.nvim_replace_termcodes("$", true, false, true)
  vim.api.nvim_feedkeys(keys, "n", false)
end, { noremap = true, silent = true })

vim.keymap.set("v", "<D-Right>", function()
  local keys = vim.api.nvim_replace_termcodes("$", true, false, true)
  vim.api.nvim_feedkeys(keys, "n", false)
end, { noremap = true, silent = true })

vim.keymap.set("i", "<D-Right>", function()
  local keys = vim.api.nvim_replace_termcodes("<Esc>A", true, false, true)
  vim.api.nvim_feedkeys(keys, "n", false)
end, { noremap = true, silent = true })

-- vim.keymap.set("n", "<D-S-Right>", function()
--   local keys = vim.api.nvim_replace_termcodes("V$", true, false, true)
--   vim.api.nvim_feedkeys(keys, "n", false)
-- end, { noremap = true, silent = true })
--
-- vim.keymap.set("i", "<D-S-Right>", function()
--   local keys = vim.api.nvim_replace_termcodes("<Esc>V$", true, false, true)
--   vim.api.nvim_feedkeys(keys, "n", false)
-- end, { noremap = true, silent = true })

vim.keymap.set("n", "<D-Left>", function()
  local keys = vim.api.nvim_replace_termcodes("0", true, false, true)
  vim.api.nvim_feedkeys(keys, "n", false)
end, { noremap = true, silent = true })

vim.keymap.set("v", "<D-Left>", function()
  local keys = vim.api.nvim_replace_termcodes("0", true, false, true)
  vim.api.nvim_feedkeys(keys, "n", false)
end, { noremap = true, silent = true })

vim.keymap.set("i", "<D-Left>", function()
  local keys = vim.api.nvim_replace_termcodes("<Esc>0i", true, false, true)
  vim.api.nvim_feedkeys(keys, "n", false)
end, { noremap = true, silent = true })

-- vim.keymap.set("n", "<D-S-Left>", function()
--   local keys = vim.api.nvim_replace_termcodes("V0", true, false, true)
--   vim.api.nvim_feedkeys(keys, "n", false)
-- end, { noremap = true, silent = true })
--
-- vim.keymap.set("i", "<D-S-Left>", function()
--   local keys = vim.api.nvim_replace_termcodes("<Esc>V0", true, false, true)
--   vim.api.nvim_feedkeys(keys, "n", false)
-- end, { noremap = true, silent = true })

-- <Wordwise>

vim.keymap.set("n", "<A-Right>", function()
  local keys = vim.api.nvim_replace_termcodes("e", true, false, true)
  vim.api.nvim_feedkeys(keys, "n", false)
end, { noremap = true, silent = true })

vim.keymap.set("i", "<A-Right>", function()
  local keys = vim.api.nvim_replace_termcodes("<Esc>ea", true, false, true)
  vim.api.nvim_feedkeys(keys, "n", false)
end, { noremap = true, silent = true })

vim.keymap.set("v", "<A-Right>", function()
  local keys = vim.api.nvim_replace_termcodes("e", true, false, true)
  vim.api.nvim_feedkeys(keys, "n", false)
end, { noremap = true, silent = true })

vim.keymap.set("n", "<A-S-Right>", function()
  local keys = vim.api.nvim_replace_termcodes("ve", true, false, true)
  vim.api.nvim_feedkeys(keys, "n", false)
end, { noremap = true, silent = true })

vim.keymap.set("i", "<A-S-Right>", function()
  local keys = vim.api.nvim_replace_termcodes("<Esc>Ve", true, false, true)
  vim.api.nvim_feedkeys(keys, "n", false)
end, { noremap = true, silent = true })

vim.keymap.set("v", "<A-S-Right>", function()
  local keys = vim.api.nvim_replace_termcodes("ve", true, false, true)
  vim.api.nvim_feedkeys(keys, "n", false)
end, { noremap = true, silent = true })

vim.keymap.set("n", "<A-Left>", function()
  local keys = vim.api.nvim_replace_termcodes("b", true, false, true)
  vim.api.nvim_feedkeys(keys, "n", false)
end, { noremap = true, silent = true })

vim.keymap.set("i", "<A-Left>", function()
  local keys = vim.api.nvim_replace_termcodes("<Esc>bi", true, false, true)
  vim.api.nvim_feedkeys(keys, "n", false)
end, { noremap = true, silent = true })

vim.keymap.set("v", "<A-Left>", function()
  local keys = vim.api.nvim_replace_termcodes("b", true, false, true)
  vim.api.nvim_feedkeys(keys, "n", false)
end, { noremap = true, silent = true })

vim.keymap.set("n", "<A-S-Left>", function()
  local keys = vim.api.nvim_replace_termcodes("Vb", true, false, true)
  vim.api.nvim_feedkeys(keys, "n", false)
end, { noremap = true, silent = true })

vim.keymap.set("i", "<A-S-Left>", function()
  local keys = vim.api.nvim_replace_termcodes("<Esc>Vb", true, false, true)
  vim.api.nvim_feedkeys(keys, "n", false)
end, { noremap = true, silent = true })

vim.keymap.set("v", "<A-S-Left>", function()
  local keys = vim.api.nvim_replace_termcodes("Vb", true, false, true)
  vim.api.nvim_feedkeys(keys, "n", false)
end, { noremap = true, silent = true })

-- indent

-- Normal 模式：单行缩进
vim.keymap.set("n", "<Tab>", ">>", { noremap = true, silent = true })
vim.keymap.set("n", "<S-Tab>", "<<", { noremap = true, silent = true })

vim.keymap.set("x", "<Tab>", ">gv", { noremap = true, silent = true })
vim.keymap.set("x", "<S-Tab>", "<gv", { noremap = true, silent = true })

-- buffers
vim.keymap.set("n", "<S-h>", function()
  require("nvchad.tabufline").prev()
end, { desc = "Prev Buffer" })
vim.keymap.set("n", "<S-l>", function()
  require("nvchad.tabufline").next()
end, { desc = "Next Buffer" })

vim.keymap.set("n", "<leader>bb", "<cmd>e #<cr>", { desc = "Switch to Other Buffer" })
vim.keymap.set("n", "<leader>`", "<cmd>e #<cr>", { desc = "Switch to Other Buffer" })

vim.keymap.set("n", "<leader>bd", function()
  require("nvchad.tabufline").close_buffer()
end, { desc = "Delete Buffer" })
vim.keymap.set("n", "<leader>bo", function()
  require("nvchad.tabufline").closeAllBufs(false)
end, { desc = "Delete Other Buffers" })
vim.keymap.set("n", "<leader>bD", "<md>:bd<cr>", { desc = "Delete Buffer and Window" })

-- -- 加载语言设置并设置快键
-- M.load_language_settings()

return M
