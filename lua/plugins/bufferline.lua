return {
  "akinsho/bufferline.nvim",
  dependencies = {
    "nvim-tree/nvim-web-devicons",
    "moll/vim-bbye",
  },

  enabled = false,

  event = "VeryLazy",

  config = function()
    require("bufferline").setup({
      options = {
        close_command = function(n)
          Snacks.bufdelete(n)
        end,
        right_mouse_command = function(n)
          Snacks.bufdelete(n)
        end,
        mode = "buffers",
        themable = false,
        numbers = "both",
        indicator = {
          style = "underline",
        },
        buffer_close_icon = "󰅖",
        modified_icon = "● ",
        close_icon = " ",
        left_trunc_marker = " ",
        right_trunc_marker = " ",

        diagnostics = "nvim_lsp",
        diagnostics_update_on_event = true,
        diagnostics_indicator = function(_, _, diag)
          local icons = LazyVim.config.icons.diagnostics
          local ret = (diag.error and icons.Error .. diag.error .. " " or "")
            .. (diag.warning and icons.Warn .. diag.warning or "")
          return vim.trim(ret)
        end,

        offsets = {
          {
            filetype = "neo-tree",
            text = "Neo-tree Explorer",
            highlight = "Directory",
            text_align = "left",
            separator = false,
          },
        },
        color_icons = true,

        get_element_icon = function(opts)
          -- 使用 nvim-web-devicons 直接获取图标
          local icon, hl = require("nvim-web-devicons").get_icon(opts.name, opts.filetype, { default = true })
          return icon, hl
        end,
        -- get_element_icon = function(element)
        --   return LazyVim.config.icons.ft[element.filetype]
        -- end,
        show_buffer_icons = true,
        show_buffer_close_icons = true,
        show_close_icon = true,
        show_tab_indicators = true,
        show_duplicate_prefix = true,
        duplicates_across_groups = true,
        persist_buffer_sort = true,
        move_wraps_at_ends = false,

        separator_style = "thin",
        enforce_regular_tabs = false,
        always_show_bufferline = true,
        auto_toggle_bufferline = true,
        hover = {
          enabled = true,
          delay = 200,
          reveal = { "close" },
        },
      },
    })
  end,
}
