-- Apply GUI options before plugin startup can process the first UI events.
require("config.platform.neovide")

require("config.appearance.intro")

require("config.appearance.startup")

require("config.lazy")

require("config.platform.locale").setup()

require("config.platform.macos_keymaps")

require("config.editor.settings")
