return {
  {
    "dmtrKovalenko/fff",
    tag = "v0.11.0",
    commit = "95fd777c2529fc7b4d7572dabff64cc07268f2c5",
    pin = true,
    lazy = false, -- FFF starts its index only when a picker/search is requested.
    build = function(plugin)
      local done, download_error = false, nil
      require("fff.download").ensure_downloaded({ version = plugin.tag, force = true }, function(success, err)
        if not success then
          download_error = err or "unknown download error"
        end
        done = true
      end)
      local completed = vim.wait(120000, function()
        return done
      end, 100)
      if not completed then
        error("FFF " .. plugin.tag .. " binary download timed out")
      end
      if download_error then
        error("FFF " .. plugin.tag .. " binary download failed: " .. download_error)
      end
    end,
    opts = {
      lazy_sync = true,
      layout = { border = "rounded" },
      debug = { enabled = false, show_scores = false },
    },
  },
}
