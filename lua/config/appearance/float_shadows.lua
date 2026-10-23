-- One publisher owns the complete window-ID shadow exclusion snapshot. The
-- platform entry point opts macOS Notebook output into this same controller.
local M = {}
local api = vim.api
local previous, previous_channel, generation = nil, nil, 0
local notebook_output, matrix_intro = false, false
local lifecycle_installed = false
local child = {
  SnacksPickerInput = true, SnacksPickerInputBorder = true,
  SnacksPickerList = true, SnacksPickerListBorder = true,
  SnacksPickerPreview = true, SnacksPickerPreviewBorder = true,
}

local function roles(win)
  local is_child, is_box = false, false
  for _, mapping in ipairs(vim.split(vim.wo[win].winhighlight, ",", { plain = true })) do
    local name = mapping:match("^[^:]+:(.+)$")
    is_child = is_child or child[name] == true
    is_box = is_box or name == "SnacksPickerBox" or name == "SnacksPickerBoxBorder"
  end
  return is_child, is_box
end

local function publish(windows, redraw)
  local channel = vim.g.neovide_channel_id
  if type(channel) ~= "number" or channel <= 0
    or (previous_channel == channel and vim.deep_equal(previous, windows)) then return end
  local ok = pcall(vim.rpcnotify, channel, "neovide.window.shadow_exclusions", windows)
  if not ok then return end
  previous, previous_channel = windows, channel
  if redraw then vim.cmd.redraw() end
end

local function refresh()
  local windows, configs, children, boxes = {}, {}, {}, {}
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    local config = api.nvim_win_get_config(win)
    if config.relative ~= "" then
      configs[win] = config
      children[win], boxes[win] = roles(win)
      if notebook_output and vim.bo[api.nvim_win_get_buf(win)].filetype == "molten_output" then
        children[win] = true
      end
      if matrix_intro and vim.w[win].glow_popup_profile == "matrix_intro" then
        children[win] = true
      end
    end
  end
  local which_key = package.loaded["which-key.view"]
  local footer = which_key and which_key.footer and which_key.footer.win
  local parent = which_key and which_key.view and which_key.view.win
  if footer and parent and configs[footer] and configs[parent]
    and configs[footer].relative == "win" and configs[footer].win == parent then
    children[footer] = true
  end
  for win, config in pairs(configs) do
    local nested_box = boxes[win] and config.relative == "win" and boxes[config.win]
    if children[win] or nested_box then windows[#windows + 1] = win end
  end
  table.sort(windows)
  publish(windows, true)
end

-- Providers that assign their identity after nvim_open_win must publish before
-- their first redraw, rather than waiting for the queued WinNew observer.
function M.refresh()
  if vim.g.neovide then refresh() end
end

function M.setup(opts)
  if not vim.g.neovide then return false end
  if opts then
    if opts.notebook_output ~= nil then notebook_output = opts.notebook_output == true end
    if opts.matrix_intro ~= nil then matrix_intro = opts.matrix_intro == true end
  end
  -- A legacy frontend may have replaced the backend snapshot since our last
  -- publication. An ownership claim must republish even if our IDs are equal.
  previous, previous_channel = nil, nil
  if not lifecycle_installed then
    lifecycle_installed = true
    local lifecycle = api.nvim_create_augroup("GlowFloatShadowOwner", { clear = true })
    -- Neovide injects its compatibility script before ui_attach. Reclaim once
    -- at that real boundary too, for an existing server whose config ran first.
    api.nvim_create_autocmd("UIEnter", { group = lifecycle, once = true, callback = function() M.setup() end })
  end
  generation = generation + 1
  local owner, queued = generation, false
  local function schedule()
    if queued then return end
    queued = true
    vim.schedule(function()
      if owner ~= generation then return end
      queued = false
      refresh()
    end)
  end
  -- Reuse the embedded controller's augroup: the already-installed frontend
  -- yields ownership here on a new session, without replacing the application.
  local group = api.nvim_create_augroup("neovide_composed_float_shadow", { clear = true })
  api.nvim_create_autocmd({ "WinNew", "WinClosed", "WinEnter", "BufWinEnter", "TabEnter" }, {
    group = group, callback = schedule,
  })
  api.nvim_create_autocmd("OptionSet", { group = group, pattern = "winhighlight", callback = schedule })
  api.nvim_create_autocmd("FileType", { group = group, callback = schedule })
  api.nvim_create_autocmd("User", { group = group, pattern = "NeovideFloatChanged", callback = schedule })
  api.nvim_create_autocmd("TabLeave", { group = group, callback = function() publish({}, false) end })
  schedule()
  return true
end

return M
