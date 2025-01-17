-- lua/configs/lsp/pyright.lua

local lspconfig = require("lspconfig")
local keymaps = require("config.keymaps")

lspconfig.pyright.setup({
  on_attach = keymaps.on_attach,
  capabilities = require("cmp_nvim_lsp").default_capabilities(),
  settings = {
    python = {
      analysis = {
        typeCheckingMode = "basic", -- 可改为 "strict"
      },
    },
  },
})