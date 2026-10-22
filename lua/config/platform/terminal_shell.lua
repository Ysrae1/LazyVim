-- Interactive terminal preference. Command jobs keep their platform shell/options.
local M = {}
local preference = vim.fn.stdpath("state") .. "/preferences/terminal-shell.json"
local pending, chosen = false, nil
local snacks_commands = {}

local function windows() return vim.fn.has("win32") == 1 end
local function same_path(a, b)
  if windows() then return a:gsub("\\", "/"):lower() == b:gsub("\\", "/"):lower() end
  return a == b
end

function M.available()
  local result, seen = {}, {}
  local function add(id, label, candidates, args)
    for _, candidate in ipairs(candidates) do
      local path = vim.fn.exepath(candidate)
      if path ~= "" and vim.fn.executable(path) == 1 then
        local key = windows() and path:lower() or path
        if not seen[key] then
          seen[key] = true
          result[#result + 1] = { id = id, label = label, path = path, args = args }
        end
        break
      end
    end
  end
  local git_bin = windows() and (vim.env.ProgramFiles or "C:/Program Files") .. "/Git/usr/bin/" or ""
  add("zsh", "zsh", { "zsh", git_bin .. "zsh.exe" }, { "-l", "-i" })
  add("fish", "fish", { "fish" }, { "-l", "-i" })
  -- System32/bash.exe launches WSL; it is not an installed Git Bash shell.
  local bash = windows() and { git_bin .. "bash.exe" } or { "bash" }
  add("bash", windows() and "Git Bash" or "bash", bash, { "-l", "-i" })
  local pwsh = { "pwsh" }
  if windows() then pwsh[#pwsh + 1] = (vim.env.ProgramFiles or "C:/Program Files") .. "/PowerShell/7/pwsh.exe" end
  add("pwsh", "PowerShell", pwsh, { "-NoLogo" })
  if windows() then
    add("powershell", "Windows PowerShell", { "powershell" }, { "-NoLogo" })
    add("cmd", "Command Prompt", { "cmd" }, {})
  else
    add("sh", "sh", { "sh" }, { "-i" })
  end
  return result
end

local function read_choice()
  if chosen then return chosen end
  local ok, lines = pcall(vim.fn.readfile, preference)
  if ok then
    local decoded, value = pcall(vim.json.decode, table.concat(lines, "\n"))
    if decoded and type(value) == "table" and value.version == 1 then chosen = value end
  end
  return chosen
end

function M.current()
  local saved = read_choice()
  if type(saved) ~= "table" or type(saved.path) ~= "string" then return nil end
  for _, candidate in ipairs(M.available()) do
    if saved.id == candidate.id and same_path(saved.path, candidate.path) then return candidate end
  end
end

local function save(shell)
  local value = { version = 1, id = shell.id, path = shell.path }
  local temporary = preference .. "." .. vim.fn.getpid() .. ".tmp"
  local ok = pcall(function()
    vim.fn.mkdir(vim.fn.fnamemodify(preference, ":h"), "p")
    assert(vim.fn.writefile({ vim.json.encode(value) }, temporary) == 0)
    assert(vim.uv.fs_rename(temporary, preference))
  end)
  chosen = value
  if not ok then
    pcall(vim.fn.delete, temporary)
    vim.notify(require("config.platform.locale").t("Could not save terminal preference."), vim.log.levels.WARN)
  end
end

function M.select(callback)
  if pending then return end
  local locale = require("config.platform.locale")
  local choices = M.available()
  if #choices == 0 then
    vim.notify(locale.t("No supported terminal shell is installed."), vim.log.levels.WARN)
    return
  end
  pending = true
  locale.select(choices, {
    prompt = "Choose Terminal Shell",
    format_item = function(item) return locale.t(item.label) end,
  }, function(shell)
    pending = false
    if not shell then return end
    -- A terminal already running retains its process; new terminals use this choice.
    save(shell)
    if callback then callback(shell) end
  end)
end

function M.with_shell(callback)
  local shell = M.current()
  if shell then callback(shell) else M.select(callback) end
end

function M.argv(shell)
  return vim.list_extend({ shell.path }, vim.deepcopy(shell.args))
end

-- ToggleTerm appends its own identity comment to a string command. Quote for
-- the existing command interpreter rather than changing Neovim's global shell.
function M.command(shell)
  local argv = M.argv(shell)
  local interpreter = vim.fs.basename(vim.o.shell):lower()
  if windows() and (interpreter:find("powershell", 1, true) or interpreter:find("pwsh", 1, true)) then
    return "& " .. table.concat(vim.tbl_map(function(arg) return "'" .. arg:gsub("'", "''") .. "'" end, argv), " ")
  end
  return table.concat(vim.tbl_map(vim.fn.shellescape, argv), " ")
end

function M.toggleterm()
  local terms = require("toggleterm.terminal")
  local count = vim.v.count
  local id = count > 0 and count or terms.get_toggled_id()
  local existing = id and terms.get(id, true)
  if existing and existing.job_id and existing.job_id > 0 then
    require("toggleterm").toggle(count)
    return
  end
  M.with_shell(function(shell)
    require("toggleterm.config").get().shell = M.command(shell)
    require("toggleterm").toggle(count)
  end)
end

function M.snacks(opts)
  opts = opts or {}
  local terminal = require("snacks.terminal")
  local key = (opts.cwd or vim.fn.getcwd()) .. "|" .. vim.v.count1
  local previous = snacks_commands[key]
  if previous then
    local existing = terminal.get(previous, vim.tbl_extend("force", opts, { create = false }))
    if existing then existing:toggle(); return end
  end
  M.with_shell(function(shell)
    local argv = M.argv(shell)
    snacks_commands[key] = argv
    terminal.toggle(argv, opts)
  end)
end

function M.setup()
  require("config.platform.locale").command("GlowTerminalShell", function() M.select() end,
    { desc = "Choose Terminal Shell" })
  vim.keymap.set({ "n", "t" }, "<c-/>", function() M.snacks({ cwd = LazyVim.root() }) end,
    { desc = "Terminal (Root Dir)" })
  vim.keymap.set({ "n", "t" }, "<c-_>", function() M.snacks({ cwd = LazyVim.root() }) end,
    { desc = "which_key_ignore" })
  vim.keymap.set("n", "<leader>ft", function() M.snacks({ cwd = LazyVim.root() }) end,
    { desc = "Terminal (Root Dir)" })
  vim.keymap.set("n", "<leader>fT", function() M.snacks() end, { desc = "Terminal (cwd)" })
end

return M
