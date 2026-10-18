return {
  "linux-cultist/venv-selector.nvim",
  branch = "main",
  version = false,
  dependencies = { "neovim/nvim-lspconfig", "nvim-telescope/telescope.nvim", "mfussenegger/nvim-dap-python" },
  opts = {
    options = {
      -- Restore/select environments explicitly; do not change all tool processes' PATH.
      cached_venv_automatic_activation = false,
      activate_venv_in_terminal = false,
    },
  },
  event = "VeryLazy", -- Optional: needed only if you want to type `:VenvSelect` without a keymapping
  keys = {
    -- Keymap to open VenvSelector to pick a venv.
    { "<leader>vs", "<cmd>VenvSelect<cr>" },
    -- Keymap to retrieve the venv from a cache (the one previously used for the same project directory).
    { "<leader>vc", "<cmd>VenvSelectCached<cr>" },
  },
}
