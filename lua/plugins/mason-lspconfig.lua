-- lua/plugins/mason-lspconfig.lua

return {
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "williamboman/mason.nvim", "neovim/nvim-lspconfig" },
    opts = {
      ensure_installed = {
        "pyright",
        "clangd",
        "texlab",
        "ltex",
        -- 其他你需要的 LSP 服务器
      },
    },
    config = function(_, opts)
      require("mason-lspconfig").setup(opts)
    end,
  },
}

