if vim.g.neovide then
  vim.print(vim.g.neovide_version)
  -- vim.o.guifont = "CodeNewRoman Nerd Font Mono:h18"
  vim.o.guifont = "FiraCode Nerd Font Mono:h16"

  vim.opt.linespace = 0
  -- vim.g.neovide_scale_factor = 1.0
  vim.g.neovide_text_gamma = 0.0
  vim.g.neovide_text_contrast = 0.5

  vim.g.neovide_padding_top = 0
  vim.g.neovide_padding_bottom = 0
  vim.g.neovide_padding_right = 0
  vim.g.neovide_padding_left = 0

  vim.g.neovide_floating_shadow = true
  vim.g.neovide_floating_z_height = 2
  vim.g.neovide_light_angle_degrees = 45
  vim.g.neovide_light_radius = 10

  vim.g.neovide_floating_blur_amount_x = 24.0
  vim.g.neovide_floating_blur_amount_y = 24.0

  vim.g.neovide_floating_corner_radius = 0.48

  vim.g.neovide_opacity = 0.95
  vim.g.neovide_normal_opacity = 0.9

  vim.g.neovide_refresh_rate = 120

  -- vim.g.neovide_show_border = true
  vim.g.neovide_window_blurred = true

  vim.g.neovide_theme = "auto"

  vim.g.neovide_remember_window_size = true

  vim.g.neovide_profiler = false
  vim.g.neovide_cursor_smooth_blink = true
  vim.g.neovide_cursor_animation_length = 0.15
  vim.g.neovide_cursor_short_animation_length = 0.04

  vim.g.neovide_cursor_trail_size = 0.6

  vim.g.neovide_cursor_vfx_mode = "railgun"
  vim.g.neovide_cursor_vfx_opacity = 200.0
  vim.g.neovide_cursor_vfx_particle_lifetime = 1.0
  vim.g.neovide_cursor_vfx_particle_density = 6.0
  vim.g.neovide_cursor_vfx_particle_speed = 15.0
  vim.g.neovide_cursor_vfx_particle_phase = 1.5
  vim.g.neovide_cursor_vfx_particle_curl = 1.0

  if vim.g.neovide then
    function _G.adjust_scale_factor()
      local min_scale = 0.5
      local max_scale = 2.0
      local current_scale = vim.g.neovide_scale_factor or 1.0

      if current_scale < min_scale then
        vim.g.neovide_scale_factor = min_scale
      elseif current_scale > max_scale then
        vim.g.neovide_scale_factor = max_scale
      end
    end

    vim.api.nvim_set_keymap(
      "n",
      "<D-->",
      "<cmd>lua vim.g.neovide_scale_factor = (vim.g.neovide_scale_factor or 1) + 0.1; adjust_scale_factor()<CR>",
      { noremap = true, silent = true }
    )
    vim.api.nvim_set_keymap(
      "n",
      "<D-9>",
      "<cmd>lua vim.g.neovide_scale_factor = (vim.g.neovide_scale_factor or 1) - 0.1; adjust_scale_factor()<CR>",
      { noremap = true, silent = true }
    )
  end

  vim.api.nvim_set_keymap(
    "n",
    "<D-0>",
    "<cmd>lua vim.g.neovide_scale_factor = 1<CR>",
    { noremap = true, silent = true }
  )
  -- 定义保存 scale_factor 的函数
  function save_scale_factor()
    local scale_file = vim.fn.stdpath("config") .. "/scale_factor.txt"
    local scale_factor = vim.g.neovide_scale_factor or 1
    local file = io.open(scale_file, "w")
    if file then
      file:write(tostring(scale_factor))
      file:close()
    end
  end

  -- 设置自动命令，在 Vim 退出时调用 save_scale_factor
  vim.cmd([[
    autocmd VimLeave * lua save_scale_factor()
  ]])

  -- 定义加载 scale_factor 的函数
  function load_scale_factor()
    local scale_file = vim.fn.stdpath("config") .. "/scale_factor.txt"
    local file = io.open(scale_file, "r")
    if file then
      local scale_factor = file:read("*a") -- 读取全部内容
      file:close()
      if scale_factor ~= "" then
        vim.g.neovide_scale_factor = tonumber(scale_factor)
      end
    end
  end

  -- 使用 SessionLoadPost 事件在 session 加载后调用 load_scale_factor
  vim.cmd([[
    autocmd SessionLoadPost * lua load_scale_factor()
  ]])
  -- vim.cmd([[
  --   autocmd VimEnter * lua load_scale_factor()
  --   ]])
end

-- 自定义终端颜色

-- vim.g.terminal_color_0 = "#484c6b"
-- vim.g.terminal_color_2 = "#a7cc76"
-- vim.g.terminal_color_1 = "#da6571"
-- vim.g.terminal_color_4 = "#909aea"
-- vim.g.terminal_color_3 = "#80b8df"
-- vim.g.terminal_color_6 = "#b8d9f7"
-- vim.g.terminal_color_5 = "#9752c6"
-- vim.g.terminal_color_8 = "#53597b"
-- vim.g.terminal_color_7 = "#fbfbfb"
-- vim.g.terminal_color_10 = "#a7cc76"
-- vim.g.terminal_color_9 = "#e67d8f"
-- vim.g.terminal_color_12 = "#82a0f0"
-- vim.g.terminal_color_11 = "#d8b072"
-- vim.g.terminal_color_14 = "#519ff3"
-- vim.g.terminal_color_13 = "#b59bf0"
-- vim.g.terminal_color_15 = "#c1c9f1"
