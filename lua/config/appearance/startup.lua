-- Set the cache path before plugins load. base46 creates it after loading;
-- reading generated files here prevents a fresh or cleaned install from starting.
-- Keep terminal transparency out of Neovide's cached plugin highlights.
local cache_dir = vim.g.neovide and "base46/" or "base46-terminal/"
vim.g.base46_cache = vim.fn.stdpath("data") .. "/" .. cache_dir
require("config.appearance.terminal").setup()

local handle = io.popen("defaults read -g AppleInterfaceStyle 2>/dev/null")
local result = handle and handle:read("*a") or ""
if handle then
  handle:close()
end
local config = require("chadrc")

-- 根据系统设置选择使用暗色或亮色主题
if result:match("Dark") then
  --
  --
  -- vim.cmd("colorscheme onehalf-lush-dark")
  config.base46.theme = config.base46.theme_toggle[1]
else
  config.base46.theme = config.base46.theme_toggle[2]
end
