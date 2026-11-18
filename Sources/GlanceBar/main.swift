import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let arguments = CommandLine.arguments
    let demo = arguments.contains("--demo")
    if let index = arguments.firstIndex(of: "--snapshot") {
        guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
            FileHandle.standardError.write(Data("Usage: GlanceBar --snapshot <directory> [--demo]\n".utf8))
            exit(2)
        }
        // Render the menu bar item and the panel to PNG files, then exit: live readings, or made-up
        // ones with --demo.
        app.setActivationPolicy(.prohibited)
        let directory = URL(fileURLWithPath: arguments[index + 1])
        Task { @MainActor in
            await SnapshotRunner.run(into: directory, demo: demo)
            exit(0)
        }
        app.run()
    } else {
        let delegate = AppDelegate(demo: demo)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
