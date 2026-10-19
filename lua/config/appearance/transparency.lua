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
  'NeoTreeWinSeparator',
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
  if vim.g.neovide_liquid_glass == true then
    -- Ordinary split cells belong to the editor's base, not the tree panel.
    -- A zero blend keeps Neovide's Normal-opacity path (currently 78%).
    local base = vim.api.nvim_get_hl_by_id(vim.fn.hlID('Normal'), true)
    if base.background then
      local attributes = vim.api.nvim_get_hl_by_id(vim.fn.hlID('WinSeparator'), true)
      local matched = vim.deepcopy(attributes)
      matched.foreground, matched.background = base.background, base.background
      matched.blend = base.blend or 0
      if not vim.deep_equal(attributes, matched) then vim.api.nvim_set_hl(0, 'WinSeparator', matched) end
      resolved_links.WinSeparator = nil
    end
  end
  local tree = vim.fn.hlID('NeoTreeNormal')
  local background = tree > 0 and vim.api.nvim_get_hl_by_id(tree, true).background
  if background then
    for _, name in ipairs({ 'NeoTreeWinSeparator' }) do
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
  if vim.g.neovide_liquid_glass == true then
    local panel = vim.api.nvim_get_hl(0, { name = 'AvanteSidebarNormal', link = false, create = false })
    if panel.bg then
      -- All blank cells around Avante's stacked panels share its own material.
      -- Reversed title groups paint only the outer cap cell's background; their
      -- accent foreground still belongs to the solid capsule.
      for _, name in ipairs({ 'AvanteSidebarWinSeparator', 'AvanteSidebarWinHorizontalSeparator',
        'AvanteReversedTitle', 'AvanteReversedSubtitle', 'AvanteReversedThirdTitle' }) do
        if vim.fn.hlexists(name) == 1 then
          local attrs = vim.api.nvim_get_hl(0, { name = name, link = false })
          attrs.bg, attrs.blend = panel.bg, panel.blend or material_blend
          if name:find('Separator', 1, true) then attrs.fg = panel.bg end
          if not vim.deep_equal(attrs, vim.api.nvim_get_hl(0, { name = name, link = false })) then
            vim.api.nvim_set_hl(0, name, attrs)
          end
          resolved_links[name] = nil
        end
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
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.g.neovide_liquid_glass == true and vim.bo[buf].buftype == ''
        and not vim.bo[buf].filetype:match('^Avante') then
        -- A glass sidebar extends its surface through the adjacent blank
        -- separator. An opaque native PDF contributes no glass surface there,
        -- so that boundary remains part of the left editor's Normal base.
        local position = vim.api.nvim_win_get_position(win)
        local right = position[2] + vim.api.nvim_win_get_width(win) + 1
        local bottom = position[1] + vim.api.nvim_win_get_height(win)
        local avante_right = false
        for _, neighbour in ipairs(vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(win))) do
          local other = vim.api.nvim_win_get_position(neighbour)
          if vim.api.nvim_win_get_config(neighbour).relative == '' and other[2] == right
            and other[1] < bottom and other[1] + vim.api.nvim_win_get_height(neighbour) > position[1]
            and vim.bo[vim.api.nvim_win_get_buf(neighbour)].filetype:match('^Avante') then
            avante_right = true; break
          end
        end
        local kept, remapped = {}, false
        for mapping in vim.wo[win].winhighlight:gmatch('[^,]+') do
          if mapping == 'WinSeparator:AvanteSidebarWinSeparator' then remapped = true
          else kept[#kept + 1] = mapping end
        end
        if avante_right then kept[#kept + 1] = 'WinSeparator:AvanteSidebarWinSeparator' end
        if remapped or avante_right then
          local value = table.concat(kept, ',')
          if value ~= vim.wo[win].winhighlight then vim.wo[win].winhighlight = value end
        end
      end
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
  for _, name in ipairs(rows) do
    -- 光标行独立调节，后续材质刷新也不能把用户设置覆盖回统一面板透明度。
    local cursorline = require('config.appearance.editor_highlights').config.cursorline
    -- NONE 明确取消行底色，不能再把空高亮物化成带透明度的 Normal 背景。
    if name ~= 'CursorLine' or (cursorline.style.bg ~= 'NONE' and cursorline.style.bg ~= 'none') then
      apply(name, name == 'CursorLine' and cursorline.neovide_blend or material_blend)
    end
  end
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
  vim.api.nvim_create_autocmd('OptionSet', { group = group, pattern = 'winhighlight', callback = schedule })
  vim.api.nvim_create_autocmd('User', {
    group = group, pattern = { 'NvThemeReload', 'LazyLoad', 'VeryLazy' }, callback = schedule,
  })
  schedule()
end

return M
