import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let service = DockBadgeService()
let url = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
var phases: [String] = []
var timer: Timer?
NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
    if let error { print(error); fflush(stdout); exit(2) }
}
timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
    service.scan { badges in
        guard let badges else { return }
        let badge = badges[url.path]
        if phases.isEmpty && badge == "7" { phases.append("7") }
        if phases == ["7"] && badge == "120" { phases.append("120") }
        if phases == ["7", "120"] && badge == nil {
            print("PASS: real Dock badge 7 → 120 → removed")
            fflush(stdout)
            timer?.invalidate()
            NSRunningApplication.runningApplications(withBundleIdentifier: "dev.local.MacBar.BadgeFixture").forEach { $0.terminate() }
            app.terminate(nil)
        }
    }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 11) {
    print("FAIL: phases=\(phases)"); fflush(stdout); exit(3)
}
app.run()
