-- Normal use stays on the checked-in dependency snapshot. For a deliberate
-- maintenance session only: NVIM_UPDATE_PLUGINS=1 nvim
-- Existing explicit pins (including both Treesitter plugins) remain in force.
if vim.env.NVIM_UPDATE_PLUGINS == "1" then
  return {}
end

local lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json"
local ok, lock = pcall(function()
  return vim.json.decode(table.concat(vim.fn.readfile(lockfile), "\n"))
end)
if not ok or type(lock) ~= "table" then
  error("Cannot load the frozen plugin snapshot: " .. lockfile .. "\n" .. tostring(lock))
end

local plugins = {}
for _, name in ipairs(vim.tbl_keys(lock)) do
  local entry = lock[name]
  if type(entry) ~= "table" or type(entry.commit) ~= "string" or not entry.commit:match("^%x+$") then
    error("Invalid commit in frozen plugin snapshot: " .. name)
  end
  -- optional merges by name into an existing spec; disabled/removed plugins
  -- are not re-enabled, and the original repository URL is preserved.
  plugins[#plugins + 1] = { name, optional = true, commit = entry.commit, pin = true }
end
table.sort(plugins, function(a, b)
  return a[1] < b[1]
end)
return plugins
