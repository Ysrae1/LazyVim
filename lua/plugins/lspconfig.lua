return {
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
      -- 如果要使用自动补全，还需 "hrsh7th/nvim-cmp" + "hrsh7th/cmp-nvim-lsp" 等
    },
    config = function()
      local lspconfig = require("lspconfig")
      local mason_lspconfig = require("mason-lspconfig")
      local keymaps = require("config.keymaps")

      local capabilities = vim.lsp.protocol.make_client_capabilities()
      local ok_cmp, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
      if ok_cmp then
        capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
      end

      -- 设置 LSP 服务器
      mason_lspconfig.setup_handlers({
        function(server_name)
          lspconfig[server_name].setup({
            on_attach = on_attach,
            capabilities = capabilities,
          })
        end,
        -- 为特定服务器设置独立的配置
        ["pyright"] = function()
          require("config.lsp.pyright")
        end,
        ["clangd"] = function()
          require("config.lsp.clangd")
        end,
        ["texlab"] = function()
          require("config.lsp.texlab")
        end,
        -- 其他 LSP 服务器的独立配置...
      })
    end,
  },
  {},
}
