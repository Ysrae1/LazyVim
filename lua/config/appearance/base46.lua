local M = {}
local queued = false
local forwarding = false

local function active()
    return package.loaded.base46 and (vim.g.colors_name == nil or vim.g.colors_name == "nvchad")
end

local function refresh_background_integrations()
    local base46 = require("base46")
    -- Base46 compiles before its defaults cache sets 'background'. These three
    -- integrations branch on that option, so a theme change otherwise compiles
    -- the new palette with the previous mode. Repair both live groups and cache.
    local mode = base46.get_theme_tb("type")
    vim.o.background = mode
    for _, name in ipairs({ "defaults", "lsp", "cmp" }) do
        package.loaded["base46.integrations." .. name] = nil
        local highlights = base46.get_integration(name)
        local source = base46.tb_2str(highlights)
        if name == "defaults" then
            source = "vim.o.tgc=true vim.o.background='" .. mode .. "' " .. source
        end
        base46.str_to_cache(name, source)
        for group, attributes in pairs(highlights) do
            vim.api.nvim_set_hl(0, group, attributes)
        end
    end
end

local function refresh_noice_copies()
    local highlights = package.loaded["noice.config.highlights"]
    if type(highlights) ~= "table" then
        return
    end
    -- Noice copies Search/IncSearch instead of linking them, then uses
    -- default=true on reload. Refresh only those copied semantic colors.
    for group, target in pairs(highlights.defaults or {}) do
        if target == "Search" or target == "IncSearch" then
            local attributes = highlights.get_link(target)
            attributes.default = nil
            vim.api.nvim_set_hl(0, "Noice" .. group, attributes)
        end
    end
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
    refresh_background_integrations()
    integrations()
    require("config.appearance.ui").apply()
    require("config.appearance.completion").apply()
    require("config.appearance.fff").apply()
    refresh_noice_copies()
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
    if vim.g.neovide and vim.fn.has("win32") == 1 then
        -- A theme can settle while Neo-tree owns focus without repainting the
        -- Windows GUI. Flush the completed palette once, without user input.
        vim.cmd("redraw!")
    else
        vim.cmd("redrawstatus!")
    end
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
