local function build_windows(plugin)
  local architecture = ({ arm64 = "ARM64", x64 = "x64" })[jit.arch]
  assert(architecture, "Unsupported Neovim architecture for Telescope FZF: " .. jit.arch)
  local build = plugin.dir .. "/build/glow-" .. jit.arch
  local commands = {
    {
      "cmake", "-S", plugin.dir, "-B", build, "-G", "Visual Studio 17 2022", "-A", architecture,
      "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded",
    },
    { "cmake", "--build", build, "--config", "Release", "--target", "install", "--parallel", "2" },
  }
  for _, command in ipairs(commands) do
    local result = vim.system(command, { text = true }):wait(120000)
    assert(result.code == 0, result.stderr .. result.stdout)
  end
  -- Keep generator/architecture caches separate, then publish only the final DLL
  -- to upstream's fixed loader path.
  local copied, err = vim.uv.fs_copyfile(build .. "/libfzf.dll", plugin.dir .. "/build/libfzf.dll")
  assert(copied, err)
end

return {
  {
    "telescope.nvim",
    dependencies = {
      {
        "nvim-telescope/telescope-fzf-native.nvim",
        -- Windows needs a DLL matching Neovim, rather than the shell/compiler host.
        build = vim.fn.has("win32") == 1 and build_windows or "make",
        config = function()
          require("telescope").setup({ defaults = { path_display = nil } })
          local ok, err = pcall(require("telescope").load_extension, "fzf")
          if not ok then
            -- The native sorter is optional; retain Telescope's Lua sorter when
            -- a fresh profile has not built its architecture-specific library yet.
            vim.schedule(function()
              vim.notify(
                "Telescope FZF (" .. jit.arch .. ") unavailable; using the Lua sorter. "
                  .. "Rebuild with :Lazy build telescope-fzf-native.nvim\n" .. tostring(err),
                vim.log.levels.WARN
              )
            end)
          end
        end,
      },
    },
  },
}
