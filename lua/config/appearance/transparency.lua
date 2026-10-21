-- Background-only transparency. Neovide keeps foreground text fully opaque.
local M = {}
local configured, queued, pending_full = false, false, false
local material_blend = 80 -- Windows light takes its denser platform policy at apply time.
-- Base surfaces precede aliases, so links which already inherit the requested
-- blend stay links. Syntax, selections and solid capsule bodies stay opaque.
local popup_surfaces = {
  "NormalFloat",
  "FloatBorder",
  "Pmenu",
  "PmenuSbar",
  "CmpPmenu",
  "CmpDoc",
  "CmpBorder",
  "CmpDocBorder",
  "BlinkCmpMenu",
  "BlinkCmpMenuBorder",
  "BlinkCmpDoc",
  "BlinkCmpDocBorder",
  "BlinkCmpDocSeparator",
  "BlinkCmpSignatureHelp",
  "BlinkCmpSignatureHelpBorder",
  "WhichKeyNormal",
  "WhichKeyBorder",
  "TelescopeNormal",
  "TelescopeBorder",
  "TelescopePromptNormal",
  "TelescopePromptBorder",
  "TelescopeResultsNormal",
  "TelescopeResultsBorder",
  "TelescopePreviewNormal",
  "TelescopePreviewBorder",
  "SnacksInputNormal",
  "SnacksInputBorder",
  "NoicePopup",
  "NoicePopupBorder",
  "NoiceCmdlinePopup",
  "NoiceCmdlinePopupBorder",
  "NoiceCmdlinePopupBorderSearch",
  "NoiceConfirm",
  "NoiceConfirmBorder",
  "NoiceMini",
  "NoicePopupmenu",
  "NoicePopupmenuBorder",
  "NoiceSplit",
  "NoiceSplitBorder",
  "LazyNormal",
  "MasonNormal",
}
-- 这些组由插件以 `default=true` 链接到公共高亮。底材物化后链接不再存在，
-- 因而每次都从其声明的源组重取前景，旧会话首次热加载也能恢复。
local popup_sources = {
  BlinkCmpMenu = "Pmenu",
  BlinkCmpMenuBorder = "Pmenu",
  BlinkCmpDoc = "NormalFloat",
  BlinkCmpDocBorder = "NormalFloat",
  BlinkCmpDocSeparator = "NormalFloat",
  BlinkCmpSignatureHelp = "NormalFloat",
  BlinkCmpSignatureHelpBorder = "NormalFloat",
  WhichKeyNormal = "NormalFloat",
  WhichKeyBorder = "FloatBorder",
  TelescopeResultsNormal = "TelescopeNormal",
  TelescopeResultsBorder = "TelescopeBorder",
  TelescopePreviewNormal = "TelescopeNormal",
  TelescopePreviewBorder = "TelescopeBorder",
  SnacksInputNormal = "Normal",
  SnacksInputBorder = "DiagnosticInfo",
  NoicePopup = "NormalFloat",
  NoicePopupBorder = "FloatBorder",
  NoiceCmdlinePopup = "Normal",
  NoiceCmdlinePopupBorder = "DiagnosticSignInfo",
  NoiceCmdlinePopupBorderSearch = "DiagnosticSignWarn",
  NoiceConfirm = "Normal",
  NoiceConfirmBorder = "DiagnosticSignInfo",
  NoiceMini = "MsgArea",
  NoicePopupmenu = "Pmenu",
  NoicePopupmenuBorder = "FloatBorder",
  NoiceSplit = "NormalFloat",
  NoiceSplitBorder = "FloatBorder",
  LazyNormal = "NormalFloat",
  MasonNormal = "NormalFloat",
}
local surfaces = {
  "SnacksNormal", "SnacksNormalNC",
  "NeoTreeWinSeparator",
  "AvanteSidebarNormal",
  "AvanteSidebarWinSeparator",
  "AvanteSidebarWinHorizontalSeparator",
  "AvantePromptInput",
  "AvantePromptInputBorder",
  "AvantePopupHint",
}
local notifier_surfaces = { SnacksNotifierMinimal = "NormalFloat", SnacksNotifierHistory = "Normal" }
for _, level in ipairs({ "Trace", "Debug", "Info", "Warn", "Error" }) do
  notifier_surfaces["SnacksNotifier" .. level] = "Normal"
  popup_surfaces[#popup_surfaces + 1] = "SnacksNotifierBorder" .. level
end
local picker_surfaces = {
  "SnacksPicker", "SnacksPickerBorder", "SnacksPickerBox", "SnacksPickerBoxBorder",
  "SnacksPickerInput", "SnacksPickerInputBorder", "SnacksPickerList", "SnacksPickerListBorder",
  "SnacksPickerPreview", "SnacksPickerPreviewBorder",
}
local rows = { "CursorLine", "NeoTreeNormal", "NeoTreeNormalNC", "NeoTreeCursorLine" }
-- 底栏与玻璃组件共用透明度；只处理底材和端帽外侧，胶囊内部保持实心。
local bottom_bar = {
  "St_EmptySpace",
  "St_EmptySpace2",
  "St_gitIcons",
  "St_lspError",
  "St_lspWarning",
  "St_LspHints",
  "St_LspInfo",
  "St_LspMsg",
  "St_Lsp",
  "St_file_sep",
  "St_Pos_sep",
  "St_cwd_sep",
  "St_lsp_sep",
  "St_sep_r",
}
local solid_capsules = {}
for _, mode in ipairs({
  "Normal",
  "Visual",
  "Insert",
  "Terminal",
  "NTerminal",
  "Replace",
  "Confirm",
  "Command",
  "Select",
}) do
  bottom_bar[#bottom_bar + 1] = "St_" .. mode .. "ModeSep"
  solid_capsules[#solid_capsules + 1] = "St_" .. mode .. "Mode"
  solid_capsules[#solid_capsules + 1] = "St_" .. mode .. "ModeText"
end
for _, name in ipairs({ "file", "Pos", "cwd", "lsp" }) do
  solid_capsules[#solid_capsules + 1] = "St_" .. name .. "_bg"
  solid_capsules[#solid_capsules + 1] = "St_" .. name .. "_txt"
end
local resolved_links = {}
local dashboard_terminal
local separator_chars =
  { vert = " ", horiz = " ", verthoriz = " ", vertleft = " ", vertright = " ", horizup = " ", horizdown = " " }

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
    saved = { target = vim.fn.hlID("Normal") }
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
      if saved then
        saved.applied = vim.deepcopy(attributes)
      end
    end
  end
  resolved_links[name] = saved and saved.applied and saved or nil
end

local function split_separators()
  if vim.g.neovide_liquid_glass == true then
    -- Ordinary split cells belong to the editor's base, not the tree panel.
    -- A zero blend keeps Neovide's Normal-opacity path (currently 78%).
    local base = vim.api.nvim_get_hl_by_id(vim.fn.hlID("Normal"), true)
    if base.background then
      local attributes = vim.api.nvim_get_hl_by_id(vim.fn.hlID("WinSeparator"), true)
      local matched = vim.deepcopy(attributes)
      matched.foreground, matched.background = base.background, base.background
      matched.blend = base.blend or 0
      if not vim.deep_equal(attributes, matched) then
        vim.api.nvim_set_hl(0, "WinSeparator", matched)
      end
      resolved_links.WinSeparator = nil
    end
  end
  local tree = vim.fn.hlID("NeoTreeNormal")
  local background = tree > 0 and vim.api.nvim_get_hl_by_id(tree, true).background
  if background then
    for _, name in ipairs({ "NeoTreeWinSeparator" }) do
      local id = vim.fn.hlID(name)
      if id > 0 then
        local attributes = vim.api.nvim_get_hl_by_id(id, true)
        local matched = vim.deepcopy(attributes)
        matched.foreground, matched.background, matched.blend = background, background, material_blend
        if not vim.deep_equal(attributes, matched) then
          vim.api.nvim_set_hl(0, name, matched)
        end
        resolved_links[name] = nil
      end
    end
  end
  if vim.g.neovide_liquid_glass == true then
    local panel = vim.api.nvim_get_hl(0, { name = "AvanteSidebarNormal", link = false, create = false })
    if panel.bg then
      -- All blank cells around Avante's stacked panels share its own material.
      -- Reversed title groups paint only the outer cap cell's background; their
      -- accent foreground still belongs to the solid capsule.
      for _, name in ipairs({
        "AvanteSidebarWinSeparator",
        "AvanteSidebarWinHorizontalSeparator",
        "AvanteReversedTitle",
        "AvanteReversedSubtitle",
        "AvanteReversedThirdTitle",
      }) do
        if vim.fn.hlexists(name) == 1 then
          local attrs = vim.api.nvim_get_hl(0, { name = name, link = false })
          attrs.bg, attrs.blend = panel.bg, panel.blend or material_blend
          if name:find("Separator", 1, true) then
            attrs.fg = panel.bg
          end
          if not vim.deep_equal(attrs, vim.api.nvim_get_hl(0, { name = name, link = false })) then
            vim.api.nvim_set_hl(0, name, attrs)
          end
          resolved_links[name] = nil
        end
      end
    end
  end
  if M.original_fillchars == nil then
    M.original_fillchars = vim.api.nvim_get_option_value("fillchars", { scope = "global" })
  end
  local function blank(values)
    for key in pairs(separator_chars) do
      if values[key] ~= " " then
        return false
      end
    end
    return true
  end
  if not blank(vim.opt_global.fillchars:get()) then
    vim.opt_global.fillchars:append(separator_chars)
  end
  -- Existing windows may override the global option. Change separator keys
  -- only, retaining their own eob, fold, lastline and other fill characters.
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative == "" then
      local buf = vim.api.nvim_win_get_buf(win)
      if
        vim.g.neovide_liquid_glass == true
        and vim.bo[buf].buftype == ""
        and not vim.bo[buf].filetype:match("^Avante")
      then
        -- A glass sidebar extends its surface through the adjacent blank
        -- separator. An opaque native PDF contributes no glass surface there,
        -- so that boundary remains part of the left editor's Normal base.
        local position = vim.api.nvim_win_get_position(win)
        local right = position[2] + vim.api.nvim_win_get_width(win) + 1
        local bottom = position[1] + vim.api.nvim_win_get_height(win)
        local avante_right = false
        for _, neighbour in ipairs(vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(win))) do
          local other = vim.api.nvim_win_get_position(neighbour)
          if
            vim.api.nvim_win_get_config(neighbour).relative == ""
            and other[2] == right
            and other[1] < bottom
            and other[1] + vim.api.nvim_win_get_height(neighbour) > position[1]
            and vim.bo[vim.api.nvim_win_get_buf(neighbour)].filetype:match("^Avante")
          then
            avante_right = true
            break
          end
        end
        local kept, remapped = {}, false
        for mapping in vim.wo[win].winhighlight:gmatch("[^,]+") do
          if mapping == "WinSeparator:AvanteSidebarWinSeparator" then
            remapped = true
          else
            kept[#kept + 1] = mapping
          end
        end
        if avante_right then
          kept[#kept + 1] = "WinSeparator:AvanteSidebarWinSeparator"
        end
        if remapped or avante_right then
          local value = table.concat(kept, ",")
          if value ~= vim.wo[win].winhighlight then
            vim.wo[win].winhighlight = value
          end
        end
      end
      vim.api.nvim_win_call(win, function()
        if not blank(vim.opt_local.fillchars:get()) then
          vim.opt_local.fillchars:append(separator_chars)
        end
      end)
    end
  end
end

local function dashboard_material()
  -- Dashboard's Matrix must use the editor material, not the sidebar blend.
  local name = "SnacksDashboardTerminal"
  local definition = vim.api.nvim_get_hl(0, { name = name, create = false })
  if vim.g.neovide then
    if vim.fn.hlexists(name) == 0 then
      return
    end
    if not dashboard_terminal or not vim.deep_equal(definition, dashboard_terminal.applied) then
      dashboard_terminal = { original = definition }
    end
    local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
    local policy = require("config.appearance.popup_materials").resolve("matrix_dashboard", normal, normal.bg)
    local attrs = vim.tbl_extend("force", normal, { blend = policy.blend })
    vim.api.nvim_set_hl(0, name, attrs)
    dashboard_terminal.applied = vim.api.nvim_get_hl(0, { name = name, create = false })
  elseif dashboard_terminal then
    if vim.deep_equal(definition, dashboard_terminal.applied) then
      -- Snacks defines default links; restoring one must replace our explicit
      -- definition rather than letting `default=true` skip the assignment.
      vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", dashboard_terminal.original, { default = false }))
    end
    dashboard_terminal, resolved_links[name] = nil, nil
  end
end

local function neo_tree_selection_blend()
  local base46 = package.loaded.base46
  local polish = base46 and base46.get_theme_tb("polish_hl")
  local tree = polish and polish["neo-tree"]
  local selection = tree and tree.NeoTreeCursorLine
  return selection and selection.blend or material_blend
end

function M.apply_popup_material()
  if not vim.g.neovide then return end
  local background = require("config.appearance.popups").background()
  local normal = vim.api.nvim_get_hl_by_id(vim.fn.hlID("Normal"), true)
  local base46, overrides = package.loaded.base46, {}
  if base46 then
    for _, groups in pairs(base46.get_theme_tb("polish_hl") or {}) do
      for name, attrs in pairs(groups) do overrides[name] = attrs end
    end
    local config = package.loaded.nvconfig
    for name, attrs in pairs(config and config.base46.hl_override or {}) do
      overrides[name] = vim.tbl_extend("force", overrides[name] or {}, attrs)
    end
    if base46.turn_str_to_color then overrides = base46.turn_str_to_color(overrides) end
  end
  for _, name in ipairs(popup_surfaces) do
    if vim.fn.hlexists(name) == 1 then
      local attrs = vim.api.nvim_get_hl_by_id(vim.fn.hlID(name), true)
      local override = overrides[name] or {}
      local source = override.link or popup_sources[name]
      if source then
        local source_attrs = vim.api.nvim_get_hl_by_id(vim.fn.hlID(source), true)
        attrs.foreground = source_attrs.foreground or normal.foreground
      end
      -- 显式主题／用户前景覆盖仍优先；不把插件正文误当作代码 Comment 调色。
      if override.fg then
        attrs.foreground = type(override.fg) == "string" and tonumber(override.fg:gsub("^#", ""), 16) or override.fg
      end
      attrs.background, attrs.blend = background, 0
      attrs.foreground = attrs.foreground or normal.foreground
      vim.api.nvim_set_hl(0, name, attrs)
    end
  end
end

function M.apply_notifier_material()
  if not vim.g.neovide then return end
  local normal = vim.api.nvim_get_hl_by_id(vim.fn.hlID("Normal"), true)
  local background = require("config.appearance.popups").background()
  -- 这些正文原本链接 Normal / NormalFloat；每次读取源颜色，避免模块重载后旧配色滞留。
  for name, source in pairs(notifier_surfaces) do
    if vim.fn.hlexists(name) == 1 then
      local attrs = vim.api.nvim_get_hl_by_id(vim.fn.hlID(source), true)
      attrs.foreground = attrs.foreground or normal.foreground
      attrs.background = background
      attrs.blend = 0
      vim.api.nvim_set_hl(0, name, attrs)
    end
  end
end

function M.apply_picker_material()
  if not vim.g.neovide then return end
  -- 所有工具浮窗共用主题已有的弹窗底色；与主编辑区分离，保证本体完全不透明。
  local normal = vim.api.nvim_get_hl_by_id(vim.fn.hlID("Normal"), true)
  if not normal.background then return end
  normal.background = require("config.appearance.popups").background()
  normal.blend = 0
  -- 提前定义基础组，首次打开也不闪现玻璃；标题、选中行、匹配文字保留各自的高亮。
  for _, name in ipairs(picker_surfaces) do
    vim.api.nvim_set_hl(0, name, normal)
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.wo[win].winhighlight:find(":SnacksPicker", 1, true) and vim.wo[win].winblend ~= 0 then
      vim.wo[win].winblend = 0
    end
  end
end

function M.apply()
  if not vim.g.neovide then
    require("config.appearance.popup_text").apply()
    return
  end
  local windows = require("config.platform.windows_appearance")
  windows.setup()
  material_blend = windows.material_blend(80)
  for _, name in ipairs(surfaces) do
    apply(name, material_blend)
  end
  M.apply_popup_material()
  M.apply_notifier_material()
  M.apply_picker_material()
  local windows_gui = vim.fn.has("win32") == 1
  if vim.g.neovide_liquid_glass == true or windows_gui then
    if windows_gui then
      -- Windows has no native Liquid Glass flag. Only the bar's outside cells
      -- follow Normal's existing RGB, so Neovide uses the editor's own opacity.
      -- Do not alter shared StatusLineNC/TabLine aliases or capsule accents.
      local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
      if normal.bg then
        for _, name in ipairs(bottom_bar) do
          if vim.fn.hlexists(name) == 1 then
            local attrs = vim.api.nvim_get_hl(0, { name = name, link = false })
            attrs.bg, attrs.blend = normal.bg, 0
            vim.api.nvim_set_hl(0, name, attrs)
            resolved_links[name] = nil
          end
        end
      end
    else
      for _, name in ipairs(bottom_bar) do
        apply(name, material_blend)
      end
    end
    -- StatusLine 的 blend 会参与组合高亮；胶囊内部必须显式覆盖为 0，不能只省略。
    for _, name in ipairs(solid_capsules) do
      if vim.fn.hlexists(name) == 1 then
        local attrs = vim.api.nvim_get_hl(0, { name = name, link = false })
        if next(attrs) then
          attrs.blend = 0
          vim.api.nvim_set_hl(0, name, attrs)
        end
      end
    end
    -- Windows leaves fractional bottom pixels on the same editor-opacity path.
    -- Keep the existing macOS Liquid Glass footer policy independent.
    if not windows_gui then
      vim.g.neovide_bottom_margin_opacity = (100 - material_blend) / 100
    end
  end
  for _, name in ipairs(rows) do
    -- 光标行独立调节，后续材质刷新也不能把用户设置覆盖回统一面板透明度。
    local cursorline = require("config.appearance.editor_highlights").config.cursorline
    -- NONE 明确取消行底色，不能再把空高亮物化成带透明度的 Normal 背景。
    if name ~= "CursorLine" or (cursorline.style.bg ~= "NONE" and cursorline.style.bg ~= "none") then
      local blend = name == "CursorLine" and cursorline.neovide_blend or material_blend
      if name == "NeoTreeCursorLine" then
        blend = neo_tree_selection_blend() -- 与主题中同一行的 bg / blend 一起调，不被面板材质覆盖。
      end
      apply(name, blend)
    end
  end
  dashboard_material()
  split_separators()
  require("config.appearance.popup_text").apply()
  require("config.appearance.popups").apply()
end

-- Opening/focusing a window changes its local material, not the theme palette.
-- Provider first-show hooks keep their synchronous path; later window events
-- only settle namespaces/separators, never rebuild every global surface group.
function M.apply_windows()
  if not vim.g.neovide then return end
  split_separators()
  require("config.appearance.popups").apply()
end

local function schedule(event)
  local window_event = event and (event.event == "WinNew" or event.event == "BufWinEnter" or event.event == "OptionSet")
  pending_full = pending_full or not window_event
  if queued then return end
  queued = true
  vim.defer_fn(function()
    local full = pending_full
    pending_full = false
    -- Keep the guard during our own winhighlight repairs to avoid feedback.
    local ok, err = pcall(full and M.apply or M.apply_windows)
    queued = false
    if not ok then error(err) end
    -- Preserve a real theme/plugin update that arrived during this refresh.
    if pending_full then schedule() end
  end, 30)
end

function M.setup()
  if configured or not vim.g.neovide then
    return
  end
  configured = true
  local group = vim.api.nvim_create_augroup("GlowBackgroundTransparency", { clear = true })
  vim.api.nvim_create_autocmd(
    { "ColorScheme", "VimEnter", "WinNew", "BufWinEnter" },
    { group = group, callback = schedule }
  )
  vim.api.nvim_create_autocmd("OptionSet", { group = group, pattern = "winhighlight", callback = schedule })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "NvThemeReload", "LazyLoad", "VeryLazy" },
    callback = schedule,
  })
  schedule()
end

return M
