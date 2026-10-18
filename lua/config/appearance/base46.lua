local M = {}
local queued = false
local forwarding = false

local function active()
    return package.loaded.base46 and (vim.g.colors_name == nil or vim.g.colors_name == "nvchad")
end

local function integrations()
    local base46 = require("base46")
    -- Replay devicons after ColorScheme handlers that reset the provider's colors.
    for _, name in ipairs({ "devicons", "avante", "yazi", "dap", "snacks" }) do
        for group, attributes in pairs(base46.get_integration(name)) do
            -- The custom Snacks integration also contains a global FloatBorder override.
            -- Apply its Snacks groups without changing unrelated plugin borders.
            if name ~= "snacks" or group:match("^Snacks") then
                vim.api.nvim_set_hl(0, group, attributes)
            end
        end
    end
end

function M.apply()
    if not active() then
        return
    end
    integrations()
    require("config.appearance.ui").apply()
    require("config.appearance.completion").apply()
    require("config.appearance.fff").apply()
    -- Finish the material after the integration replay has set its final RGB.
    -- This also covers nested Avante ColorScheme resets without polling.
    require("config.appearance.transparency").apply()

    -- Recompute faded edge groups on existing visible trees without navigation.
    local manager = package.loaded["neo-tree.sources.manager"]
    if manager then
        for _, source in ipairs({ "filesystem", "buffers", "git_status" }) do
            manager.redraw(source)
        end
    end
    vim.cmd("redrawstatus!")
end

local function schedule_apply()
    if queued then
        return
    end
    queued = true
    -- Some plugins schedule their own ColorScheme handlers. Apply after those
    -- handlers so they cannot overwrite Base46 with their default palette.
    vim.schedule(function()
        vim.schedule(function()
            queued = false
            M.apply()
        end)
    end)
end

function M.setup()
    local group = vim.api.nvim_create_augroup("Base46PluginCompatibility", { clear = true })
    vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "NvThemeReload",
        callback = function()
            if not active() or forwarding then
                return
            end
            integrations()
            forwarding = true
            local ok, err = pcall(vim.api.nvim_exec_autocmds, "ColorScheme", {
                pattern = vim.g.colors_name or "nvchad",
                modeline = false,
            })
            forwarding = false
            schedule_apply()
            if not ok then
                vim.notify("Base46 plugin theme refresh: " .. tostring(err), vim.log.levels.WARN)
            end
        end,
    })
    vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = schedule_apply })
    vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = { "LazyLoad", "VeryLazy" },
        callback = schedule_apply,
    })
end

return M
