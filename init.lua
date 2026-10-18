-- Apply GUI options before plugin startup can process the first UI events.
require("config.platform.neovide")

require("config.appearance.startup")

require("config.appearance.intro")

require("config.lazy")

require("config.platform.locale")

require("config.platform.macos_keymaps")

require("config.editor.settings")
