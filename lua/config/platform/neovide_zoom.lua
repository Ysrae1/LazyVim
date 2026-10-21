local M = {}

local state_dir = vim.fn.stdpath("state") .. "/neovide"
local scale_file = state_dir .. "/scale_factor.txt"
local legacy_scale_file = vim.fn.stdpath("config") .. "/archive/legacy/scale_factor.txt"

local function parse_scale(value)
  local scale = tonumber(value)
  if not scale or scale ~= scale or scale == math.huge or scale == -math.huge then
    return nil
  end
  return math.max(0.5, math.min(2.0, scale))
end

local function read_scale(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local value = file:read("*a")
  file:close()
  return parse_scale(value)
end

function M.load_scale_factor()
  vim.g.neovide_scale_factor = read_scale(scale_file)
    or read_scale(legacy_scale_file)
    or parse_scale(vim.g.neovide_scale_factor)
    or 1.0
end

function M.save_scale_factor()
  local scale = parse_scale(vim.g.neovide_scale_factor) or 1.0
  vim.g.neovide_scale_factor = scale
  local ok, err = pcall(function()
    vim.fn.mkdir(state_dir, "p")
    if vim.fn.writefile({ tostring(scale) }, scale_file) ~= 0 then
      error("could not write " .. scale_file)
    end
  end)
  if not ok then
    vim.notify("Could not save Neovide scale: " .. tostring(err), vim.log.levels.WARN)
  end
end

function M.adjust(delta)
  vim.g.neovide_scale_factor = parse_scale((parse_scale(vim.g.neovide_scale_factor) or 1.0) + delta)
end

function M.reset()
  vim.g.neovide_scale_factor = 1.0
end

-- Retire only the exact old owned Mac shortcut. Inspect global x/s separately
-- so a user-specific Select mapping or buffer-local override is not removed.
local legacy_nine_descriptions = { ["Decrease Neovide scale"] = true, ["缩小 Neovide 界面"] = true }
local function retire_mac_nine()
  for _, mode in ipairs({ "n", "i", "x", "s", "c", "t" }) do
    for _, map in ipairs(vim.api.nvim_get_keymap(mode)) do
      if map.lhs == "<D-9>" and legacy_nine_descriptions[map.desc] and type(map.callback) == "function" then
        local info = debug.getinfo(map.callback, "S")
        local source = info and info.source:gsub("\\", "/") or ""
        -- These positions identify decrease() in the released pre-migration
        -- neovide_zoom.lua (SHA135fb200). Description alone is not ownership.
        if source:match("/lua/config/platform/neovide_zoom%.lua$")
          and info.linedefined == 66 and info.lastlinedefined == 68 then
          pcall(vim.keymap.del, mode, "<D-9>")
        end
      end
    end
  end
end

function M.setup(opts)
  if not vim.g.neovide then
    return
  end
  opts = opts or {}
  local modes = { "n", "i", "v", "c", "t" }
  local function bind(key, callback, description)
    vim.keymap.set(modes, key, callback, { silent = true, desc = description })
  end
  local function increase()
    M.adjust(0.1)
  end
  local function decrease()
    M.adjust(-0.1)
  end

  if vim.fn.has("macunix") == 1 then
    retire_mac_nine()
    bind("<D-=>", increase, "Increase Neovide scale")
    bind("<D-+>", increase, "Increase Neovide scale")
    bind("<D-->", decrease, "Decrease Neovide scale")
    bind("<D-0>", M.reset, "Reset Neovide scale")
  elseif vim.fn.has("win32") == 1 then
    bind("<C-=>", increase, "Increase Neovide scale")
    bind("<C-+>", increase, "Increase Neovide scale")
    bind("<C-->", decrease, "Decrease Neovide scale")
    bind("<C-0>", M.reset, "Reset Neovide scale")
  end

  -- Hot-loading bindings need not replace the scale of the current session.
  if opts.load ~= false then
    M.load_scale_factor()
  end
  local group = vim.api.nvim_create_augroup("UserNeovideScale", { clear = true })
  vim.api.nvim_create_autocmd("SessionLoadPost", { group = group, callback = M.load_scale_factor })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.save_scale_factor })
end

return M
