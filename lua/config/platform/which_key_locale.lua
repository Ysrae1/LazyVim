-- WhichKey 3aab2147 has no locale option for generated counts/help labels.
-- Action descriptions continue through the official opts.replace.desc API.
-- These provider-only adapters leave user descriptions and vendor files intact.
local M = {}
local labels = { [" close"] = " 关闭", [" back"] = " 返回", [" scroll"] = " 滚动" }

local function chinese()
  return require("config.platform.locale").current() == "zh"
end

local function generated_count(node, opts)
  opts = opts or {}
  if node.desc or (opts.default or "count") ~= "count" or opts.group == false or node:can_expand() then return end
  local rhs = node.keymap and node.keymap.rhs
  if type(rhs) == "string" and rhs ~= "" then return end
  local count = node:count()
  if count > 0 then return count end
end

function M.item(original, node, opts)
  local item = original(node, opts)
  local plugin = node.parent and node.parent.plugin
  if plugin == "marks" and type(node.desc) == "string" and node.desc:sub(1, 6) == "file: " then
    -- The label is provider chrome; the suffix is a user path even when its
    -- basename happens to be a known translatable product phrase.
    item.desc = (chinese() and "文件：" or "file: ") .. node.desc:sub(7)
  elseif plugin == "registers" and vim.g.clipboard and vim.g.clipboard.name == "OSC 52"
    and (node.key == "+" or node.key == "*")
    and node.value == "OSC 52 detected, register not checked to maintain compatibility" then
    item.value = require("config.platform.locale").t(node.value)
  end
  local icon = node.mapping and node.mapping.icon
  if type(node.action) == "function" and type(icon) == "table" and icon.cat == "file" and icon.name then
    -- Official extras.expand.win/buf entries carry user file names, not
    -- product action labels, even when a file is named Config/Keymaps.
    item.desc = node.desc
    return item
  end
  local count = chinese() and generated_count(node, opts)
  if count then
    local group = item.group and require("which-key.config").icons.group or ""
    item.desc = group .. count .. " 个快捷键"
  end
  return item
end

function M.append(append, self, value, opts, source)
  local highlight = type(opts) == "table" and opts.hl or opts
  if highlight == "WhichKeySeparator" and labels[value] and chinese() then
    -- Restrict this class method to the pinned provider's own renderer;
    -- do not intercept custom users of wk.Text or wrap view.show again
    -- (the popup material adapter already owns its display boundary).
    if source and source:gsub("\\", "/"):match("/which%-key/view%.lua$") then
      value = labels[value]
    end
  end
  return append(self, value, opts)
end

-- Migrate only the exact old wrapper marked by this adapter. Keep the vendor
-- entry point once, then dispatch through require() so hot reloads replace
-- translation logic without replacing/stacking provider methods again.
local function original(provider, method, marker, upvalue)
  local current = provider[method]
  if provider[marker] ~= current then return current end
  for index = 1, 20 do
    local name, value = debug.getupvalue(current, index)
    if not name then break end
    if name == upvalue and type(value) == "function" then return value end
  end
  error("Cannot migrate the adapter's old WhichKey " .. method .. " wrapper safely")
end

function M.setup()
  local view = require("which-key.view")
  local text = require("which-key.text")
  if not view._glow_locale_dispatch then
    local base = original(view, "item", "_glow_locale_item", "original")
    view.item = function(node, opts)
      return require("config.platform.which_key_locale").item(base, node, opts)
    end
    view._glow_locale_item, view._glow_locale_dispatch = view.item, true
  end

  -- Footer labels bypass replace.desc in this pinned renderer. Translate
  -- only its exact separator segments during show(), before widths/first draw.
  if not text._glow_locale_dispatch then
    local base = original(text, "append", "_glow_locale_append", "append")
    text.append = function(self, value, opts)
      local caller = debug.getinfo(2, "S")
      return require("config.platform.which_key_locale").append(base, self, value, opts, caller and caller.source)
    end
    text._glow_locale_append, text._glow_locale_dispatch = text.append, true
  end

  vim.api.nvim_create_autocmd("User", {
    group = vim.api.nvim_create_augroup("GlowWhichKeyLocale", { clear = true }),
    pattern = "GlowLanguageChanged",
    callback = function()
      if view.valid() then view.show() end
    end,
  })
end

return M
