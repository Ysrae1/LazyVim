-- Yazi's native Neovide preview is scoped to its embedded instance. A private
-- config overlays one previewer; the user's standalone Yazi files stay intact.
local M = {}
local transport = require("config.media.image_transport")
local sessions, native, configured = {}, {}, false
local pending = false
local uv = vim.uv or vim.loop
local event_kind = "neovide-glow-preview"
local plugin_name = "neovide-glow-native-preview"
local module_dir = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
local overlays = {}

local function available()
  return vim.g.neovide_native_image == true and type(vim.g.neovide_channel_id) == "number"
end

local function rpc(method, ...)
  return available() and transport.notify("yazi", method, ...)
end

local function release(session)
  if session.id then
    native[session.id] = nil
    rpc("close", session.id)
    session.id, session.geometry = nil, nil
  end
end

local function cleanup(buf)
  local session = sessions[buf]
  if session then release(session); sessions[buf] = nil end
  if next(sessions) == nil then
    for directory in pairs(overlays) do vim.fn.delete(directory, "rf") end
  end
end

local function border(config, side)
  local chars = config.border
  if type(chars) ~= "table" then return 0 end
  local indices = side == "top" and { 1, 2, 3 } or side == "left" and { 1, 8, 7 }
    or side == "right" and { 3, 4, 5 } or { 5, 6, 7 }
  for _, index in ipairs(indices) do
    local char = chars[index]
    if type(char) == "table" then char = char[1] end
    if char and char ~= "" then return 1 end
  end
  return 0
end

local function intersects(a, b)
  return a.row < b.row + b.height and b.row < a.row + a.height
    and a.col < b.col + b.width and b.col < a.col + a.width
end

local function geometry(session)
  local win = session.win
  if not win or not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= session.buf
    or vim.api.nvim_win_get_tabpage(win) ~= vim.api.nvim_get_current_tabpage()
    or vim.api.nvim_get_current_win() ~= win or not session.visible or not session.region or not session.path
    or vim.fn.pumvisible() == 1 or vim.api.nvim_get_mode().mode:sub(1, 1) == "c" then return nil end
  local info = vim.fn.getwininfo(win)[1]
  if not info then return nil end
  local config = vim.api.nvim_win_get_config(win)
  local position = vim.api.nvim_win_get_position(win)
  local top = position[1] + border(config, "top") + (info.winbar or 0)
  local left = position[2] + border(config, "left")
  local region = session.region
  -- Job.area is Yazi's actual preview rectangle in terminal cells, rather than
  -- a guessed ratio. Reject stale rectangles during a terminal/window resize.
  if region.x < 0 or region.y < 0 or region.w <= 0 or region.h <= 0
    or region.x + region.w > info.width or region.y + region.h > info.height then return nil end
  local view = { row = top + region.y, col = left + region.x, width = region.w, height = region.h,
    zoom = 1, pan_x = 0, pan_y = 0, overlay = config.relative ~= "" }
  for _, other in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if other ~= win then
      local other_config = vim.api.nvim_win_get_config(other)
      if other_config.relative ~= "" and (other_config.zindex or 50) >= (config.zindex or 0) then
        local p = vim.api.nvim_win_get_position(other)
        local bounds = { row = p[1], col = p[2],
          width = vim.api.nvim_win_get_width(other) + border(other_config, "left") + border(other_config, "right"),
          height = vim.api.nvim_win_get_height(other) + border(other_config, "top") + border(other_config, "bottom") }
        if intersects(view, bounds) then return nil end
      end
    end
  end
  return view
end

function M.refresh()
  pending = false
  for buf, session in pairs(sessions) do
    if not vim.api.nvim_buf_is_valid(buf) then cleanup(buf)
    else
      local view = geometry(session)
      if not view or session.error then release(session)
      else
        if not session.id then
          session.id, session.error = transport.allocate("yazi")
          if session.id then
            native[session.id] = session
            if not rpc("load", session.id, session.path) then release(session) end
          else
            vim.notify(session.error, vim.log.levels.WARN, { title = "Neovide Glow" })
          end
        end
        if session.id and not vim.deep_equal(session.geometry, view) then
          rpc("show", session.id, view)
          session.geometry = view
        end
      end
    end
  end
