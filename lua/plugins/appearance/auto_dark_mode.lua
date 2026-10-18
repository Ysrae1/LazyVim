return {
  {
    "f-person/auto-dark-mode.nvim",
    lazy = false,
    config = function()
      require("auto-dark-mode").setup({
        update_interval = 1000,
        set_dark_mode = function()
          -- 调色/主题重载会替换 nvconfig；每次取当前表，避免继续修改旧配置。
          local config = require("nvconfig")
          local dark_theme = config.base46.theme_toggle[1]
          if config.base46.theme ~= dark_theme then
            config.base46.theme = dark_theme
            require("base46").load_all_highlights()
          end
        end,
        set_light_mode = function()
          local config = require("nvconfig")
          local light_theme = config.base46.theme_toggle[2]
          if config.base46.theme ~= light_theme then
            config.base46.theme = light_theme
            require("base46").load_all_highlights()
          end
        end,
      })
      require("auto-dark-mode").init()
    end,
  },
}
