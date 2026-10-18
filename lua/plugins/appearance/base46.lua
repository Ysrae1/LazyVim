return {
  "nvim-lua/plenary.nvim",
  { "nvim-tree/nvim-web-devicons", lazy = true },

  {
    "nvchad/ui",
    config = function()
      -- Quickfile can redraw a new tab before NvChad's BufEnter bookkeeping.
      vim.api.nvim_create_autocmd("BufReadPre", {
        group = vim.api.nvim_create_augroup("UserNvChadTabBuffers", { clear = true }),
        callback = function(event)
          if vim.t.bufs == nil then
            vim.t.bufs = vim.bo[event.buf].buflisted and { event.buf } or {}
          end
        end,
      })
      local function load_ui()
        if vim.fn.filereadable(vim.g.base46_cache .. "tbline") == 0 then
          require("base46").load_all_highlights()
        end
        require("nvchad")
      end
      if vim.fn.filereadable(vim.g.base46_cache .. "tbline") == 0 then
        -- base46 requires nvconfig, which lazy-loads this UI configuration.
        -- Finish that module first; compiling highlights here synchronously
        -- would require base46 again while its initialization is in progress.
        vim.schedule(load_ui)
      else
        load_ui()
      end
    end,
  },

  {
    "ysrae1/base46",
    lazy = true,
    build = function()
      require("base46").load_all_highlights()
    end,
  },

  "nvchad/volt", -- optional, needed for theme switcher
  -- or just use Telescope themes
}
