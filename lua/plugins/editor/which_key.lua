return {
  "folke/which-key.nvim",
  opts = function(_, opts)
    require("config.platform.locale").setup_which_key(opts)
    local additions = {
    win = { wo = { winblend = 0 } },
    icons = { separator = "󰁔" },
    spec = {
      { "<leader>a", group = "Avante", mode = { "n", "x" } },
      { "<leader>r", group = "Renaming" },
      { "<leader>\\", desc = "Reveal Current File in NeoTree" },
      { "<leader>\\\\", desc = "Reveal Current File in NeoTree" },
      { "<leader>vs", desc = "Select Python Environment" },
      { "<leader>vc", desc = "Restore Cached Python Environment" },
      { "<leader>t", group = "telescope and toggles" },
      { "<leader>v", group = "python venv selector", icon = "" }, -- group-- group
      -- { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find File", mode = "n" },
      -- { "<leader>fb", function() print("hello") end, desc = "Foobar" },
      -- { "<leader>fn", desc = "New File" },
      -- { "<leader>f1", hidden = true }, -- hide this keymap
      -- { "<leader>w", proxy = "<c-w>", group = "windows" }, -- proxy to window mappings
      -- { "<leader>b", group = "buffers", expand = function()
      --     return require("which-key.extras").expand.buf()
      --   end
      -- },
      -- {
      --   -- Nested mappings are allowed and can be added in any order
      --   -- Most attributes can be inherited or overridden on any level
      --   -- There's no limit to the depth of nesting
      --   mode = { "n", "v" }, -- NORMAL and VISUAL mode
      --   { "<leader>q", "<cmd>q<cr>", desc = "Quit" }, -- no need to specify mode since it's inherited
      --   { "<leader>w", "<cmd>w<cr>", desc = "Write" },
      -- },
    },
    }
    opts.win = vim.tbl_deep_extend("force", opts.win or {}, additions.win)
    opts.icons = vim.tbl_deep_extend("force", opts.icons or {}, additions.icons)
    opts.spec = vim.list_extend(opts.spec or {}, additions.spec)
    return opts
  end,
}
