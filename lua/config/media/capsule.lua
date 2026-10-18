-- Shared native media controls. Notebook keeps its own independent alignment.
local M = {}

-- Match NvChad minimal's final position capsule: one grid column after its
-- right endcap. PDF and image headers share this edge and width accounting.
function M.bar(left, right, left_width, right_width)
  local right_padding = " "
  return "%#GlowMediaBar# " .. left .. "%=" .. right .. right_padding,
    left_width + right_width + (left ~= "" and 3 or 2)
end

function M.close_hint(width)
  if width < 2 then return "%#GlowMediaMenuValue#q" end
  return "%#GlowMediaBar#%=%#GlowMediaMenuValue#q%#GlowMediaBar# "
end

function M.format(group, label, value)
  label = tostring(label):gsub("^%s+", ""):gsub("%s+$", "")
  value = tostring(value):gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\r\n\t]", " ")
  local function escape(text) return text:gsub("%%", "%%%%") end
  return "%#" .. group .. "Cap#%#" .. group .. "#" .. escape(label)
    .. " %#" .. group .. "Value# " .. escape(value)
    .. "%#" .. group .. "ValueCap#%#GlowMediaBar#",
    vim.fn.strdisplaywidth("" .. label .. "  " .. value .. "")
end

local function highlight(name)
  return vim.api.nvim_get_hl(0, { name = name, link = false, create = false })
end

local function theme_color(kind, key)
  local ok, palette = pcall(function() return require("base46").get_theme_tb(kind) end)
  local color = ok and palette and palette[key]
  return type(color) == "string" and tonumber(color:gsub("^#", ""), 16) or type(color) == "number" and color or nil
end

local function luminance(color)
  local function linear(channel)
    channel = channel / 255
    return channel <= .04045 and channel / 12.92 or ((channel + .055) / 1.055) ^ 2.4
  end
  return .2126 * linear(math.floor(color / 65536))
    + .7152 * linear(math.floor(color / 256) % 256) + .0722 * linear(color % 256)
end

local function contrasting(color, surface, dark)
  local base = luminance(surface)
  local red, green, blue = math.floor(color / 65536), math.floor(color / 256) % 256, color % 256
  for _ = 1, 60 do
    local light = luminance(red * 65536 + green * 256 + blue)
    if (math.max(light, base) + .05) / (math.min(light, base) + .05) >= 4.5 then break end
    local function adjust(channel)
      return dark and math.min(255, math.ceil(channel + (255 - channel) * .08)) or math.floor(channel * .93)
    end
    red, green, blue = adjust(red), adjust(green), adjust(blue)
  end
  return red * 65536 + green * 256 + blue
end

-- Match Notebook's accent label + neutral value surface, adapting the same hue
-- for readable value text in both themes. Outer caps inherit no background.
function M.refresh_colors()
  local normal, dark = highlight("Normal"), vim.o.background == "dark"
  local surface = dark and (highlight("St_file_txt").bg or highlight("NormalFloat").bg or normal.bg or 0x20242b) or 0xffffff
  local ink = highlight("St_NormalMode").fg or theme_color("base_30", "black") or normal.bg
    or (dark and 0x0b0e14 or 0xfafafa)
  vim.api.nvim_set_hl(0, "GlowMediaBar", { fg = normal.fg, bg = "NONE" })
  for _, palette in ipairs({
    { "Info", "St_NormalMode", "DiagnosticInfo" },
    { "Action", "St_TerminalMode", "DiagnosticOk", "St_VisualMode" },
    { "Menu", "St_InsertMode", "DiagnosticWarn" },
  }) do
    local source = highlight(palette[2])
    if not source.bg and palette[4] then source = highlight(palette[4]) end
    local accent = palette[1] == "Action" and theme_color("base_16", "base0B") or nil
    accent = contrasting(accent or source.bg or highlight(palette[3]).fg or normal.fg or 0x405f8f, surface, dark)
    local group = "GlowMedia" .. palette[1]
    vim.api.nvim_set_hl(0, group, { fg = ink, bg = accent, bold = true })
    vim.api.nvim_set_hl(0, group .. "Value", { fg = accent, bg = surface, bold = false })
    vim.api.nvim_set_hl(0, group .. "Cap", { fg = accent, bg = "NONE" })
    vim.api.nvim_set_hl(0, group .. "ValueCap", { fg = surface, bg = "NONE" })
  end
end

return M
