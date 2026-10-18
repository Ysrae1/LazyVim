return {
  {
    "mason-org/mason-lspconfig.nvim",
    -- Installed Mason and its bridge are v1; this LazyVim requires the v2 bridge.
    -- Keep existing tools on Mason's PATH and let LazyVim use vim.lsp.config/enable.
    -- Re-enable this bridge only after upgrading mason.nvim and mason-lspconfig together.
    enabled = false,
  },
}
