-- lua/configs/lsp/texlab.lua

local lspconfig = require("lspconfig")
local keymaps = require("config.keymaps")

lspconfig.texlab.setup({
  on_attach = keymaps.on_attach,
  capabilities = require("cmp_nvim_lsp").default_capabilities(),
  settings = {
    texlab = {
      build = {
        executable = "latexmk",
        args = {
          "-xelatex",
          "-file-line-error",
          "-interaction=nonstopmode",
          "-synctex=1",
          "%f",
        },
        forwardSearchAfter = false,
        onSave = true,
      },
      forwardSearch = {
        executable = "/Applications/Skim.app/Contents/SharedSupport/displayline",
        args = { "%l", "%p", "%f" },
      },
      chktex = {
        onEdit = true,
        onOpenAndSave = true,
      },
      bibtexFormatter = "texlab", -- 选择 bibtex 格式化工具
    },
  },
})
