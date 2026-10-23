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

-- LazyVim 28db03f's ai_whichkey() gives MiniAi bfb26d9 the same object
-- descriptions under a/i (and an/in/al/il). Resolve their actual semantics
-- from the provider's mapped closure, never from a guessed key prefix.
local mini_ai_objects = {
  ['" string'] = { '" string', 'inner " string' },
  ["' string"] = { "' string", "inner ' string" },
  ['` string'] = { '` string', 'inner ` string' },
  ['() block'] = { 'Round Bracket Block', 'Round Bracket Contents Without Edge Whitespace' },
  ['() block with ws'] = { 'Round Bracket Block', 'Round Bracket Contents With Edge Whitespace' },
  ['<> block'] = { '<> block', 'Angle Bracket Contents Without Edge Whitespace' },
  ['<> block with ws'] = { '<> block', 'Angle Bracket Contents With Edge Whitespace' },
  ['[] block'] = { '[] block', 'Square Bracket Contents Without Edge Whitespace' },
  ['[] block with ws'] = { '[] block', 'Square Bracket Contents With Edge Whitespace' },
  ['{} block'] = { 'Brace Block', 'Brace Contents Without Edge Whitespace' },
  ['{} with ws'] = { 'Brace Block', 'Brace Contents With Edge Whitespace' },
  [')]} block'] = { 'Bracket Block', 'Bracket Contents With Edge Whitespace' },
  ['whitespace'] = { 'Space-Delimited Text With Right Separator', 'Space-Delimited Inner Text' },
  ['underscore'] = { 'Underscore-Delimited Text With Right Separator', 'Underscore-Delimited Inner Text' },
  ['user prompt'] = { 'Text With User-Specified Boundaries', 'Text Inside User-Specified Boundaries' },
  ['argument'] = { 'Argument With Adjacent Separator Or Whitespace', 'Argument Without Separator Or Edge Whitespace' },
  ['class'] = { 'Class Definition', 'Class Contents' },
  ['digit(s)'] = { 'Consecutive Digits', 'Consecutive Digits' },
  ['CamelCase / snake_case'] = { 'CamelCase Or Snake Case Segment', 'CamelCase Or Snake Case Segment' },
  ['function'] = { 'Function Definition', 'Function Body' },
  ['entire file'] = { 'Entire File With Edge Blank Lines', 'Entire File Without Edge Blank Lines' },
  ['indent'] = { 'Indentation Text Object', 'Indentation Text Object' },
  ['block, conditional, loop'] = { 'Code Block Conditional Or Loop', 'Code Block Conditional Or Loop Contents' },
  ['quote `"\''] = { 'Quoted Text With Delimiters', 'Quoted Text Without Delimiters' },
  ['tag'] = { 'tag block', 'inner tag block' },
  ['use/call'] = { 'Function Call With Name And Parentheses', 'Function Call Arguments' },
  ['use/call without dot'] = { 'Function Call Without Dots In Name', 'Function Call Arguments Without Dots In Name' },
}

local function mini_ai_context(prefix)
  local callback = prefix and prefix.keymap and prefix.keymap.callback
  if type(callback) ~= 'function' then return end
  local source = debug.getinfo(callback, 'S').source:gsub('\\', '/')
  if not source:match('/mini/ai%.lua$') then return end
  local kind, search
  for index = 1, 10 do
    local name, value = debug.getupvalue(callback, index)
    if not name then break end
    if name == 'ai_type' then kind = value elseif name == 'search_method' then search = value end
  end
  if kind == 'a' or kind == 'i' then return kind, search end
end

local function mini_ai_text(node)
  if not chinese() then return end
  local kind, search = mini_ai_context(node)
  if kind then
    local group = kind == 'i' and 'Inside Text Object' or 'Around Text Object'
    if search == 'next' then group = kind == 'i' and 'Next Inside Text Object' or 'Next Around Text Object'
    elseif search == 'prev' then group = kind == 'i' and 'Previous Inside Text Object' or 'Previous Around Text Object' end
    return require('config.platform.locale').t(group), true
  end
  kind = mini_ai_context(node.parent)
  if not kind then return end
  -- A real child mapping overrides MiniAi's generated display-only metadata.
  -- Retain its explicit description even if it resembles a provider phrase.
  if node.keymap then return node.keymap.desc end
  local row = mini_ai_objects[node.desc]
  if row then return require('config.platform.locale').t(row[kind == 'a' and 1 or 2]) end
end

function M.item(original, node, opts)
  local item = original(node, opts)
  local mini_text, mini_group = mini_ai_text(node)
  if mini_text then
    item.desc = (mini_group and item.group and require('which-key.config').icons.group or '') .. mini_text
  end
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
      return require("config.locale.which_key").item(base, node, opts)
    end
    view._glow_locale_item, view._glow_locale_dispatch = view.item, true
  end

  -- Footer labels bypass replace.desc in this pinned renderer. Translate
  -- only its exact separator segments during show(), before widths/first draw.
  if not text._glow_locale_dispatch then
    local base = original(text, "append", "_glow_locale_append", "append")
    text.append = function(self, value, opts)
      local caller = debug.getinfo(2, "S")
      return require("config.locale.which_key").append(base, self, value, opts, caller and caller.source)
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
