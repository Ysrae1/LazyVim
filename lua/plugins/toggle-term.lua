return {

  {
    "akinsho/toggleterm.nvim",
    event = "VeryLazy",
    version = "*",
    config = function()
      require("toggleterm").setup({
        -- 在这里配置 toggleterm 的选项
        size = 20,
        open_mapping = [[<c-t>]],
        on_open = function(term)
          -- 当终端打开时运行，设置终端的工作目录
          local current_dir = vim.fn.expand("%:p:h")
          if vim.fn.isdirectory(current_dir) == 1 then
            vim.cmd("tcd " .. vim.fn.fnameescape(current_dir))
          end
          print("Terminal " .. term.id .. " opened in " .. current_dir)
        end,
        hide_numbers = true,
        shade_filetypes = {},
        shade_terminals = true,
        shading_factor = 2,
        start_in_insert = true,
        insert_mappings = true,
        persist_size = true,
        direction = "float", -- 或 'horizontal' | 'vertical' | 'tab'
        close_on_exit = true,
        shell = vim.o.shell, -- 使用 Vim 的默认 shell
        autochdir = true,
        float_opts = {
          -- The border key is *almost* the same as 'nvim_open_win'
          -- see :h nvim_open_win for details on borders however
          -- the 'curved' border is a custom border type
          -- not natively supported but implemented in this plugin.
          border = "curved", -- like `size`, width, height, row, and col can be a number or function which is passed the current terminal
          -- width = <value>,
          -- height = <value>,
          -- row = <value>,
          -- col = <value>,
          -- winblend = 3,
          -- zindex = <value>,
          title_pos = "center",
        },
      })
    end,
  },
}
