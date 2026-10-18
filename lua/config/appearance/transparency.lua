-- Background-only transparency. Neovide keeps foreground text fully opaque.
local M = {}
local configured, queued = false, false
local material_blend = 40 -- Every glass component uses 60% background opacity.
-- Base surfaces precede aliases, so links which already inherit the requested
-- blend stay links. No syntax, selection, title badge or statusline groups.
local surfaces = {
  'NormalFloat', 'FloatBorder', 'Pmenu', 'PmenuSbar',
  'CmpPmenu', 'CmpDoc', 'CmpBorder', 'CmpDocBorder',
  'BlinkCmpMenu', 'BlinkCmpMenuBorder', 'BlinkCmpDoc', 'BlinkCmpDocBorder',
  'BlinkCmpDocSeparator', 'BlinkCmpSignatureHelp', 'BlinkCmpSignatureHelpBorder',
  'WhichKeyNormal', 'WhichKeyBorder',
  'TelescopeNormal', 'TelescopeBorder', 'TelescopePromptNormal', 'TelescopePromptBorder',
  'TelescopeResultsNormal', 'TelescopeResultsBorder', 'TelescopePreviewNormal', 'TelescopePreviewBorder',
  'SnacksNormal', 'SnacksNormalNC', 'SnacksInputNormal', 'SnacksInputBorder',
  'SnacksPicker', 'SnacksPickerBorder', 'SnacksPickerBox', 'SnacksPickerBoxBorder',
  'SnacksPickerInput', 'SnacksPickerInputBorder', 'SnacksPickerList', 'SnacksPickerListBorder',
  'SnacksPickerPreview', 'SnacksPickerPreviewBorder',
  'SnacksNotifierMinimal', 'SnacksNotifierHistory',
  'NoicePopup', 'NoicePopupBorder', 'NoiceCmdlinePopup', 'NoiceCmdlinePopupBorder',
  'NoiceCmdlinePopupBorderSearch', 'NoiceConfirm', 'NoiceConfirmBorder', 'NoiceMini',
  'NoicePopupmenu', 'NoicePopupmenuBorder', 'NoiceSplit', 'NoiceSplitBorder',
  'LazyNormal', 'MasonNormal',
  'WinSeparator', 'NeoTreeWinSeparator',
  'AvanteSidebarNormal', 'AvanteSidebarWinSeparator', 'AvanteSidebarWinHorizontalSeparator',
  'AvantePromptInput', 'AvantePromptInputBorder', 'AvantePopupHint',
}
for _, level in ipairs({ 'Trace', 'Debug', 'Info', 'Warn', 'Error' }) do
  surfaces[#surfaces + 1] = 'SnacksNotifier' .. level
  surfaces[#surfaces + 1] = 'SnacksNotifierBorder' .. level
end
local rows = { 'CursorLine', 'NeoTreeNormal', 'NeoTreeNormalNC', 'NeoTreeCursorLine' }
local resolved_links = {}
local dashboard_terminal
local separator_chars = { vert = ' ', horiz = ' ', verthoriz = ' ', vertleft = ' ',
  vertright = ' ', horizup = ' ', horizdown = ' ' }

local function apply(name, blend)
  local id = vim.fn.hlID(name)
  -- The ID-based reader gets the global definition even under winhighlight.
  local attributes = id > 0 and vim.api.nvim_get_hl_by_id(id, true) or {}
  local current = attributes
  local target = id > 0 and vim.fn.synIDtrans(id) or id
  local saved = resolved_links[name]
  if target > 0 and target ~= id then
    saved = { target = target }
  elseif saved and vim.deep_equal(attributes, saved.applied) then
    -- A link to Normal needs its own blend; keep following the theme's RGB
    -- after resolving it, rather than freezing the first theme's foreground.
    attributes = vim.api.nvim_get_hl_by_id(saved.target, true)
  else
    saved = nil
  end
  if id > 0 and next(attributes) == nil then
    -- Neovim drops a blend-only definition. An explicitly empty panel group
    -- inherits Normal, so materialize that same RGB and keep following it.
    saved = { target = vim.fn.hlID('Normal') }
    attributes = vim.api.nvim_get_hl_by_id(saved.target, true)
  end
  -- Existing foreground-only separators and empty panel groups still need an
  -- explicit material blend: their inherited background otherwise stays opaque.
  -- Keep all RGB/style attributes intact and never create unloaded plugin groups.
  if id > 0 then
    attributes = vim.deepcopy(attributes)
    attributes.blend = blend
    if not vim.deep_equal(current, attributes) then
      vim.api.nvim_set_hl(0, name, attributes)
      if saved then saved.applied = vim.deepcopy(attributes) end
    end
  end
  resolved_links[name] = saved and saved.applied and saved or nil
end

local function split_separators()
  local tree = vim.fn.hlID('NeoTreeNormal')
  local background = tree > 0 and vim.api.nvim_get_hl_by_id(tree, true).background
  if background then
    for _, name in ipairs({ 'WinSeparator', 'NeoTreeWinSeparator', 'AvanteSidebarWinSeparator' }) do
      local id = vim.fn.hlID(name)
      if id > 0 then
        local attributes = vim.api.nvim_get_hl_by_id(id, true)
        local matched = vim.deepcopy(attributes)
        matched.foreground, matched.background, matched.blend = background, background, material_blend
        if not vim.deep_equal(attributes, matched) then vim.api.nvim_set_hl(0, name, matched) end
        resolved_links[name] = nil
      end
    end
  end
  if M.original_fillchars == nil then M.original_fillchars = vim.api.nvim_get_option_value('fillchars', { scope = 'global' }) end
  local function blank(values)
    for key in pairs(separator_chars) do if values[key] ~= ' ' then return false end end
    return true
  end
  if not blank(vim.opt_global.fillchars:get()) then vim.opt_global.fillchars:append(separator_chars) end
  -- Existing windows may override the global option. Change separator keys
  -- only, retaining their own eob, fold, lastline and other fill characters.
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative == '' then
      vim.api.nvim_win_call(win, function()
        if not blank(vim.opt_local.fillchars:get()) then vim.opt_local.fillchars:append(separator_chars) end
      end)
    end
  end
end

local function dashboard_material()
  -- Dashboard embeds its own terminal float, separate from SnacksNormal. Keep
  -- this narrow rule away from ordinary terminals and non-Glass Neovide.
  local name = 'SnacksDashboardTerminal'
  local definition = vim.api.nvim_get_hl(0, { name = name, create = false })
  if vim.g.neovide_liquid_glass == true then
    if vim.fn.hlexists(name) == 0 then return end
    if not dashboard_terminal or not vim.deep_equal(definition, dashboard_terminal.applied) then
      dashboard_terminal = { original = definition }
    end
    apply(name, material_blend)
    dashboard_terminal.applied = vim.api.nvim_get_hl(0, { name = name, create = false })
  elseif dashboard_terminal then
    if vim.deep_equal(definition, dashboard_terminal.applied) then
      -- Snacks defines default links; restoring one must replace our explicit
      -- definition rather than letting `default=true` skip the assignment.
      vim.api.nvim_set_hl(0, name, vim.tbl_extend('force', dashboard_terminal.original, { default = false }))
    end
    dashboard_terminal, resolved_links[name] = nil, nil
  end
end

function M.apply()
  if not vim.g.neovide then return end
  for _, name in ipairs(surfaces) do apply(name, material_blend) end
  for _, name in ipairs(rows) do apply(name, material_blend) end
  dashboard_material()
  split_separators()
end

local function schedule()
  if queued then return end
  queued = true
  -- Base46 reapplies plugin integrations in nested scheduled callbacks. Settle
  -- after those callbacks once per theme/plugin update, without a polling loop.
  vim.defer_fn(function() queued = false; M.apply() end, 30)
end

function M.setup()
  if configured or not vim.g.neovide then return end
  configured = true
  local group = vim.api.nvim_create_augroup('GlowBackgroundTransparency', { clear = true })
  vim.api.nvim_create_autocmd({ 'ColorScheme', 'VimEnter', 'WinNew', 'BufWinEnter' }, { group = group, callback = schedule })
  vim.api.nvim_create_autocmd('User', {
    group = group, pattern = { 'NvThemeReload', 'LazyLoad', 'VeryLazy' }, callback = schedule,
  })
  schedule()
end

return M
