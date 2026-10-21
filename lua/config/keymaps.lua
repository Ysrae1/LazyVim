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
  local enabled = not vim.diagnostic.is_enabled()
  vim.diagnostic.enable(enabled)
  vim.g.diagnostics_active = enabled
end

local map = vim.keymap.set

local del = vim.keymap.del

map(
  "n",
  "<leader>tn",
  "<cmd>lua require('config.editor.toggles').toggle_null_ls()<CR>",
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
  require("fff").find_files({ cwd = vim.fn.getcwd() })
end, { desc = "FFF find files" })
map("n", "<leader>ta", function()
  builtin.find_files({ follow = true, no_ignore = true, hidden = true })
end, { desc = "telescope find all files" })

-- Layout operations exclude the file tree, AI panes and other auxiliary windows.
require("config.navigation.editor_window_keymaps").setup()
require("config.platform.windows_edit_keymaps").setup()
require("config.navigation.reindent_keymaps").setup()

return M
