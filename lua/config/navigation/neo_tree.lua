local M = {}
local cache = {}

-- Light 玻璃的实际底色不一定是白色；向主题的弱化文字色收敛，避免末尾字变白发光。
-- 只影响侧栏末尾三个字符，不改主题色板；Dark 保留原先向黑色渐隐的效果。
local function light_fade_target()
    local color = require("base46").get_theme_tb("base_30").light_grey
    return assert(tonumber(color:sub(2), 16), "Invalid Neo-tree light fade color")
end

-- The three dark-mode steps retain about 74%, 68%, and 48% brightness.
function M.fade_color(color, amount, light, target)
    local r = math.floor(color / 0x10000)
    local g = math.floor(color / 0x100) % 0x100
    local b = color % 0x100
    local strength = 0.80 * (1 - amount)
    target = target or (light and light_fade_target() or 0)
    local function byte(value, destination)
        local faded = light and (value + (destination - value) * strength) or (value * (1 - strength))
        return math.max(0, math.min(255, math.floor(faded + 0.5)))
    end
    return byte(r, math.floor(target / 0x10000)) * 0x10000
        + byte(g, math.floor(target / 0x100) % 0x100) * 0x100
        + byte(b, target % 0x100)
end

function M.setup()
    local highlights = require("neo-tree.ui.highlights")
    highlights.get_faded_highlight_group = function(name, amount)
        assert(type(name) == "string", "Neo-tree fade requires a highlight name")
        assert(type(amount) == "number" and amount >= 0 and amount <= 1, "Invalid Neo-tree fade amount")
        -- Neo-tree's default reader leaves links unresolved, losing their real foreground.
        local source = vim.api.nvim_get_hl(0, { name = name, link = false, create = false })
        local light = vim.o.background == "light"
        local target = light and light_fade_target() or 0
        if not source.fg then
            source.fg = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).fg or (light and 0x000000 or 0xffffff)
        end
        local group = name .. "GlowFade" .. math.floor(amount * 100)
        local previous = cache[group]
        if
            not previous
            or previous.amount ~= amount
            or previous.light ~= light
            or previous.target ~= target
            or not vim.deep_equal(previous.source, source)
        then
            local faded = vim.deepcopy(source)
            local channel = faded.reverse and faded.bg and "bg" or "fg"
            faded[channel] = M.fade_color(faded[channel], amount, light, target)
            vim.api.nvim_set_hl(0, group, faded)
            cache[group] = { source = source, amount = amount, light = light, target = target }
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
