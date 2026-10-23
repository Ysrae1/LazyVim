-- 浮窗底材最终覆盖层；可手调设置集中在 popup_materials.lua。
local M = {}
local bases = { "Normal", "NormalNC", "NormalFloat", "FloatBorder", "FloatTitle", "FloatFooter" }

local function read(namespace)
  return vim.api.nvim_get_hl(namespace, {})
end

local function resolver(global, private)
  local function resolve(name, seen)
    seen = seen or {}
    if seen[name] then return {} end
    seen[name] = true
    local value = private and private[name]
    if not value or next(value) == nil then value = global[name] or {} end
    if value.link then return resolve(value.link, seen) end
    return value
  end
  return resolve
end

local function background(normal, global)
  local ok, colors = pcall(function() return require("base46").get_theme_tb("base_30") end)
  if ok and type(colors) == "table" then
    -- Neovide 对与 Normal 相同的 RGB 另用窗口透明度；选用主题已有色槽避免落入该路径。
    for _, key in ipairs({ "darker_black", "one_bg", "black2", "one_bg2", "one_bg3" }) do
      local value = colors[key]
      local color = type(value) == "string" and tonumber(value:gsub("^#", ""), 16) or value
      if type(color) == "number" and color ~= normal then return color end
    end
  end
  local fallback = resolver(global)("NormalFloat").bg
  return fallback and fallback ~= normal and fallback or normal
end

function M.background()
  -- This lookup is also used once per notifier surface. Reading every global
  -- highlight here repeatedly copies the entire syntax table on Windows.
  -- Only these two resolved global colors contribute to the existing policy.
  local global = {}
  for _, name in ipairs({ "Normal", "NormalFloat" }) do
    global[name] = vim.api.nvim_get_hl(0, { name = name, link = false, create = false })
  end
  return background(global.Normal.bg, global)
end

local function mappings(value)
  local result = {}
  for item in value:gmatch("[^,]+") do
    local source, target = item:match("^([^:]+):(.+)$")
    if source then result[source] = target end
  end
  return result
end

