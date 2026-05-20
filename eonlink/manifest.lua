local base = "https://raw.githubusercontent.com/FenyaVeyvon/opencomputers-dashboard/main/eonlink"

return {
  name = "EonLink",
  version = "0.1.8",
  baseUrl = base,
  installDir = "/home/eonlink",
  files = {
    { path = "VERSION", url = base .. "/VERSION" },
    { path = "README_OC.md", url = base .. "/README_OC.md" },
    { path = "bin/EonLink.lua", target = "/bin/EonLink.lua", url = base .. "/bin/eonlink.lua" },
    { path = "bin/eonlink.lua", target = "/bin/eonlink.lua", url = base .. "/bin/eonlink.lua" },
    { path = "main.lua", url = base .. "/app/main.lua" },
    { path = "core/logger.lua", url = base .. "/app/core/logger.lua" },
    { path = "core/fsutil.lua", url = base .. "/app/core/fsutil.lua" },
    { path = "core/downloader.lua", url = base .. "/app/core/downloader.lua" },
    { path = "core/manifest.lua", url = base .. "/app/core/manifest.lua" },
    { path = "core/json.lua", url = base .. "/app/core/json.lua" },
    { path = "core/auth.lua", url = base .. "/app/core/auth.lua" },
    { path = "core/gui.lua", url = base .. "/app/core/gui.lua" },
    { path = "core/protocol.lua", url = base .. "/app/core/protocol.lua" },
    { path = "core/net_tcp.lua", url = base .. "/app/core/net_tcp.lua" },
    { path = "src/shared/tcp.lua", url = base .. "/app/src/shared/tcp.lua" },
    { path = "src/applied/members.lua", url = base .. "/app/src/applied/members.lua" },
    { path = "src/modules/chatbox.lua", url = base .. "/app/src/modules/chatbox.lua" }
  }
}
