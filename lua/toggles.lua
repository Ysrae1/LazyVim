-- null-ls toggle

local null_ls = require("null-ls")
local mason_registry = require("mason-registry")
local formatting = null_ls.builtins.formatting
local diagnostics = null_ls.builtins.diagnostics
local code_actions = null_ls.builtins.code_actions

-- 存储当前null-ls源的状态
local null_ls_enabled = true

local function setup_sources()
  return {
    -- get from $PATH
    diagnostics.ruff,
    diagnostics.mypy,
    formatting.black,

    -- get from mason
    formatting.stylua.with({
      command = mason_registry.get_package("stylua").path,
      extra_args = { "--indent-type", "Spaces", "--indent-width", "2" },
    }),
    formatting.shfmt.with({
      command = mason_registry.get_package("shfmt").path,
    }),
    formatting.prettierd.with({
      command = mason_registry.get_package("prettierd").path,
    }),
    formatting.rustfmt.with({
      command = mason_registry.get_package("rustfmt").path,
    }),
    formatting.yamlfix.with({
      command = mason_registry.get_package("yamlfix").path, -- requires python
    }),

    diagnostics.yamllint.with({
      command = mason_registry.get_package("yamllint").path,
    }),

    code_actions.shellcheck.with({
      command = mason_registry.get_package("shellcheck").path,
    }),
  }
end

local function toggle_null_ls()
  if null_ls_enabled then
    -- 禁用所有null-ls源
    null_ls.disable(setup_sources())
    null_ls_enabled = false
    print("null-ls disabled")
  else
    -- 启用所有null-ls源
    null_ls.enable(setup_sources())
    null_ls_enabled = true
    print("null-ls enabled")
  end
end

-- vim.api.nvim_set_keymap(
--   "n",
--   "<leader>tn",
--   "<cmd>lua require('toggles').toggle_null_ls()<CR>",
--   { noremap = true, silent = true, desc = "Toggle null_ls" }
-- )

-- -- autoformatter toggle
--
-- local function toggle_format_options()
--   -- 获取当前的_global.formatoptions，返回一个键值对表
--   local current_fo = vim.opt_global.formatoptions:get()
--
--   -- 打印当前状态
--   print("Current global formatoptions: " .. vim.inspect(current_fo))
--
--   -- 检查是否包含 'r' 和 'o'
--   if current_fo["r"] and current_fo["o"] then
--     -- 移除所有选项，仅保留 'q'
--     vim.opt_global.formatoptions = { q = true }
--     print("Auto-comment and other options are disabled, only 'q' is retained")
--   else
--     -- 恢复 'r', 'o' 以及其他通常使用的选项
--     vim.opt_global.formatoptions = {
--       j = true,
--       n = true,
--       c = true,
--       r = true,
--       o = true,
--       q = true,
--       l = true,
--     }
--     print("Auto-comment and other options are enabled")
--   end
--
--   -- 打印更新后的状态
--   local updated_fo = vim.opt_global.formatoptions:get()
--   print("Updated global wformatoptions: " .. vim.inspect(updated_fo))
-- end
--
-- vim.api.nvim_set_keymap(
--   "n",
--   "<leader>tf",
--   '<cmd>lua require("toggles").toggle_format_options()<CR>',
--   { noremap = true, silent = true, desc = "Toggle autoformatter" }
-- )
