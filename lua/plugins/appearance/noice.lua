return {
  {
    "folke/noice.nvim",
    -- enabled = false,
    event = "VeryLazy",
    opts = {
      views = { mini = { win_options = { winblend = 0 } } },
      lsp = {
        override = {
          -- ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
          -- ["vim.lsp.util.stylize_markdown"] = true,
          -- ["cmp.entry.get_documentation"] = true,
          ["cmp.entry.get_documentation"] = false,
          ["vim.lsp.util.stylize_markdown"] = false,
          ["vim.lsp.util.convert_input_to_markdown_lines"] = false,
        },
        signature = {
          enabled = false,
        },

        hover = {
          enabled = false,
        },
      },
      notify = {
        enabled = false,
      },
      routes = {
        {
          filter = {
            event = "msg_show",
            any = {
              { find = "%d+L, %d+B" },
              { find = "; after #%d+" },
              { find = "; before #%d+" },
            },
          },
          view = "mini",
        },
      },
      presets = {
        bottom_search = true,
        command_palette = true,
        long_message_to_split = true,
      },
    },
  -- stylua: ignore
  keys = {
    { "<leader>sn", "", desc = "+noice"},
    { "<S-Enter>", function() require("noice").redirect(vim.fn.getcmdline()) end, mode = "c", desc = "Redirect Cmdline" },
    { "<leader>snl", function() require("noice").cmd("last") end, desc = "Noice Last Message" },
    { "<leader>snh", function() require("noice").cmd("history") end, desc = "Noice History" },
    { "<leader>sna", function() require("noice").cmd("all") end, desc = "Noice All" },
    { "<leader>snd", function() require("noice").cmd("dismiss") end, desc = "Dismiss All" },
    { "<leader>snt", function() require("noice").cmd("pick") end, desc = "Noice Picker (Telescope/FzfLua)" },
    { "<c-f>", function() if not require("noice.lsp").scroll(4) then return "<c-f>" end end, silent = true, expr = true, desc = "Scroll Forward", mode = {"i", "n", "s"} },
    { "<c-b>", function() if not require("noice.lsp").scroll(-4) then return "<c-b>" end end, silent = true, expr = true, desc = "Scroll Backward", mode = {"i", "n", "s"}},
  },

    config = function(_, opts)
      -- HACK: noice shows messages from before it was enabled,
      -- but this is not ideal when Lazy is installing plugins,
      -- so clear the messages in this case.
      if vim.o.filetype == "lazy" then
        vim.cmd([[messages clear]])
      end
      -- Neovide 0.16 temporarily owns ext_cmdline while capturing startup errors.
      -- Wait without blocking its first redraw, then let Noice attach normally.
      local attempts = 0
      local function setup_when_ready()
        local external_cmdline = false
        for _, ui in ipairs(vim.api.nvim_list_uis()) do
          external_cmdline = external_cmdline or ui.ext_cmdline == true
        end
        if vim.g.neovide and external_cmdline then
          attempts = attempts + 1
          if attempts < 200 then
            vim.defer_fn(setup_when_ready, 50)
          else
            vim.notify("Neovide has not released its startup command line; Noice could not start.", vim.log.levels.WARN)
          end
          return
        end
        require("noice").setup(opts)
      end
      setup_when_ready()
    end,
  },
}
