return {
  -- LazyVim now supplies LSP, path, buffer and Lua completion through blink.
  -- Keep LuaSnip snippets without starting a second completion engine.
  {
    "L3MON4D3/LuaSnip",
    lazy = true,
    dependencies = { "rafamadriz/friendly-snippets" },
    opts = { history = true, delete_check_events = "TextChanged" },
    config = function(_, opts)
      require("luasnip").setup(opts)
      local loader = require("luasnip.loaders.from_vscode")
      -- Load the actual snippet collection instead of scanning every plugin's
      -- package.json (Yazi's package metadata is not a snippet manifest).
      local friendly = require("lazy.core.config").plugins["friendly-snippets"]
      if friendly then
        loader.lazy_load({ paths = { friendly.dir } })
      end
      local custom = vim.fn.stdpath("config") .. "/snippets"
      if vim.fn.filereadable(custom .. "/package.json") == 1
        or vim.fn.filereadable(custom .. "/package.jsonc") == 1
      then
        loader.lazy_load({ paths = { custom } })
      end
    end,
  },
  { "hrsh7th/nvim-cmp", enabled = false },
  {
    "saghen/blink.cmp",
    dependencies = { "L3MON4D3/LuaSnip" },
    opts = {
      -- Use the bundled matcher across CPU architectures; no native download on startup.
      fuzzy = { implementation = "lua" },
      snippets = { preset = "luasnip" },
      keymap = {
        ["<Tab>"] = { "snippet_forward", "fallback" },
        ["<S-Tab>"] = { "snippet_backward", "fallback" },
      },
    },
  },
}
