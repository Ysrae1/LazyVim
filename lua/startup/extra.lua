local M = {}

vim.api.nvim_create_autocmd("FileType", {
  pattern = "neo-tree",
  callback = function()
    vim.cmd("stopinsert")
  end,
})

vim.o.wrap = true
vim.o.linebreak = false
vim.o.list = false -- extra option I set in addition to the ones in your question

require("toggles")

return M