end

local function schedule()
  if pending then return end
  pending = true
  vim.schedule(M.refresh)
end

function M.on_status(id, width, height, err)
  local session = native[id]
  if not session or session.id ~= id then return end
  if err and err ~= vim.NIL and err ~= "" then
    session.error = tostring(err)
    release(session)
    vim.notify("Yazi 图片预览失败：" .. session.error, vim.log.levels.WARN, { title = "Neovide Glow" })
  else session.width, session.height = width, height end
end

local function session_for(yazi_id)
  for _, session in pairs(sessions) do
    if tostring(session.yazi_id) == tostring(yazi_id) then return session end
  end
end

local function on_message(event)
  local data = event.data
  if not data or data.type ~= event_kind then return end
  local session = session_for(data.yazi_id)
  if not session then return end
  local ok, payload = pcall(vim.json.decode, data.raw_data or "")
  if not ok or type(payload) ~= "table" then return end
  if payload.action == "state" then
    if session.source ~= payload.source then
      release(session)
      session.path, session.region, session.error = nil, nil, nil
    end
    session.source, session.visible = payload.source, payload.visible == true
  elseif payload.action == "clear" then
    release(session)
    session.source, session.path, session.region, session.error = payload.source, nil, nil, nil
  elseif payload.action == "preview" and type(payload.source) == "string" and type(payload.path) == "string" and type(payload.area) == "table" then
    local area = payload.area
    for _, key in ipairs({ "x", "y", "w", "h" }) do
      if type(area[key]) ~= "number" or area[key] ~= area[key] or math.abs(area[key]) > 1000000 then return end
    end
    if session.source ~= payload.source or session.path ~= payload.path then release(session) end
    session.source, session.path, session.region, session.visible, session.error = payload.source, payload.path, area, payload.visible == true, nil
  else return end
  schedule()
end

local function overlay(source, target)
  vim.fn.mkdir(target .. "/plugins", "p", 448)
  local iterator = uv.fs_scandir(source)
  if iterator then
    while true do
      local name = uv.fs_scandir_next(iterator)
      if not name then break end
      if name ~= "plugins" and name ~= "yazi.toml" and name ~= "init.lua" then
        local destination = target .. "/" .. name
        if not uv.fs_lstat(destination) then assert(uv.fs_symlink(source .. "/" .. name, destination)) end
      end
    end
  end
  local user_plugins = uv.fs_scandir(source .. "/plugins")
  if user_plugins then
    while true do
      local name = uv.fs_scandir_next(user_plugins)
      if not name then break end
      local destination = target .. "/plugins/" .. name
      if name ~= plugin_name .. ".yazi" and name ~= "neovide-glow-jxl.yazi" and not uv.fs_lstat(destination) then
        assert(uv.fs_symlink(source .. "/plugins/" .. name, destination))
      end
    end
  end
  local own_plugin = target .. "/plugins/" .. plugin_name .. ".yazi"
  local own_metadata = uv.fs_lstat(own_plugin)
  if own_metadata and own_metadata.type == "link" then assert(uv.fs_unlink(own_plugin)) end
  vim.fn.mkdir(own_plugin, "p", 448)
  assert(uv.fs_copyfile(module_dir .. "/yazi/" .. plugin_name .. ".yazi/main.lua", own_plugin .. "/main.lua"))
  local python = vim.fn.exepath("python3")
  local ok, runtime = pcall(require, "config.media.runtime")
  if ok and vim.fn.executable(runtime.python()) == 1 then python = runtime.python() end
  if python == "" then error("Yazi 原生预览配置需要 Python 3.11+（TOML 标准库）。") end
  local output = vim.fn.system({ python, module_dir .. "/yazi/overlay.py", source, target, module_dir .. "/yazi" })
  if vim.v.shell_error ~= 0 then error("无法准备 Yazi 原生预览配置：" .. output) end
  local init = { 'require("' .. plugin_name .. '"):install()' }
  if vim.fn.filereadable(source .. "/init.lua") == 1 then init[#init + 1] = "dofile(" .. string.format("%q", source .. "/init.lua") .. ")" end
  init[#init + 1] = 'require("' .. plugin_name .. '"):setup()'
  vim.fn.writefile(init, target .. "/init.lua")
end

function M.setup()
  if configured then return end
  configured = true
  local group = vim.api.nvim_create_augroup("GlowYaziNativePreview", { clear = true })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "YaziDDSCustom", callback = on_message })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "YaziDDSHover", callback = function(event)
    local data = event.data or {}
    local session = session_for(data.yazi_id)
    if session and session.source ~= data.url then
      release(session)
      session.source, session.path, session.region, session.error = data.url, nil, nil, nil
    end
  end })
  vim.api.nvim_create_autocmd({ "WinResized", "VimResized", "TabEnter", "WinEnter", "WinClosed", "BufWinEnter", "BufWinLeave", "CompleteChanged", "CompleteDone", "CmdlineEnter", "CmdlineLeave" }, {
    group = group, callback = schedule,
  })
  vim.api.nvim_create_autocmd({ "TermClose", "BufWipeout" }, { group = group, callback = function(event) cleanup(event.buf) end })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = function()
    for buf in pairs(sessions) do cleanup(buf) end
    for directory in pairs(overlays) do vim.fn.delete(directory, "rf") end
  end })
