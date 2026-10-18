return {
  {
    "neovim/nvim-lspconfig",
    -- Let LazyVim configure diagnostics, capabilities, keymaps and each server once.
    opts = function(_, opts)
      -- Inset diagnostics within the existing two-column sign slot.
      local signs = opts.diagnostics and opts.diagnostics.signs
      if type(signs) == "table" and type(signs.text) == "table" then
        for severity, icon in pairs(signs.text) do
          local glyph = type(icon) == "string" and vim.trim(icon) or ""
          if vim.fn.strdisplaywidth(glyph) == 1 then
            signs.text[severity] = " " .. glyph
          end
        end
      end
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
