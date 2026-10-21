-- Profile preference only. Authentication remains owned by GitHub CLI.
local M = {}
local loaded, username, registered = false, nil, false

local function notify(message, level)
  vim.notify(require("config.platform.locale").t(message), level or vim.log.levels.INFO, { title = "GitHub" })
end

function M.normalize(value)
  if type(value) ~= "string" then
    return nil
  end
  value = vim.trim(value)
  value = value:gsub("^https://github%.com/", ""):gsub("/$", "")
  if #value < 1 or #value > 39 or not value:match("^[A-Za-z0-9][A-Za-z0-9%-]*$")
    or value:sub(-1) == "-" or value:find("--", 1, true) then
    return nil
  end
  return value
end

local function state_path()
  return vim.fn.stdpath("state") .. "/glow/github.json"
end

function M.get_user()
  if not loaded then
    loaded = true
    local ok, lines = pcall(vim.fn.readfile, state_path())
    if ok then
      local decoded, data = pcall(vim.json.decode, table.concat(lines, "\n"))
      if decoded and type(data) == "table" then
        username = M.normalize(data.username)
      end
    end
  end
  return username
end

function M.set_user(value)
  local normalized = value ~= nil and M.normalize(value) or nil
  if value ~= nil and not normalized then
    notify("请输入有效的 GitHub 用户名，或 https://github.com/用户名。", vim.log.levels.WARN)
    return false
  end
  local path = state_path()
  local ok, result = pcall(function()
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    return vim.fn.writefile({ vim.json.encode({ version = 1, username = normalized }) }, path)
  end)
  if not ok or result ~= 0 then
    notify("无法保存 GitHub 个人设置。", vim.log.levels.ERROR)
    return false
  end
  loaded, username = true, normalized
  vim.cmd("redrawtabline")
  return true
end

function M.profile_url()
  local user = M.get_user()
  return "https://github.com" .. (user and "/" .. user or "")
end

function M.open()
  local ok, _, err = pcall(vim.ui.open, M.profile_url())
  if not ok or err then
    notify("无法打开浏览器，请检查系统默认浏览器。", vim.log.levels.WARN)
  end
end

local function have_gh()
  if vim.fn.executable("gh") ~= 1 then
    notify("未安装 GitHub CLI（gh）；仍可直接设置用户名和打开个人主页。", vim.log.levels.WARN)
    return false
  end
  return true
end

function M.import_user()
  if not have_gh() then
    return
  end
  -- Invoked only by an explicit menu/command action; never request a token.
  vim.system({ "gh", "api", "user", "--hostname", "github.com", "--jq", ".login" }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 or not M.normalize(result.stdout) then
        notify("无法读取 GitHub 账户；请先登录 gh，或手动设置用户名。", vim.log.levels.WARN)
        return
      end
      if M.set_user(result.stdout) then
        notify("已使用 GitHub CLI 当前登录的用户名。")
      end
    end)
  end)
end

function M.login()
  if not have_gh() then
    return
  end
  -- Authentication is interactive and is never started while rendering the badge.
  vim.cmd("botright 12new")
  local job = vim.fn.jobstart({ "gh", "auth", "login", "--hostname", "github.com", "--web" }, {
    term = true,
    on_exit = function(_, code)
      if code == 0 then
        vim.schedule(M.import_user)
      end
    end,
  })
  if job <= 0 then
    notify("无法启动 GitHub 登录终端。", vim.log.levels.ERROR)
    return
  end
  vim.cmd("startinsert")
end

function M.prompt_user()
  require("config.platform.locale").input({ prompt = "GitHub 用户名 / 个人主页：", default = M.get_user() or "" }, function(value)
    if value ~= nil then
      M.set_user(value)
    end
  end)
end

function M.menu()
  local actions = {
    { "打开个人主页", M.open },
    { "设置 GitHub 用户名", M.prompt_user },
    { "使用 gh 当前登录账户", M.import_user },
    { "登录 GitHub（gh）", M.login },
    { "清除主页设置（保留 gh 登录）", function() M.set_user(nil) end },
  }
  require("config.platform.locale").select(actions, { prompt = "GitHub", format_item = function(item) return require("config.platform.locale").t(item[1]) end }, function(item)
    if item then
      item[2]()
    end
  end)
end

function M.setup()
  if registered then
    return
  end
  registered = true
  require("config.platform.locale").command("GlowGitHub", function(opts)
    local action = opts.fargs[1] or "menu"
    if action == "set" then
      if opts.fargs[2] then M.set_user(opts.fargs[2]) else M.prompt_user() end
    elseif action == "clear" then
      M.set_user(nil)
    elseif action == "open" then
      M.open()
    elseif action == "import" then
      M.import_user()
    elseif action == "login" then
      M.login()
    elseif action == "menu" then
      M.menu()
    else
      notify("用法：GlowGitHub [menu|open|set 用户名|import|login|clear]", vim.log.levels.WARN)
    end
  end, {
    nargs = "*",
    desc = "GitHub 个人主页与主动登录",
    complete = function() return { "menu", "open", "set", "import", "login", "clear" } end,
  })
  vim.cmd([[
    function! TbOpenGitHubProfile(a,b,c,d)
      lua require('config.integrations.github').menu()
    endfunction
  ]])
end

function M.badge()
  M.setup()
  return require("nvchad.tabufline.utils").btn("  " .. (M.get_user() or "GitHub") .. " ", "TabCloseBtn", "OpenGitHubProfile")
end

return M
