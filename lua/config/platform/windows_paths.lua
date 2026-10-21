local M = {}

-- Neovim 0.12.3 encodes UNC backslashes as part of a URI authority, which
-- language servers reject (neovim/neovim#18909). Keep all non-UNC behavior.
function M.setup()
    if vim.fn.has("win32") ~= 1 then
        return
    end
    local uri = require("vim.uri")
    if uri._glow_windows_paths then
        return
    end
    local from_fname, to_fname = uri.uri_from_fname, uri.uri_to_fname
    uri.uri_from_fname = function(path)
        local windows = path:gsub("\\", "/")
        local host, tail = windows:match("^//([^/]+)(/[^/]+.*)$")
        if host and host ~= "?" and host ~= "." then
            return "file://" .. host .. uri.uri_encode(tail)
        end
        return from_fname(path)
    end
    uri.uri_to_fname = function(value)
        local without_fragment = value:gsub("#.*$", "")
        local host, tail = without_fragment:match("^file://([^/]+)(/.*)$")
        -- localhost and drive-letter forms retain Neovim's existing handling.
        if host and host:lower() ~= "localhost" and not host:find("[:@?#%%]") then
            return "\\\\" .. host .. uri.uri_decode(tail):gsub("/", "\\")
        end
        return to_fname(value)
    end
    -- Update the module used internally by uri_from/to_bufnr and any already
    -- cached public aliases. Merely replacing vim.uri_from_fname misses buffers.
    vim.uri_from_fname, vim.uri_to_fname = uri.uri_from_fname, uri.uri_to_fname
    uri._glow_windows_paths = { from_fname = from_fname, to_fname = to_fname }
end

return M
