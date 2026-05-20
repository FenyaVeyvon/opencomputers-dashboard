local base = "https://raw.githubusercontent.com/FenyaVeyvon/opencomputers-dashboard/main/eonlink"

return {
  name = "EonLink",
  version = "0.1.0",
  baseUrl = base,
  installDir = "/home/eonlink",
  files = {
    { path = "VERSION", url = base .. "/VERSION" },
    { path = "README_OC.md", url = base .. "/README_OC.md" },
    { path = "bin/EonLink.lua", target = "/bin/EonLink.lua", url = base .. "/bin/eonlink.lua" },
    { path = "bin/eonlink.lua", target = "/bin/eonlink.lua", url = base .. "/bin/eonlink.lua" },
    { path = "main.lua", url = base .. "/app/main.lua" },
    { path = "config.example.lua", url = base .. "/app/config.example.lua" },
    { path = "core/logger.lua", url = base .. "/app/core/logger.lua" },
    { path = "core/fsutil.lua", url = base .. "/app/core/fsutil.lua" },
    { path = "core/downloader.lua", url = base .. "/app/core/downloader.lua" },
    { path = "core/manifest.lua", url = base .. "/app/core/manifest.lua" },
    { path = "core/module_loader.lua", url = base .. "/app/core/module_loader.lua" },
    { path = "core/event_bus.lua", url = base .. "/app/core/event_bus.lua" },
    { path = "core/protocol.lua", url = base .. "/app/core/protocol.lua" },
    { path = "core/net_tcp.lua", url = base .. "/app/core/net_tcp.lua" },
    { path = "core/state.lua", url = base .. "/app/core/state.lua" },
    { path = "modules/chat.lua", url = base .. "/app/modules/chat.lua" },
    { path = "modules/command_box.lua", url = base .. "/app/modules/command_box.lua" },
    { path = "modules/radar.lua", url = base .. "/app/modules/radar.lua" },
    { path = "modules/machines.lua", url = base .. "/app/modules/machines.lua" },
    { path = "modules/inventory.lua", url = base .. "/app/modules/inventory.lua" }
  }
}
