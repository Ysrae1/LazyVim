vim.o.shell = "/bin/zsh --login"

vim.o.encoding = "utf-8"
vim.o.fileencoding = "utf-8"

vim.wo.wrap = true
vim.wo.linebreak = true
vim.wo.list = false -- extra option I set in addition to the ones in your question

vim.o.number = true
vim.o.relativenumber = true
-- -- 强制将语言环境设置为中文

vim.cmd([[highlight FloatingWindow guibg=#2E3440]])
vim.cmd([[highlight FloatingBorder guifg=#81A1C1 guibg=#2E3440]])

if vim.g.neovide then
  local api = vim.api
  vim.g.dashboard_disable_at_vimenter = 2
  vim.g.neovide_scale_factor = 1
  local function open_floating_terminal()
    local width = math.floor(vim.o.columns * 4)
    local height = math.floor(vim.o.lines * 4)
    local col = math.floor((vim.o.columns - width) / 2)
    local row = math.floor((vim.o.lines - height) / 2)

    local opts = {
      style = "minimal",
      relative = "editor",
      width = width,
      height = height,
      col = col,
      row = row,
      border = "shadow",
    }

    local buf = api.nvim_create_buf(false, true)
    local win = api.nvim_open_win(buf, true, opts)

    vim.cmd(
      -- "terminal timeout 4 cmatrix -c -a -b -u 0"

      -- "terminal timeout 4 /Users/ysrae1/go/bin/gomatrix -p 60"
      "terminal timeout 4 unimatrix -o -s 100"
    ) -- 替换 'ls' 为你需要自动执行的命令
    vim.defer_fn(function()
      if api.nvim_win_is_valid(win) then
        api.nvim_win_close(win, true)
      end
      -- 检查缓冲区是否仍然有效，并删除它
      if api.nvim_buf_is_valid(buf) then
        api.nvim_buf_delete(buf, { force = true })
      end
    end, 2000)
    -- 替换 'ls' 为你需要自动执行的命令
  end
  --
  -- 设置自动命令，在 Neovim 启动时执行
  vim.api.nvim_create_autocmd("VimEnter", {
    pattern = "*",
    callback = function()
      vim.defer_fn(function()
        open_floating_terminal()
      end, 1)
      vim.defer_fn(function()
        vim.g.neovide_scale_factor = 0.85
      end, 500)
    end,
  })
end
