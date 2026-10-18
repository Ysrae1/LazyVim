return {
  {
    "lukas-reineke/indent-blankline.nvim",
    event = "LazyFile",
    init = function()
      vim.api.nvim_create_autocmd("User", {
        pattern = "VeryLazy",
        once = true,
        callback = function()
          require("snacks")
            .toggle({
              name = "Indention Guides",
              get = function()
                return require("ibl.config").get_config(0).enabled
              end,
              set = function(state)
                require("ibl").setup_buffer(0, { enabled = state })
              end,
            })
            :map("<leader>ug")
        end,
      })
    end,
    opts = function()
      return {
        indent = {
          char = ".",
          tab_char = "│",
        },
        scope = { show_start = false, show_end = false },
        exclude = {
          filetypes = {
            "Trouble",
            "alpha",
            "dashboard",
            "help",
            "lazy",
            "mason",
            "neo-tree",
            "notify",
            "snacks_dashboard",
            "snacks_notif",
            "snacks_terminal",
            "snacks_win",
            "toggleterm",
            "trouble",
          },
        },
      }
    end,
    main = "ibl",
  },
}