end

-- Use as yazi.nvim opts transformer. All pre-existing hooks are preserved.
function M.configure(opts)
  opts = opts or {}
  if not available() then return opts end
  M.setup()
  local source = opts.config_home or vim.env.YAZI_CONFIG_HOME or ((vim.env.XDG_CONFIG_HOME or vim.fn.expand("~/.config")) .. "/yazi")
  source = vim.fs.normalize(vim.fn.fnamemodify(source, ":p"))
  local target = vim.fn.tempname() .. "-glow-yazi"
  overlays[target] = true
  opts.config_home = target
  opts.forwarded_dds_events = opts.forwarded_dds_events or { "nvim-cycle-buffer" }
  if not vim.tbl_contains(opts.forwarded_dds_events, event_kind) then opts.forwarded_dds_events[#opts.forwarded_dds_events + 1] = event_kind end
  opts.hooks = opts.hooks or {}
  local before, opened, ready, closed = opts.hooks.before_opening_window, opts.hooks.yazi_opened, opts.hooks.on_yazi_ready, opts.hooks.yazi_closed_successfully
  opts.hooks.before_opening_window = function(window_opts)
    overlay(source, target)
    if before then before(window_opts) end
  end
  opts.hooks.yazi_opened = function(path, buf, config)
    local wins = vim.fn.win_findbuf(buf)
    sessions[buf] = { buf = buf, win = wins[1], source = path, visible = true }
    if opened then opened(path, buf, config) end
  end
  opts.hooks.on_yazi_ready = function(buf, config, api)
    local session = sessions[buf]
    if session then session.yazi_id = api.yazi_id end
    if ready then ready(buf, config, api) end
    api:emit_to_yazi({ "peek", "--force" })
  end
  opts.hooks.yazi_closed_successfully = function(path, config, state)
    for buf, session in pairs(sessions) do
      if not vim.api.nvim_win_is_valid(session.win) then cleanup(buf) end
    end
    if closed then closed(path, config, state) end
  end
  return opts
end

function M.status()
  local result = {}
  for buf, session in pairs(sessions) do
    result[buf] = { source = session.source, path = session.path, region = session.region, visible = session.visible, id = session.id, yazi_id = session.yazi_id }
  end
  return result
end

return M