local function serialize(mapping)
  local parts = {}
  for source, target in pairs(mapping) do parts[#parts + 1] = source .. ":" .. target end
  table.sort(parts)
  return table.concat(parts, ",")
end

local function is_backdrop(filetype, mapping)
  if filetype == "lazy_backdrop" or filetype == "mason_backdrop" or filetype == "snacks_win_backdrop" then return true end
  for _, target in pairs(mapping) do
    if target:lower():find("backdrop", 1, true) then return true end
  end
  return false
end

local function is_dashboard(filetype, mapping)
  if filetype:match("^snacks_dashboard") then return true end
  for _, target in pairs(mapping) do
    if target:find("SnacksDashboardTerminal", 1, true) then return true end
  end
  return false
end

local function chrome(name)
  -- laststatus=3 的全局底栏也借用当前浮窗 namespace，不能把这些组变成实心。
  return name:match("^St_") or name:match("^StatusLine") or name:match("^WinBar")
    or name:match("^TabLine") or name:match("^Tb") or name:match("^BufferLine")
end

local avante_material_groups = {
  "AvanteSidebarWinSeparator", "AvanteSidebarWinHorizontalSeparator",
  "AvanteReversedTitle", "AvanteReversedSubtitle", "AvanteReversedThirdTitle",
}
local function avante_material(profiles, normal, popup, global)
  local policy = profiles.resolve("avante", normal, popup)
  -- Shared separator cells can be drawn by the neighbouring editor. Only
  -- Avante-owned groups are global; all sidebar content uses its own namespace.
  for _, name in ipairs(avante_material_groups) do
    if vim.fn.hlexists(name) == 1 then
      local attrs = vim.api.nvim_get_hl(0, { name = name, link = false })
      attrs.bg, attrs.blend = policy.bg, policy.blend
      if name:find("Separator", 1, true) then attrs.fg = policy.bg end
      vim.api.nvim_set_hl(0, name, attrs)
      global[name] = attrs
    end
  end
end

local function material(value, normal, popup, policy, base)
  value = vim.deepcopy(value)
  if base then
    -- 反色基础组先还原其实际前景，避免换底材后又被反色交换回来。
    if value.reverse then value.fg, value.reverse = value.bg or normal.bg, nil end
    value.fg, value.bg, value.blend = value.fg or normal.fg, policy.bg, policy.blend
  elseif value.bg and (value.bg == normal.bg or value.bg == popup) then
    value.bg, value.blend = policy.bg, policy.blend
  elseif value.blend and value.blend > 0 then
    -- 选中块等独立语义背景仍保持清晰，不把整幅文字与背景一起混合。
    value.blend = 0
  end
  return value
end

local picker_caption_tokens = {
  GlowPickerPromptTitle = true, GlowPickerPreviewTitle = true, GlowPickerResultsTitle = true,
  TelescopePromptTitle = true, TelescopePreviewTitle = true, TelescopeResultsTitle = true,
}
local notebook_caption_tokens = {
  GlowNotebookExpand = true, GlowNotebookExpandCap = true,
  GlowNotebookExpandValue = true, GlowNotebookExpandValueCap = true,
}

-- Generic captions inherit the float material; semantic picker title capsules
-- retain their theme-owned RGB and stay opaque. Derive chunk-only groups so
-- neither decision changes selections/diagnostics in the buffer body.
local function captions(config, state)
  local sources, changes = {}, {}
  for _, field in ipairs({ "title", "footer" }) do
    if type(config[field]) == "table" then
      local chunks, changed = vim.deepcopy(config[field]), false
      for _, chunk in ipairs(chunks) do
        local groups = chunk[2]
        groups = type(groups) == "table" and groups or { groups or (field == "title" and "FloatTitle" or "FloatFooter") }
        local original = {}
        for _, group in ipairs(groups) do
          local name = type(group) == "number" and vim.api.nvim_get_hl_name_by_id(group) or group
          local saved = state.caption_sources and state.caption_sources[name]
          if saved then vim.list_extend(original, saved) else original[#original + 1] = name end
        end
        local derived = "GlowPopupCaption_" .. vim.fn.sha256(table.concat(original, ":")):sub(1, 20)
        sources[derived] = original
        if #groups ~= 1 or groups[1] ~= vim.fn.hlID(derived) and groups[1] ~= derived then
          chunk[2], changed = derived, true
        end
      end
      if changed then
        changes[field], changes[field .. "_pos"] = chunks, config[field .. "_pos"]
      end
    end
  end
  local signature = vim.tbl_keys(sources)
  table.sort(signature)
  return sources, changes, table.concat(signature, ":")
end

local function source_namespace(win, mapping, state)
  local namespace = vim.api.nvim_get_hl_ns({ winid = win })
  if namespace == state.namespace then return state.source_namespace or 0 end
  if namespace <= 0 then return 0 end
  -- winhighlight 自身生成内部 namespace；它随映射变化，不能当作插件源缓存。
  for name, value in pairs(read(namespace)) do
    if next(value) ~= nil and (not value.link or value.link ~= mapping[name]) then return namespace end
  end
  return 0
end

-- Called only inside Nui's own border lifecycle. The border has its own
-- buffer; source highlights here cannot affect syntax/selection in the body.
function M.prepare_nui_border(border)
  if not vim.g.neovide or not border.winid or not vim.api.nvim_win_is_valid(border.winid) then return end
  local groups = {}
  for _, line in ipairs(border._.lines or {}) do
    for _, chunk in ipairs(line._texts or { line }) do
      local group = chunk.extmark and chunk.extmark.hl_group
      if type(group) == "string" then groups[group] = true end
    end
  end
  vim.w[border.winid].glow_popup_caption_groups = vim.tbl_keys(groups)
  M.apply({ border.winid })
end

local function nui_hooks()
  local border, popup = package.loaded["nui.popup.border"], package.loaded["nui.popup"]
  if not border then return end
  local utils = require("nui.utils")._
  local hooks = utils._glow_popup_material_hooks
  if not hooks then
    hooks = { originals = {} }
    utils._glow_popup_material_hooks = hooks
    -- These are provider utilities, not Neovim APIs. They run after the real
    -- options/text exist and before Nui's internal redraw, under an exact
    -- active-border/window guard. Ordinary Nui utility calls are unchanged.
    local option, options, lines = utils.set_win_option, utils.set_win_options, utils.render_lines
    utils.set_win_option = function(win, ...)
      local result = vim.F.pack_len(option(win, ...))
      local active = hooks.border
      if active and active.winid == win then require("config.appearance.popups").prepare_nui_border(active) end
      return vim.F.unpack_len(result)
    end
    utils.set_win_options = function(win, ...)
      local result = vim.F.pack_len(options(win, ...))
      if hooks.popup and hooks.popup.winid == win and vim.g.neovide then
        require("config.appearance.popups").apply({ win })
      end
      return vim.F.unpack_len(result)
    end
    utils.render_lines = function(text, buf, ...)
      local result = vim.F.pack_len(lines(text, buf, ...))
      local active = hooks.border
      if active and active.bufnr == buf then require("config.appearance.popups").prepare_nui_border(active) end
      return vim.F.unpack_len(result)
    end
  end
  local function wrap(provider, method, kind)
    if not provider then return end
    local key = kind .. ":" .. method
    if hooks.originals[key] then return end
    local original = provider[method]
    -- Migrate only the previous Glow-marked closure. Do not layer a second
    -- after-show hook or unwrap another plugin's methods during hot updates.
    if kind == "border" and provider["_glow_material_" .. method] == original then
      local previous
      for index = 1, 20 do
        local name, value = debug.getupvalue(original, index)
        if not name then break end
        if name == "original" and type(value) == "function" then previous = value; break end
      end
      assert(previous, "Unable to migrate the previous Glow Nui material hook")
      original = previous
    end
    hooks.originals[key] = original
    provider[method] = function(self, ...)
      if not vim.g.neovide then return original(self, ...) end
      local previous, mapping = hooks[kind], self._.winhighlight
      hooks[kind] = self
      -- Ensure a material boundary even when Nui has no explicit winhighlight.
      local supplied = kind == "border" and method == "_open_window" and mapping == nil
      if supplied then self._.winhighlight = "" end
      local result = vim.F.pack_len(pcall(original, self, ...))
      if supplied and self._.winhighlight == "" then self._.winhighlight = nil end
      hooks[kind] = previous
      if not result[1] then error(result[2], 0) end
      if kind == "border" then require("config.appearance.popups").prepare_nui_border(self) end
      return unpack(result, 2, result.n)
    end
    provider["_glow_material_" .. method] = provider[method]
  end
  for _, method in ipairs({ "_open_window", "_relayout", "set_text" }) do wrap(border, method, "border") end
  wrap(popup, "_open_window", "popup")
end

local function provider_hooks()
  local function after_show(provider, method, marker)
    if not provider or type(provider[method]) ~= "function" or provider[marker] == provider[method] then return end
    local original = provider[method]
    provider[method] = function(...)
      local result = vim.F.pack_len(original(...))
      -- WhichKey 屏蔽窗口事件；Noice 重画时也可能重设边框映射。
      -- 显示结束后同步刷新两层，不加轮询；reload 后动态读取新版处理函数。
      require("config.appearance.popups").apply()
      vim.api.nvim_exec_autocmds("User", { pattern = "NeovideFloatChanged", modeline = false })
      return vim.F.unpack_len(result)
    end
    provider[marker] = provider[method]
  end
  after_show(package.loaded["which-key.view"], "show", "_glow_material_show")
  after_show(package.loaded["noice.view.nui"], "show", "_glow_material_show")

  nui_hooks()

  -- Snacks 2.30 的 list.on_show() 会直接 flush，show() 返回后再覆盖已经太晚。
  -- 仅在已加载的 provider 内，借其 on_win 边界：此时 wo 已设置，列表尚未首绘。
  local snacks = package.loaded["snacks.win"]
  if not snacks and package.loaded.snacks then snacks = require("snacks.win") end
  if snacks and snacks._glow_material_show ~= snacks.show then
    local original = snacks.show
    snacks.show = function(self, ...)
      local mapping = self.opts.wo and self.opts.wo.winhighlight or ""
      local picker = type(mapping) == "string" and mapping:find(":SnacksPicker", 1, true)
      if type(mapping) == "table" then
        for _, target in pairs(mapping) do
          picker = picker or type(target) == "string" and target:match("^SnacksPicker")
        end
      end
      if not vim.g.neovide or not picker then return original(self, ...) end
      local updating = self:valid()
      local on_win = self.opts.on_win
      self.opts.on_win = function(win, ...)
        -- 单窗处理避免关闭 provider 仍在构造的其它窗口（例如 backdrop）。
        require("config.appearance.popups").apply({ win.win })
        if on_win then return on_win(win, ...) end
      end
      local result = vim.F.pack_len(pcall(original, self, ...))
      self.opts.on_win = on_win
      if not result[1] then error(result[2], 0) end
      -- 已存在的窗口走 update()，不会再调用 on_win。
      if updating and self:valid() then require("config.appearance.popups").apply({ self.win }) end
      vim.api.nvim_exec_autocmds("User", { pattern = "NeovideFloatChanged", modeline = false })
      return unpack(result, 2, result.n)
    end
    snacks._glow_material_show = snacks.show
  end
  -- Scratch/input/notification windows use the same on_win boundary as picker.
  -- Keep a separate guard so an already-running picker hook can be upgraded
  -- without wrapping it again or requiring the user's editor to restart.
  if snacks and snacks._glow_material_float_show ~= snacks.show then
    local original = snacks.show
    snacks.show = function(self, ...)
      local mapping = self.opts.wo and self.opts.wo.winhighlight or ""
      local picker = type(mapping) == "string" and mapping:find(":SnacksPicker", 1, true)
      if type(mapping) == "table" then
        for _, target in pairs(mapping) do picker = picker or type(target) == "string" and target:match("^SnacksPicker") end
      end
      if not vim.g.neovide or picker or self.opts.position ~= "float"
        or self.opts.bo and self.opts.bo.filetype == "snacks_win_backdrop" then return original(self, ...) end
      local updating, on_win = self:valid(), self.opts.on_win
      self.opts.on_win = function(win, ...)
        require("config.appearance.popups").apply({ win.win })
        if on_win then return on_win(win, ...) end
      end
      local result = vim.F.pack_len(pcall(original, self, ...))
      self.opts.on_win = on_win
      if not result[1] then error(result[2], 0) end
      if updating and self:valid() then require("config.appearance.popups").apply({ self.win }) end
      return unpack(result, 2, result.n)
    end
    snacks._glow_material_float_show = snacks.show
    snacks._glow_material_show = snacks.show
  end
  -- Providers also replace captions after show (input prompt, picker counters,
  -- resize). Reapply at those provider methods, before their next redraw.
  for _, method in ipairs({ "set_title", "update" }) do
    local marker = "_glow_material_" .. method
    if snacks and snacks[marker] ~= snacks[method] then
      local original = snacks[method]
      snacks[method] = function(self, ...)
        local title, position = self.opts.title, self.opts.title_pos
        local result = vim.F.pack_len(original(self, ...))
        if method == "set_title" and vim.deep_equal(title, self.opts.title) and position == self.opts.title_pos then
          return vim.F.unpack_len(result)
        end
        if vim.g.neovide and self:valid() and self.opts.position == "float"
          and not (self.opts.bo and self.opts.bo.filetype == "snacks_win_backdrop") then
          require("config.appearance.popups").apply({ self.win })
        end
        return vim.F.unpack_len(result)
      end
      snacks[marker] = snacks[method]
    end
  end
end

-- LazyLoad 后立即装 provider 钩子，不等待主题稳定用的 30ms 延时。
-- 不提前加载 Snacks，也不覆盖 nvim_open_win/redraw 等全局 API。
if vim.g.neovide then
  vim.api.nvim_create_autocmd("User", {
    group = vim.api.nvim_create_augroup("GlowPopupProviderHooks", { clear = true }),
    pattern = "LazyLoad",
    callback = provider_hooks,
  })
end

function M.apply(windows)
  if not vim.g.neovide then return end
  provider_hooks()
  vim.o.pumblend = 0
  -- 每轮仅扫描一次全局高亮，只保留会透出背景的稀疏覆盖；不按窗口复制全部语法组。
  local global = read(0)
  local resolve_global = resolver(global)
  local normal = resolve_global("Normal")
  local popup = background(normal.bg, global)
  if not popup then return end
  local profiles = require("config.appearance.popup_materials")
  avante_material(profiles, normal, popup, global)
  -- 内建 Pmenu 不在 nvim_list_wins 中；它的基础底材组使用同一个菜单配置。
  -- pumblend=0 保持前景原样，背景混合交给高亮 blend / Neovide。
  local completion = profiles.resolve("completion_menu", normal, popup)
  for _, name in ipairs({ "Pmenu", "PmenuSbar" }) do
    if global[name] then
      local attrs = material(resolve_global(name), normal, popup, completion, true)
      vim.api.nvim_set_hl(0, name, attrs)
      global[name] = attrs
    end
  end
  local sparse_cache, applied = {}, {}

  for _, win in ipairs(windows or vim.api.nvim_list_wins()) do
    local config = vim.api.nvim_win_get_config(win)
    local mapping = mappings(vim.wo[win].winhighlight)
    if config.relative ~= "" or config.external or profiles.is_avante(win, mapping) then
      local filetype = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
      if is_backdrop(filetype, mapping) then
        -- 仅关闭明确标记的遮罩，不按尺寸、层级或是否可聚焦猜测工具窗口。
        pcall(vim.api.nvim_win_close, win, true)
      elseif not is_dashboard(filetype, mapping) or profiles.classify(win, mapping) == "matrix_dashboard" then
        local state = vim.w[win].glow_popup_material or {}
        local source = source_namespace(win, mapping, state)
        -- 迁移早期版本的派生映射；后续只保留原始映射，不再生成全局前缀组。
        for name, target in pairs(mapping) do
          if state.targets and target == state.targets[name] then
            mapping[name] = state.sources[name]
          elseif target:sub(1, 10) == "GlowPopup_" then
            mapping[name] = target:sub(11)
          end
        end
        local original = serialize(mapping)
        if vim.wo[win].winhighlight ~= original then vim.wo[win].winhighlight = original end
        local profile = profiles.classify(win, mapping)
        local policy = profiles.resolve(profile, normal, popup)
        -- 前端用 Src 合成浮窗的绝对背景 alpha；每个子窗保留自己的材质。
        -- blend=100 会清空父背景，不能把它当作“只画文字”的继承方式。
        local material_key = policy.mode .. ":" .. policy.bg .. ":" .. policy.blend
        if not sparse_cache[material_key] then
          local sparse = {}
          for name in pairs(global) do
            local value = resolve_global(name)
            if chrome(name) then
              -- 显式保留原始 chrome 样式，链接也不能通过局部 Normal 换底色。
              sparse[name] = vim.deepcopy(value)
            elseif value.bg and (value.bg == normal.bg or value.bg == popup) or value.blend and value.blend > 0 then
              sparse[name] = material(value, normal, popup, policy)
            end
          end
          sparse_cache[material_key] = sparse
        end
        local sparse = sparse_cache[material_key]
        local text_overrides = require("config.appearance.popup_text").window_overrides(filetype, mapping)
        -- 同样的 NormalFloat 映射也可能同时用于通知和代码预览，不能共享局部弱色覆盖。
        local text_policy = next(text_overrides) and ":notification" or ""
        local caption_sources, caption_changes, caption_signature = captions(config, state)
        for _, name in ipairs(vim.w[win].glow_popup_caption_groups or {}) do
          caption_sources[name] = { name }
        end
        local caption_keys = vim.tbl_keys(caption_sources)
        table.sort(caption_keys)
        caption_signature = table.concat(caption_keys, ":")
        local namespace = vim.api.nvim_create_namespace("GlowPopupMaterial:" .. vim.fn.sha256(source .. ":" .. original .. text_policy .. ":" .. profile .. ":" .. caption_signature))
        if not applied[namespace] then
          applied[namespace] = true
          local private = source > 0 and read(source) or {}
          local resolve = resolver(global, private)
          local source_normal = private.Normal and next(private.Normal) and resolve("Normal") or resolve(mapping.Normal or "Normal")
          local values = vim.deepcopy(sparse)
          -- 插件自己的语义前景、背景与样式优先；只取消其背景透明度。
          for name, value in pairs(private) do
            if not chrome(name) then
              values[name] = (value.link and not sparse[name]) and value or material(resolve(name), source_normal, popup, policy)
            end
          end
          -- Namespace 优先于 winhighlight，因此将全部原映射复现到该 namespace。
          for name, target in pairs(mapping) do
            if not chrome(name) and (not private[name] or next(private[name]) == nil) then
              values[name] = material(resolve(target), source_normal, popup, policy)
            end
          end
          for _, name in ipairs(bases) do
            local value
            if private[name] and next(private[name]) then
              value = resolve(name)
            elseif mapping[name] then
              value = resolve(mapping[name])
            elseif name == "Normal" or ((name == "NormalNC" or name == "NormalFloat") and (mapping.Normal or private.Normal)) then
              value = source_normal
            else
              value = resolve(name)
            end
            values[name] = material(value, source_normal, popup, policy, true)
          end
          if profile == "avante" then
            -- These custom-colored cap exteriors are material, not semantic
            -- selections; retain their explicit blend even in custom mode.
            for _, name in ipairs(avante_material_groups) do
              if global[name] then
                values[name] = vim.deepcopy(global[name])
                for mapped, target in pairs(mapping) do
                  if target == name then values[mapped] = vim.deepcopy(global[name]) end
                end
              end
            end
          end
          for name, groups in pairs(caption_sources) do
            local value, semantic, notebook = {}, false, false
            for _, group in ipairs(groups) do
              value = vim.tbl_extend("force", value, resolve(mapping[group] or group))
              semantic = semantic or picker_caption_tokens[group] or picker_caption_tokens[mapping[group]]
              notebook = notebook or notebook_caption_tokens[group] or notebook_caption_tokens[mapping[group]]
            end
            if notebook then
              -- Notebook footer caps keep their transparent outside, while
              -- their themed label/value backgrounds remain solid.
              value.blend = value.bg ~= nil and 0 or nil
              values[name] = value
            elseif semantic and value.bg ~= nil then
              value.blend = 0
              values[name] = value
            else
              values[name] = material(value, source_normal, popup, policy, true)
            end
          end
          for name, attrs in pairs(text_overrides) do
            values[name] = vim.tbl_extend("force", vim.deepcopy(resolve(name)), attrs)
          end
          -- 颜色切换时移除失效的旧覆盖，让新主题和全局语义组重新正常继承。
          for name in pairs(read(namespace)) do
            if not values[name] then vim.api.nvim_set_hl(namespace, name, {}) end
          end
          for name, value in pairs(values) do vim.api.nvim_set_hl(namespace, name, value) end
        end
        vim.api.nvim_win_set_hl_ns(win, namespace)
        if next(caption_changes) then vim.api.nvim_win_set_config(win, caption_changes) end
        if vim.wo[win].winblend ~= 0 then vim.wo[win].winblend = 0 end
        vim.w[win].glow_popup_material = { source_namespace = source, namespace = namespace,
          profile = profile, mode = policy.mode, caption_sources = caption_sources }
      end
    else
      local state = vim.w[win].glow_popup_material
      if state and state.profile == "avante" then
        -- A provider may reuse its split for an ordinary buffer. Release only
        -- our namespace once both its filetype and owned mapping are gone.
        if vim.api.nvim_get_hl_ns({ winid = win }) == state.namespace then
          vim.api.nvim_win_set_hl_ns(win, state.source_namespace or 0)
        end
        vim.w[win].glow_popup_material = nil
      end
    end
  end
end

return M
