local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json"
  local lock = vim.json.decode(table.concat(vim.fn.readfile(lockfile), "\n"))
  local commit = lock["lazy.nvim"] and lock["lazy.nvim"].commit
  if type(commit) ~= "string" or not commit:match("^%x+$") then
    error("Cannot bootstrap lazy.nvim without its frozen commit in " .. lockfile)
  end
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--no-checkout", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
  local checkout = vim.fn.system({ "git", "-C", lazypath, "checkout", "--detach", commit })
  if vim.v.shell_error ~= 0 then
    error("Failed to check out frozen lazy.nvim commit " .. commit .. ":\n" .. checkout)
  end
end

---@diagnostic disable-next-line: undefined-field
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({

  spec = {

    -- add LazyVim and import its plugins
    {

      "LazyVim/LazyVim",

      opts = {
        colorscheme = function()
          require("config.appearance.base46").setup()
          require("base46").load_all_highlights()
          vim.cmd.colorscheme("nvchad")
        end,
      },
      import = "lazyvim.plugins",
    },

    -- import/override with your plugins
    { import = "lazyvim.plugins.extras.lsp.none-ls" },
    { import = "plugins" },
    { import = "config.stable_plugins" },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
    version = false, -- Version selection is fixed by config.stable_plugins in normal use.
    -- version = "*", -- try installing the latest stable version for plugins that support semver
  },

  ui = {
    icons = {
      ft = "",
      lazy = "󰂠 ",
      loaded = "",
      not_loaded = "",
    },
  },

  install = {
    missing = false, -- Restore missing dependencies explicitly; never install on startup.
  },
  checker = {
    enabled = false, -- Update deliberately after checking the lockfile.
  },
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        "tokyonight",
        -- "matchparen",
        -- "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
