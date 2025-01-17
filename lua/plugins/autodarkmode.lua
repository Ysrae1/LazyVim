return {
  {
    "f-person/auto-dark-mode.nvim",
    lazy = false,
    config = function()
      local config = require("nvconfig")
      require("auto-dark-mode").setup({
        update_interval = 1000,
        set_dark_mode = function()
          local dark_theme = config.base46.theme_toggle[1]

          -- print("Current dark in toggle: " .. dark_theme)

          if config.base46.theme ~= dark_theme then
            config.base46.theme = dark_theme
            -- print("Current dark: " .. config.base46.theme .. dark_theme)
            require("base46").load_all_highlights()
          end
        end,
        set_light_mode = function()
          local light_theme = config.base46.theme_toggle[2]

          -- print("Current light in toggle: " .. light_theme)

          if config.base46.theme ~= light_theme then
            config.base46.theme = light_theme
            -- print("Current light: " .. config.base46.theme .. light_theme)

            require("base46").load_all_highlights()
          end
        end,
      })
      require("auto-dark-mode").init()
    end,
  },
}
