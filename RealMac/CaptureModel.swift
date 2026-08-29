import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class CaptureModel: ObservableObject {
    static let shared = CaptureModel()

    @Published var compositeImage: NSImage?
    @Published var countdown: Int?
    @Published var isWorking = false
    @Published var statusText = "Getting ready…"
    @Published var isShowingError = false
    @Published var errorMessage = ""

    private let screenService = ScreenCaptureService()
    private let cameraService = CameraCaptureService()

    private init() { }

    func startCapture() async {
        guard !isWorking else { return }
        isWorking = true
        statusText = "Checking permissions…"
        PreviewWindowController.shared.show(model: self, activate: false)

        do {
            try await cameraService.prepare()
            for value in stride(from: 3, through: 1, by: -1) {
                countdown = value
                try await Task.sleep(for: .seconds(1))
            }

            countdown = nil
            statusText = "Capturing your moment…"
            PreviewWindowController.shared.hideForCapture()
            try await Task.sleep(for: .milliseconds(250))

            async let screen = screenService.captureMainDisplay()
            async let reaction = cameraService.capturePhoto()
            let (screenImage, reactionImage) = try await (screen, reaction)
            compositeImage = try ImageComposer.compose(screen: screenImage, reaction: reactionImage)
            isWorking = false
            PreviewWindowController.shared.show(model: self)
        } catch {
            countdown = nil
            isWorking = false
            errorMessage = error.localizedDescription
            isShowingError = true
            PreviewWindowController.shared.show(model: self)
        }
    }

    func save() {
        guard let compositeImage else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "RealMac-\(Self.fileTimestamp).jpg"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ImageComposer.jpegData(for: compositeImage).write(to: url, options: .atomic)
        } catch { show(error) }
    }

    func share() {
        guard let compositeImage else { return }
        PreviewWindowController.shared.showSharePicker(for: compositeImage)
    }

    private func show(_ error: Error) {
        errorMessage = error.localizedDescription
        isShowingError = true
    }

    private static var fileTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}
