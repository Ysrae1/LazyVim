local M = {}

function M.apply()
  local base46 = package.loaded.base46
  if type(base46) ~= "table" then
    return
  end
  local syntax = base46.get_theme_tb("base_16")
  local colors = base46.get_theme_tb("base_30")
  -- 复制反馈独立使用 base0F；保留 IncSearch 原来的搜索高亮。
  local foreground = vim.o.background == "dark" and colors.black or colors.white
  vim.api.nvim_set_hl(0, "Base46Yank", { bg = syntax.base0F, fg = foreground })
end

function M.setup()
  -- Replace LazyVim's default callback so copying only flashes once.
  local group = vim.api.nvim_create_augroup("lazyvim_highlight_yank", { clear = true })
  vim.api.nvim_create_autocmd("TextYankPost", {
    group = group,
    desc = "Highlight copied text with Base46 base0F",
    callback = function()
      -- Base46 直接加载高亮时 colors_name 可以为空，与兼容层的判断保持一致。
      local use_base46 = package.loaded.base46
        and (vim.g.colors_name == nil or vim.g.colors_name == "nvchad")
      local highlight = vim.hl or vim.highlight
      highlight.on_yank({
        higroup = use_base46 and "Base46Yank" or "IncSearch",
      })
    end,
  })
  M.apply()
end

return M
