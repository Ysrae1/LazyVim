return {
  {
    "smoka7/multicursors.nvim",
    event = "VeryLazy",
    dependencies = {
      "nvimtools/hydra.nvim",
    },
    opts = function()
      local mouse = require("config.editor.multicursor_mouse")
      local actions = require("config.editor.multicursor_actions")
      return {
        normal_keys = {
          -- Navigation only moves the real cursor; confirm an edit point separately.
          ["j"] = { method = false, opts = {} },
          ["k"] = { method = false, opts = {} },
          ["<C-n>"] = { method = mouse.start, opts = { desc = "Add cursor at current position" } },
          ["<C-p>"] = { method = mouse.undo_point, opts = { desc = "Undo last cursor addition" } },
          ["gU"] = { method = function() actions.change_case(true) end, opts = { desc = "Uppercase selections" } },
          ["gu"] = { method = function() actions.change_case(false) end, opts = { desc = "Lowercase selections" } },
          ["<LeftMouse>"] = { method = mouse.click, opts = { desc = "Add cursor with mouse" } },
          ["<LeftDrag>"] = { method = mouse.drag, opts = { desc = "" } },
          ["<LeftRelease>"] = { method = mouse.release, opts = { desc = "" } },
          ["<D-LeftMouse>"] = { method = mouse.press, opts = { desc = "Command+drag: add selection" } },
          ["<D-LeftDrag>"] = { method = mouse.drag, opts = { desc = "" } },
          ["<D-LeftRelease>"] = { method = mouse.release, opts = { desc = "" } },
        },
        extend_keys = {
          ["<C-p>"] = { method = mouse.undo_point, opts = { desc = "Undo last cursor addition" } },
          ["gU"] = { method = function() actions.change_case(true) end, opts = { desc = "Uppercase selections" } },
          ["gu"] = { method = function() actions.change_case(false) end, opts = { desc = "Lowercase selections" } },
        },
      }
    end,
    config = function(_, opts)
      require("multicursors").setup(opts)
      require("config.editor.multicursor_mouse").setup()
      require("config.appearance.ui").apply_selection_style()
    end,
    cmd = { "MCstart", "MCvisual", "MCclear", "MCpattern", "MCvisualPattern", "MCunderCursor" },
    keys = {
      { "<leader>m", function() require("config.editor.multicursor_mouse").start() end, mode = "n", desc = "Start multi-cursor editing" },
      { "<leader>m", function() require("config.editor.multicursor_mouse").visual() end, mode = "x", desc = "Start editing selected text" },
      { "<D-LeftMouse>", function() require("config.editor.multicursor_mouse").press() end, mode = { "n", "x" }, desc = "Add selection with Command+drag" },
      { "<D-LeftDrag>", function() require("config.editor.multicursor_mouse").drag() end, mode = { "n", "x" }, desc = "Extend mouse selection" },
      { "<D-LeftRelease>", function() require("config.editor.multicursor_mouse").release() end, mode = { "n", "x" }, desc = "Finish mouse selection" },
    },
  },
}
