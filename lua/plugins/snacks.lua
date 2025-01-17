return {
  {
    "snacks.nvim",
    -- enabled = false,
    priority = 500,
    event = "VeryLazy",
    ---@type snacks.Config
    opts = {
      bigfile = { enabled = true },
      notifier = {
        timeout = 4000,
      },

      dashboard = {
        enabled = true,
        width = 80,
        row = nil,
        col = nil,
        pane_gap = 4,
        autokeys = "1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
        preset = {
          pick = nil,
          keys = {
            -- Snacks' default setting.

            -- { icon = " ", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
            -- { icon = " ", key = "n", desc = "New File", action = ":ene | startinsert" },
            -- { icon = " ", key = "g", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
            -- { icon = " ", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
            -- {
            --   icon = " ",
            --   key = "c",
            --   desc = "Config",
            --   action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})",
            -- },

            -- Using telescope.
            --
            --
            {
              icon = " ",
              key = "f",
              desc = "Find File",
              action = function()
                require("telescope.builtin").find_files({ hidden = true })
              end,
            },
            {
              icon = " ",
              key = "n",
              desc = "New File",
              action = function()
                vim.cmd("ene | startinsert")
              end,
            },
            {
              icon = " ",
              key = "g",
              desc = "Find Text",
              action = function()
                require("telescope.builtin").live_grep()
              end,
            },
            {
              icon = " ",
              key = "r",
              desc = "Recent Files",
              action = function()
                require("telescope.builtin").oldfiles()
              end,
            },
            -- { icon = " ", key = "f", desc = "Find File", action = ":Telescope find_files" },
            -- { icon = " ", key = "n", desc = "New File", action = ":ene | startinsert" },
            -- { icon = " ", key = "g", desc = "Find Text", action = ":Telescope live_grep" },
            -- { icon = " ", key = "r", desc = "Recent Files", action = ":Telescope oldfiles" },
            {
              icon = " ",
              key = "c",
              desc = "Config",
              action = ":lua require('telescope.builtin').find_files({ cwd = vim.fn.stdpath('config')})",
            },

            {
              icon = " ",
              key = "s",
              desc = "Restore Session",
              action = ":lua require('persistence').load({ last = true })",
            },
            { icon = "󰒲 ", key = "l", desc = "Lazy", action = ":Lazy", enabled = package.loaded.lazy ~= nil },
            { icon = "󰇥 ", key = "y", desc = "Yazi", action = ":Yazi" },
            { icon = " ", key = "q", desc = "Quit", action = ":qa" },
          },
          header = [[
███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗
████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║
██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║
██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║
██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║
╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝]],
        },
        formats = {
          icon = function(item)
            return { item.icon, width = 2, hl = "icon" }
          end,
          footer = { "%s", align = "center" },
          header = { "%s", align = "center" },
          file = function(item, ctx)
            local fname = vim.fn.fnamemodify(item.file, ":~")
            fname = ctx.width and #fname > ctx.width and vim.fn.pathshorten(fname) or fname
            if #fname > ctx.width then
              local dir = vim.fn.fnamemodify(fname, ":h")
              local file = vim.fn.fnamemodify(fname, ":t")
              if dir and file then
                file = file:sub(-(ctx.width - #dir - 2))
                fname = dir .. "/…" .. file
              end
            end
            local dir, file = fname:match("^(.*)/(.+)$")
            return dir and { { dir .. "/", hl = "dir" }, { file, hl = "file" } } or { { fname, hl = "file" } }
          end,
        },
        sections = {
          { section = "header", padding = 1, pane = 1 },

          {
            section = "terminal",
            -- cmd = "cmatrix -a -b -u 1",
            cmd = "cmatrix -a -b -u 5 -o",
            random = 10,
            pane = 1,
            height = 6,
            padding = 1,
          },

          { icon = " ", title = "Keymaps", section = "keys", indent = 2, padding = 1, pane = 1 },
          { icon = " ", title = "Recent Files", section = "recent_files", indent = 2, padding = 1, pane = 1 },
          { icon = " ", title = "Projects", section = "projects", indent = 2, padding = 1, pane = 1 },
          { section = "startup" },
        },
      },

      indent = { enabled = true },
      input = { enabled = true },
      quickfile = { enabled = true },
      scroll = { enabled = true },
      statuscolumn = { enabled = true },
      words = { enabled = true },
      styles = {
        notification = {
          wo = { wrap = true },
        },
      },
    },

    vim.api.nvim_create_user_command("Dashboard", function()
      require("dashboard"):instance()
    end, {}),

    init = function()
      vim.api.nvim_create_autocmd("User", {
        pattern = "VeryLazy",
        callback = function()
          -- Setup some globals for debugging (lazy-loaded)
          _G.dd = function(...)
            Snacks.debug.inspect(...)
          end
          _G.bt = function()
            Snacks.debug.backtrace()
          end
          vim.print = _G.dd -- Override print to use snacks for `:=` command

          -- Create some toggle mappings
          Snacks.toggle.option("spell", { name = "Spelling" }):map("<leader>us")
          Snacks.toggle.option("wrap", { name = "Wrap" }):map("<leader>uw")
          Snacks.toggle.option("relativenumber", { name = "Relative Number" }):map("<leader>uL")
          Snacks.toggle.diagnostics():map("<leader>ud")
          Snacks.toggle.line_number():map("<leader>ul")
          Snacks.toggle
            .option("conceallevel", { off = 0, on = vim.o.conceallevel > 0 and vim.o.conceallevel or 2 })
            :map("<leader>uc")
          Snacks.toggle.treesitter():map("<leader>uT")
          Snacks.toggle.option("background", { off = "light", on = "dark", name = "Dark Background" }):map("<leader>ub")
          Snacks.toggle.inlay_hints():map("<leader>uh")
          Snacks.toggle.indent():map("<leader>ug")
          Snacks.toggle.dim():map("<leader>uD")
        end,
      })
    end,
  },
  -- {
  --   "nvimdev/dashboard-nvim",
  --   lazy = Verylazy, -- As https://github.com/nvimdev/dashboard-nvim/pull/450, dashboard-nvim shouldn't be lazy-loaded to properly handle stdin.
  --   opts = function()
  --     local logo = [[
  --          ██╗      █████╗ ███████╗██╗   ██╗██╗   ██╗██╗███╗   ███╗          Z
  --          ██║     ██╔══██╗╚══███╔╝╚██╗ ██╔╝██║   ██║██║████╗ ████║      Z
  --          ██║     ███████║  ███╔╝  ╚████╔╝ ██║   ██║██║██╔████╔██║   z
  --          ██║     ██╔══██║ ███╔╝    ╚██╔╝  ╚██╗ ██╔╝██║██║╚██╔╝██║ z
  --          ███████╗██║  ██║███████╗   ██║    ╚████╔╝ ██║██║ ╚═╝ ██║
  --          ╚══════╝╚═╝  ╚═╝╚══════╝   ╚═╝     ╚═══╝  ╚═╝╚═╝     ╚═╝
  --     ]]

  --     logo = string.rep("\n", 8) .. logo .. "\n\n"

  --     local opts = {
  --       theme = "doom",
  --       hide = {
  --         -- this is taken care of by lualine
  --         -- enabling this messes up the actual laststatus setting after loading a file
  --         statusline = false,
  --       },
  --       config = {
  --         header = vim.split(logo, "\n"),
  --         -- stylua: ignore
  --         center = {
  --           { action = 'lua LazyVim.pick()()',                           desc = " Find File",       icon = " ", key = "f" },
  --           { action = "ene | startinsert",                              desc = " New File",        icon = " ", key = "n" },
  --           { action = 'lua LazyVim.pick("oldfiles")()',                 desc = " Recent Files",    icon = " ", key = "r" },
  --           { action = 'lua LazyVim.pick("live_grep")()',                desc = " Find Text",       icon = " ", key = "g" },
  --           { action = 'lua LazyVim.pick.config_files()()',              desc = " Config",          icon = " ", key = "c" },
  --           { action = 'lua require("persistence").load()',              desc = " Restore Session", icon = " ", key = "s" },
  --           { action = "LazyExtras",                                     desc = " Lazy Extras",     icon = " ", key = "x" },
  --           { action = "Lazy",                                           desc = " Lazy",            icon = "󰒲 ", key = "l" },
  --           { action = function() vim.api.nvim_input("<cmd>qa<cr>") end, desc = " Quit",            icon = " ", key = "q" },
  --         },
  --         footer = function()
  --           local stats = require("lazy").stats()
  --           local ms = (math.floor(stats.startuptime * 100 + 0.5) / 100)
  --           return { "⚡ Neovim loaded " .. stats.loaded .. "/" .. stats.count .. " plugins in " .. ms .. "ms" }
  --         end,
  --       },
  --     }

  --     for _, button in ipairs(opts.config.center) do
  --       button.desc = button.desc .. string.rep(" ", 43 - #button.desc)
  --       button.key_format = "  %s"
  --     end

  --     -- open dashboard after closing lazy
  --     if vim.o.filetype == "lazy" then
  --       vim.api.nvim_create_autocmd("WinClosed", {
  --         pattern = tostring(vim.api.nvim_get_current_win()),
  --         once = true,
  --         callback = function()
  --           vim.schedule(function()
  --             vim.api.nvim_exec_autocmds("UIEnter", { group = "dashboard" })
  --           end)
  --         end,
  --       })
  --     end

  --     return opts
  --   end,
  -- }
}
