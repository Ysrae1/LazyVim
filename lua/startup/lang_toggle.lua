local M = {}

local lang_file = vim.fn.stdpath("config") .. "/lang_setting.txt"

function M.toggle_lang()
  if vim.env.LANG == "en_US.UTF-8" then
    vim.env.LANG = "zh_CN.UTF-8"
    vim.env.LC_ALL = "zh_CN.UTF-8"
    print("语言已切换至中文，重启以应用。")
  else
    vim.env.LANG = "en_US.UTF-8"
    vim.env.LC_ALL = "en_US.UTF-8"
    print("Switched language to English, relaunch to apply changes.")
  end
  M.save_language_settings()
end

-- 保存语言设置到文件
function M.save_language_settings()
  vim.fn.writefile({ vim.env.LANG }, lang_file)
end

-- 从文件加载语言设置
function M.load_language_settings()
  if vim.fn.filereadable(lang_file) == 1 then
    local lang = vim.fn.readfile(lang_file)[1]
    vim.env.LANG = lang
    vim.env.LC_ALL = lang
  end
end

vim.keymap.set("n", "<leader><C-l>", M.toggle_lang, { noremap = true, silent = true, desc = "Toggle Language" })


-- 加载语言设置并设置快键
M.load_language_settings()

return M
