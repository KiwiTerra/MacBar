import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.regular)
DispatchQueue.main.asyncAfter(deadline: .now() + 1) { app.dockTile.badgeLabel = "7" }
DispatchQueue.main.asyncAfter(deadline: .now() + 3) { app.dockTile.badgeLabel = "120" }
DispatchQueue.main.asyncAfter(deadline: .now() + 5) { app.dockTile.badgeLabel = nil }
DispatchQueue.main.asyncAfter(deadline: .now() + 8) { app.terminate(nil) }
app.run()
