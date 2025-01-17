-- lua/plugins/mason.lua

return {
  {
    "williamboman/mason.nvim",
    opts = {
      ui = {
        border = "rounded",
        icons = {
          package_installed = "✓",
          package_pending = "➜",
          package_uninstalled = "✗",
        },
      },
      -- ensure_installed = {
      --   "black",
      --   "mypy",
      --   "ruff",
      -- },
    },
    config = function(_, opts)
      require("mason").setup(opts)
    end,
  },
  {
    vim.api.nvim_create_user_command("MasonInstallAll", function()
      local mason_registry = require("mason-registry")

      local packages = {
        "debugpy",
        "black",
        "mypy",
        "ruff",
        "clang-format",
        "gofumpt",
        "goimports",
        "prettierd",
        "stylua",
        "jq",
        "shfmt",
        "isort",
        "luacheck",
        "hadolint",
      }

      for _, package in ipairs(packages) do
        local pkg = mason_registry.get_package(package)
        if not pkg:is_installed() then
          pkg:install()
        end
      end
    end, {}),
  },
}

