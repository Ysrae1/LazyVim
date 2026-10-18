return {
  {
    "nvimtools/none-ls.nvim",
    dependencies = { "mason.nvim", "gbprod/none-ls-shellcheck.nvim" },
    opts = function(_, opts)
      local null_ls = require("null-ls")
      local formatting = null_ls.builtins.formatting
      local diagnostics = null_ls.builtins.diagnostics

      local config_markers = {
        mypy = { "mypy.ini", ".mypy.ini", "pyproject.toml", "setup.cfg" },
        yamllint = { ".yamllint", ".yamllint.yaml", ".yamllint.yml" },
        black = { "pyproject.toml" },
        stylua = { "stylua.toml", ".stylua.toml" },
        shfmt = { ".editorconfig" },
        prettierd = { "package.json" },
        shellcheck = { ".shellcheckrc" },
      }

      -- Mason adds its bin directory to PATH. Package.path is not an executable.
      -- Missing optional tools should not cause an error when a file is opened.
      local function available(source, command, source_opts)
        source_opts = source_opts or {}
        local source_cwd = source_opts.cwd or (source._opts or {}).cwd
        local markers = vim.list_extend(vim.deepcopy(config_markers[command] or {}), {
          ".null-ls-root", ".neoconf.json", "Makefile", ".git",
        })
        -- none-ls shares one client across projects; never inherit its first root.
        -- Keep each builtin's own config discovery, then fall back per file.
        source_opts.cwd = function(params)
          return (source_cwd and source_cwd(params))
            or vim.fs.root(params.bufname, markers)
            or vim.fs.dirname(params.bufname)
        end
        source_opts.command = command
        source_opts.condition = function()
          return vim.fn.executable(command) == 1
        end
        return source.with(source_opts)
      end

      opts.debug = false
      opts.sources = {
        available(diagnostics.mypy, "mypy"),
        available(diagnostics.yamllint, "yamllint"),
        available(formatting.black, "black"),
        available(formatting.stylua, "stylua", {
          extra_args = { "--indent-type", "Spaces", "--indent-width", "2" },
        }),
        available(formatting.shfmt, "shfmt"),
        available(formatting.prettierd, "prettierd"),
        available(require("none-ls-shellcheck.diagnostics"), "shellcheck"),
        available(require("none-ls-shellcheck.code_actions"), "shellcheck"),
      }
      return opts
    end,
  },
}
