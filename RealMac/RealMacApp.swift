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

            VStack(alignment: .leading, spacing: 6) {
                Text("Timer").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Picker("Timer", selection: $model.countdownDuration) {
                    Text("Instant").tag(0)
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(model.isWorking)
            }

            HStack {
                Text("⌘⇧B").font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Button(model.isWorking ? "Cancel" : "Open Preview") {
                    if model.isWorking {
                        model.cancelCapture()
                    } else {
                        PreviewWindowController.shared.show(model: model)
                    }
                }
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
