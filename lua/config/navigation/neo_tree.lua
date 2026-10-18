local M = {}
local cache = {}

-- Preserve the hue while fading toward the theme's bright or dark end.
-- The three dark-mode steps retain about 74%, 68%, and 48% brightness.
function M.fade_color(color, amount, light)
    local r = math.floor(color / 0x10000)
    local g = math.floor(color / 0x100) % 0x100
    local b = color % 0x100
    local strength = 0.80 * (1 - amount)
    local function byte(value)
        local faded = light and (value + (255 - value) * strength) or (value * (1 - strength))
        return math.max(0, math.min(255, math.floor(faded + 0.5)))
    end
    return byte(r) * 0x10000 + byte(g) * 0x100 + byte(b)
end

function M.setup()
    local highlights = require("neo-tree.ui.highlights")
    highlights.get_faded_highlight_group = function(name, amount)
        assert(type(name) == "string", "Neo-tree fade requires a highlight name")
        assert(type(amount) == "number" and amount >= 0 and amount <= 1, "Invalid Neo-tree fade amount")
        -- Neo-tree's default reader leaves links unresolved, losing their real foreground.
        local source = vim.api.nvim_get_hl(0, { name = name, link = false, create = false })
        local light = vim.o.background == "light"
        if not source.fg then
            source.fg = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).fg or (light and 0x000000 or 0xffffff)
        end
        local group = name .. "GlowFade" .. math.floor(amount * 100)
        local previous = cache[group]
        if
            not previous
            or previous.amount ~= amount
            or previous.light ~= light
            or not vim.deep_equal(previous.source, source)
        then
            local faded = vim.deepcopy(source)
            local channel = faded.reverse and faded.bg and "bg" or "fg"
            faded[channel] = M.fade_color(faded[channel], amount, light)
            vim.api.nvim_set_hl(0, group, faded)
            cache[group] = { source = source, amount = amount, light = light }
        end
        return group
    end
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("NeoTreeColorFade", { clear = true }),
        callback = function()
            cache = {}
        end,
    })
end

return M
