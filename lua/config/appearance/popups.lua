-- 普通浮窗使用实心底材；主窗口、侧栏和 Dashboard 内嵌终端的玻璃材质独立保留。
local M = {}
local bases = { "Normal", "NormalNC", "NormalFloat", "FloatBorder" }

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
  local global = read(0)
  return background(resolver(global)("Normal").bg, global)
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

local function solid(value, normal, popup, base)
  value = vim.deepcopy(value)
  if base then
    -- 反色基础组先还原其实际前景，避免换底材后又被反色交换回来。
    if value.reverse then value.fg, value.reverse = value.bg or normal.bg, nil end
    value.fg, value.bg, value.blend = value.fg or normal.fg, popup, 0
  elseif value.blend and value.blend > 0 or value.bg and value.bg == normal.bg then
    if value.bg == normal.bg then value.bg = popup end
    value.blend = 0
  end
  return value
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

function M.apply()
  if not vim.g.neovide then return end
  vim.o.pumblend = 0
  -- 每轮仅扫描一次全局高亮，只保留会透出背景的稀疏覆盖；不按窗口复制全部语法组。
  local global = read(0)
  local resolve_global = resolver(global)
  local normal = resolve_global("Normal")
  local popup = background(normal.bg, global)
  if not popup then return end
  local sparse, applied = {}, {}
  for name in pairs(global) do
    local value = resolve_global(name)
    if value.bg and value.bg == normal.bg or value.blend and value.blend > 0 then
      sparse[name] = solid(value, normal, popup)
    end
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local config = vim.api.nvim_win_get_config(win)
    if config.relative ~= "" or config.external then
      local filetype = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
      local mapping = mappings(vim.wo[win].winhighlight)
      if is_backdrop(filetype, mapping) then
        -- 仅关闭明确标记的遮罩，不按尺寸、层级或是否可聚焦猜测工具窗口。
        pcall(vim.api.nvim_win_close, win, true)
      elseif not is_dashboard(filetype, mapping) then
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
        local namespace = vim.api.nvim_create_namespace("GlowPopupMaterial:" .. vim.fn.sha256(source .. ":" .. original))
        if not applied[namespace] then
          applied[namespace] = true
          local private = source > 0 and read(source) or {}
          local resolve = resolver(global, private)
          local values = vim.deepcopy(sparse)
          -- 插件自己的语义前景、背景与样式优先；只取消其背景透明度。
          for name, value in pairs(private) do
            values[name] = (value.link and not sparse[name]) and value or solid(resolve(name), normal, popup)
          end
          -- Namespace 优先于 winhighlight，因此将全部原映射复现到该 namespace。
          for name, target in pairs(mapping) do
            if not private[name] or next(private[name]) == nil then values[name] = solid(resolve(target), normal, popup) end
          end
          local source_normal = private.Normal and next(private.Normal) and resolve("Normal") or resolve(mapping.Normal or "Normal")
          for _, name in ipairs(bases) do
            local value
            if private[name] and next(private[name]) then
              value = resolve(name)
            elseif mapping[name] then
              value = resolve(mapping[name])
            elseif name == "Normal" or (name ~= "FloatBorder" and (mapping.Normal or private.Normal)) then
              value = source_normal
            else
              value = resolve(name)
            end
            values[name] = solid(value, source_normal, popup, true)
          end
          -- 颜色切换时移除失效的旧覆盖，让新主题和全局语义组重新正常继承。
          for name in pairs(read(namespace)) do
            if not values[name] then vim.api.nvim_set_hl(namespace, name, {}) end
          end
          for name, value in pairs(values) do vim.api.nvim_set_hl(namespace, name, value) end
        end
        vim.api.nvim_win_set_hl_ns(win, namespace)
        if vim.wo[win].winblend ~= 0 then vim.wo[win].winblend = 0 end
        vim.w[win].glow_popup_material = { source_namespace = source, namespace = namespace }
      end
    end
  end
end

return M
