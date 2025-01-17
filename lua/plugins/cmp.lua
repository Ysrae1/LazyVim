return {
  -- Autocompletion
  {
    "L3MON4D3/LuaSnip",
    event = "VeryLazy",
  },
  {
    "hrsh7th/cmp-buffer",
    event = "VeryLazy",
  },
  {
    "saadparwaiz1/cmp_luasnip",
    event = "VeryLazy",
  },
  {
    "hrsh7th/nvim-cmp",
    event = "VeryLazy",
    priority = 2000,
    enabled = true,
    dependencies = {
      { "L3MON4D3/LuaSnip" },
      { "hrsh7th/cmp-buffer" },
      { "hrsh7th/cmp-nvim-lsp" },
      { "saadparwaiz1/cmp_luasnip" },
    },
  },
  require("cmp").setup({
    sources = {
      { name = "nvim_lua" },
      { name = "path" },
    },
  }),
}
