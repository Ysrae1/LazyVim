-- Pure UI label catalog: constructing/reloading it does not change keymaps,
-- preferences, commands or user content. Existing GUI sessions can adopt it live.
local M = {}
function M.new(current, opts)
  opts = opts or {}
  local phrases, folded, out = {}, {}, {}
  for _, name in ipairs({ "config.platform.locale_messages", "config.platform.locale_ui_messages" }) do
    if opts.reload then package.loaded[name] = nil end
    local ok, entries = pcall(require, name)
    if ok then
      for _, pair in ipairs(entries) do
        local source = vim.trim(pair[1])
        local row = { en = vim.trim(pair[3] or pair[1]), zh = vim.trim(pair[2]) }
        if not phrases[source] then
          phrases[source] = row
          phrases[row.en] = phrases[row.en] or row
          folded[source:lower()] = folded[source:lower()] or row
          folded[row.en:lower()] = folded[row.en:lower()] or row
          phrases[row.zh] = phrases[row.zh] or row
        end
      end
    elseif name == "config.platform.locale_messages" then
      error(entries)
    end
  end
  -- Only known product labels are matched. Case/spacing variants and leading UI
  -- glyphs are normalized for lookup, never applied as replacements to user text.
  local function phrase(value)
    return phrases[value] or folded[value:gsub("%s+", " "):lower()]
  end
  local states = { { "Enable ", "启用 " }, { "Disable ", "停用 " }, { "Toggle ", "切换 " } }
  local function resolve(value, lang)
    local row = phrase(value)
    if row then return row[lang] end
    for _, state in ipairs(states) do
      for _, prefix in ipairs(state) do
        if value:sub(1, #prefix):lower() == prefix:lower() then
          local rest = phrase(value:sub(#prefix + 1))
          if rest then
            local label = rest[lang]
            local prefix = lang == "zh" and vim.trim(state[2]) or state[1]
            if lang == "zh" and label:match("^[%w]") then prefix = prefix .. " " end
            return prefix .. label
          end
        end
      end
    end
  end
  local function decorated(value, lang)
    local count, split, seen = vim.fn.strchars(value), 0, false
    for i = 0, count - 1 do
      local char = vim.fn.strcharpart(value, i, 1)
      local code = vim.fn.char2nr(char)
      local glyph = (code >= 0xe000 and code <= 0xf8ff) or (code >= 0xf0000 and code <= 0xffffd)
        or (code >= 0x100000 and code <= 0x10fffd) or (code >= 0x2600 and code <= 0x27bf)
        or (code >= 0x1f300 and code <= 0x1faff)
      if glyph or char == "+" then seen = true; split = i + 1
      elseif seen and char:match("%s") then split = i + 1
      else break end
    end
    if seen and split < count then
      local result = resolve(vim.fn.strcharpart(value, split), lang)
      if result then return vim.fn.strcharpart(value, 0, split) .. result end
    end
  end
  function out.t(text)
    if type(text) ~= "string" then return text end
    local left, value, right = text:match("^(%s*)(.-)(%s*)$")
    local translated = resolve(value, current()) or decorated(value, current())
    return translated and (left .. translated .. right) or text
  end
  function out.known(text)
    if type(text) ~= "string" then return false end
    local value = vim.trim(text)
    return resolve(value, "en") ~= nil or decorated(value, "en") ~= nil
  end
  return out
end
return M
