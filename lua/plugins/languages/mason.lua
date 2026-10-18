local packages = {
  "pyright",
  "gopls",
  "neocmakelsp",
  "lua-language-server",
  "json-lsp",
  "marksman",
  "clangd",
  "texlab",
  "ltex-ls",
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

local versions = { pyright = "1.1.414", gopls = "v0.22.0", neocmakelsp = "v0.10.2" }

return {
  {
    "mason-org/mason.nvim",
    opts = {
      ui = {
        border = "rounded",
        icons = {
          package_installed = "󰄬",
          package_pending = "󰁔",
          package_uninstalled = "󰅖",
        },
      },
    },
    init = function()
      vim.api.nvim_create_user_command("MasonInstallAll", function()
        require("lazy").load({ plugins = { "mason.nvim" } })
        local registry = require("mason-registry")
        registry.refresh(function()
          for _, name in ipairs(packages) do
            local ok, package = pcall(registry.get_package, name)
            if not ok then
              vim.notify("Mason package unavailable: " .. name, vim.log.levels.WARN)
            elseif not package:is_installed() then
              package:install({ version = versions[name] })
            end
          end
        end)
      end, { desc = "Install configured language servers and tools" })
    end,
    config = function(_, opts)
      -- Preserve installed tools; installation is an explicit Mason command.
      require("mason").setup(opts)
    end,
  },
}
