return {
  "anuvyklack/help-vsplit.nvim",
  config = function()
    require("help-vsplit").setup({
      always = false, -- Always open help in a vertical split.
      side = "right", -- 'left' or 'right'
      buftype = { "help" },
      filetype = { "man" },
    })
  end,
}
