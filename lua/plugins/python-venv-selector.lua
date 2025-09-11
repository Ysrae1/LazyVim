return {
  "linux-cultist/venv-selector.nvim",
  branch = "main",
  version = false,
  dependencies = { "neovim/nvim-lspconfig", "nvim-telescope/telescope.nvim", "mfussenegger/nvim-dap-python" },
  init = function()
    local orig_notify = vim.notify
    vim.notify = function(msg, level, opts)
      if type(msg) == "string" and msg:match("VenvSelect is now using `main` as the updated branch again") then
        return
      end
      return orig_notify(msg, level, opts)
    end
  end,
  opts = {
    -- Your options go here
    -- name = "venv",
    -- auto_refresh = false
  },
  event = "VeryLazy", -- Optional: needed only if you want to type `:VenvSelect` without a keymapping
  keys = {
    -- Keymap to open VenvSelector to pick a venv.
    { "<leader>vs", "<cmd>VenvSelect<cr>" },
    -- Keymap to retrieve the venv from a cache (the one previously used for the same project directory).
    { "<leader>vc", "<cmd>VenvSelectCached<cr>" },
  },
}
