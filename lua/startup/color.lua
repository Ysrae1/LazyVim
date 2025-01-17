-- put this in your main init.lua file ( before lazy setup )
vim.g.base46_cache = vim.fn.stdpath("data") .. "/base46/"

-- put this after lazy setup

-- (method 1, For heavy lazyloaders)
dofile(vim.g.base46_cache .. "defaults")
dofile(vim.g.base46_cache .. "statusline")

-- (method 2, for non lazyloaders) to load all highlights at once
for _, v in ipairs(vim.fn.readdir(vim.g.base46_cache)) do
  dofile(vim.g.base46_cache .. v)
end

local handle = io.popen("defaults read -g AppleInterfaceStyle 2>/dev/null")
local result = handle:read("*a")
handle:close()
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
