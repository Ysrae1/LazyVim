return {
  {
    "telescope.nvim",
    dependencies = {
      "nvim-telescope/telescope-fzf-native.nvim",
      build = "make",
      config = function()
        require("telescope").setup({
          defaults = {
            path_display = nil,
            -- other default configurations
          },
          -- other configurations
        })
        require("telescope").load_extension("fzf")
      end,
    },
  },
}
