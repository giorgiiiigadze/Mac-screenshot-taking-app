import SwiftUI

@main
struct RealMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = CaptureModel.shared

    var body: some Scene {
        MenuBarExtra("RealMac", systemImage: "camera.viewfinder") {
            MenuBarView(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            VStack(spacing: 12) {
                Image(systemName: "camera.viewfinder").font(.system(size: 36))
                Text("RealMac").font(.title2.bold())
                Text("Global shortcut: ⌘⇧B").foregroundStyle(.secondary)
            }
            .frame(width: 320, height: 180)
        }
    }
}

private struct MenuBarView: View {
    @ObservedObject var model: CaptureModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RealMac").font(.headline)
                    Text("Screen + reaction, one moment")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "camera.viewfinder")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }

            Button { Task { await model.startCapture() } } label: {
                Label(model.isWorking ? "Capturing…" : "Capture Now", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isWorking)

            HStack {
                Text("⌘⇧B").font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Button("Open Preview") { PreviewWindowController.shared.show(model: model) }
                    .buttonStyle(.plain)
            }
            Divider()
            Button("Quit RealMac") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 300)
    }
}
