-- lua/configs/lsp/clangd.lua

local lspconfig = require("lspconfig")
local keymaps = require("config.keymaps")

lspconfig.clangd.setup({
  on_attach = keymaps.on_attach,
  capabilities = require("cmp_nvim_lsp").default_capabilities(),
  cmd = { "clangd", "--background-index", "--clang-tidy" },
})