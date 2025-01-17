return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
      local configs = require("nvim-treesitter.configs")

      configs.setup({
        ensure_installed = {
          "c",
          "go",
          "lua",
          "vim",
          "vimdoc",
          "bash",
          "cmake",
          "cpp",
          "comment",
          "css",
          "diff",
          "dockerfile",
          "git_config",
          "git_rebase",
          "gitattributes",
          "gitcommit",
          "gitignore",
          "gomod",
          "gosum",
          "gowork",
          "hjson",
          "html",
          "ini",
          "javascript",
          "json",
          "json5",
          "jsdoc",
          "jsonc",
          "luadoc",
          "luap",
          "make",
          "markdown",
          "meson",
          "ninja",
          "nix",
          "python",
          "pug",
          "rust",
          "scss",
          "sql",
          "svelte",
          "toml",
          "tsx",
          "typescript",
          "vue",
          "yaml",
        },
        sync_install = false,
        highlight = { enable = true, disable = { "neo-tree" } },
        indent = { enable = true },
        fold = {
          enable = true, -- 启用基于 treesitter 的折叠
        },
        vim.api.nvim_create_autocmd("FileType", {
          pattern = "*",
          callback = function()
            vim.wo.foldmethod = "expr"
            vim.wo.foldexpr = "nvim_treesitter#foldexpr()"
            vim.wo.foldenable = true -- 可选，启用折叠
          end,
        }),
      })
    end,
  },
}

