-- ~/.config/nvim/lua/plugins/null-ls.lua
return {
  {
    "nvimtools/none-ls.nvim",
    dependencies = { "williamboman/mason.nvim", "gbprod/none-ls-shellcheck.nvim" },
    event = { "BufReadPre", "BufNewFile" },
    opts = function()
      local mason_registry = require("mason-registry")
      local null_ls = require("null-ls")
      local formatting = null_ls.builtins.formatting
      local diagnostics = null_ls.builtins.diagnostics
      local code_actions = null_ls.builtins.code_actions

      return {
        debug = false,
        sources = {
          -- 诊断
          diagnostics.mypy,
          diagnostics.yamllint.with({
            command = mason_registry.get_package("yamllint").path,
          }),

          -- 格式化
          formatting.black,
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

          -- shellcheck via external source (diagnostics + code actions)
          require("none-ls-shellcheck.diagnostics"),
          require("none-ls-shellcheck.code_actions"),
        },
      }
    end,
  },
}