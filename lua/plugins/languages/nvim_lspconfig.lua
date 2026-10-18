return {
  {
    "neovim/nvim-lspconfig",
    -- Let LazyVim configure diagnostics, capabilities, keymaps and each server once.
    opts = function(_, opts)
      opts.servers = opts.servers or {}
      for _, server in ipairs({ "pyright", "clangd", "texlab" }) do
        opts.servers[server] = vim.tbl_deep_extend(
          "force",
          opts.servers[server] or {},
          require("config.lsp." .. server)
        )
      end
      opts.servers.ltex = opts.servers.ltex or {}
      opts.servers["*"] = opts.servers["*"] or {}
      opts.servers["*"].keys = opts.servers["*"].keys or {}
      table.insert(opts.servers["*"].keys, { "<leader>rn", vim.lsp.buf.rename, desc = "Rename" })
    end,
  },
}
