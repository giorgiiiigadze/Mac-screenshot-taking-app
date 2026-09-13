import AppKit
import Combine
import UniformTypeIdentifiers

struct CaptureRecord: Identifiable {
    let id: UUID
    let createdAt: Date
    var cameraCorner: CameraCorner
    var thumbnail: NSImage

    var title: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }
}

@MainActor
final class CaptureModel: ObservableObject {
    static let shared = CaptureModel()

    @Published var compositeImage: NSImage?
    @Published var countdown: Int?
    @Published var isWorking = false
    @Published var statusText = "Getting ready…"
    @Published var isShowingError = false
    @Published var errorMessage = ""
    @Published private(set) var cameraCorner: CameraCorner = .topRight
    @Published private(set) var captures: [CaptureRecord] = []
    @Published private(set) var selectedCaptureID: UUID?
    @Published private(set) var screenPreviewImage: NSImage?
    @Published private(set) var reactionPreviewImage: NSImage?
    @Published var countdownDuration = UserDefaults.standard.object(forKey: "countdownDuration") as? Int ?? 3 {
        didSet { UserDefaults.standard.set(countdownDuration, forKey: "countdownDuration") }
    }

    private let screenService = ScreenCaptureService()
    private let cameraService = CameraCaptureService()
    private var activeCaptureID: UUID?
    private var capturedScreen: CGImage?
    private var capturedReaction: CGImage?
    private let history = CaptureHistoryStore()

    private init() {
        captures = history.loadRecords()
        if let latest = captures.first, let assets = try? history.loadAssets(for: latest) {
            selectedCaptureID = latest.id
            cameraCorner = latest.cameraCorner
            capturedScreen = assets.screen
            capturedReaction = assets.reaction
            compositeImage = assets.composite
            screenPreviewImage = NSImage(cgImage: assets.screen, size: NSSize(width: assets.screen.width, height: assets.screen.height))
            reactionPreviewImage = NSImage(cgImage: assets.reaction, size: NSSize(width: assets.reaction.width, height: assets.reaction.height))
        }
    }

    func startCapture() async {
        guard !isWorking else { return }
        let captureID = UUID()
        activeCaptureID = captureID
        isWorking = true
        statusText = "Checking permissions…"
        PreviewWindowController.shared.show(model: self, activate: false)

        do {
            try await cameraService.prepare()
            guard isActive(captureID) else {
                await cameraService.stop()
                return
            }
            for value in stride(from: countdownDuration, through: 1, by: -1) {
                countdown = value
                try await Task.sleep(for: .seconds(1))
                guard isActive(captureID) else {
                    await cameraService.stop()
                    return
                }
            }

            countdown = nil
            statusText = "Capturing your moment…"
            PreviewWindowController.shared.hideForCapture()
            // Let AppKit finish removing the countdown window before the screen request.
            try await Task.sleep(for: .milliseconds(400))
            guard isActive(captureID) else {
                await cameraService.stop()
                return
            }

            async let screen = screenService.captureMainDisplay()
            async let reaction = cameraService.capturePhoto()
            let (screenImage, reactionImage) = try await (screen, reaction)
            await cameraService.stop()
            guard isActive(captureID) else { return }
            capturedScreen = screenImage
            capturedReaction = reactionImage
            screenPreviewImage = NSImage(cgImage: screenImage, size: NSSize(width: screenImage.width, height: screenImage.height))
            reactionPreviewImage = NSImage(cgImage: reactionImage, size: NSSize(width: reactionImage.width, height: reactionImage.height))
            try updateComposite()
            let record = try history.save(
                screen: screenImage,
                reaction: reactionImage,
                composite: compositeImage,
                corner: cameraCorner
            )
            captures.insert(record, at: 0)
            selectedCaptureID = record.id
            isWorking = false
            activeCaptureID = nil
            PreviewWindowController.shared.show(model: self)
        } catch {
            await cameraService.stop()
            guard isActive(captureID) else { return }
            countdown = nil
            isWorking = false
            activeCaptureID = nil
            errorMessage = error.localizedDescription
            isShowingError = true
            PreviewWindowController.shared.show(model: self)
        }
    }

    func cancelCapture() {
        guard isWorking else { return }
        activeCaptureID = nil
        countdown = nil
        isWorking = false
        statusText = "Capture cancelled"
        PreviewWindowController.shared.show(model: self)
    }

    func moveCamera(to point: CGPoint, in previewSize: CGSize) {
        guard previewSize.width > 0, previewSize.height > 0 else { return }
        let horizontal = point.x < previewSize.width / 2 ? 0 : 1
        let vertical = point.y < previewSize.height / 2 ? 0 : 1
        let corner: CameraCorner
        switch (horizontal, vertical) {
        case (0, 0): corner = .topLeft
        case (1, 0): corner = .topRight
        case (0, 1): corner = .bottomLeft
        default: corner = .bottomRight
        }
        guard corner != cameraCorner else { return }
        cameraCorner = corner
        do {
            try updateComposite()
            updateSelectedRecord()
        } catch {
            show(error)
        }
    }

    func selectCapture(_ id: UUID) {
        guard id != selectedCaptureID, let record = captures.first(where: { $0.id == id }) else { return }
        do {
            let assets = try history.loadAssets(for: record)
            capturedScreen = assets.screen
            capturedReaction = assets.reaction
            screenPreviewImage = NSImage(cgImage: assets.screen, size: NSSize(width: assets.screen.width, height: assets.screen.height))
            reactionPreviewImage = NSImage(cgImage: assets.reaction, size: NSSize(width: assets.reaction.width, height: assets.reaction.height))
            cameraCorner = record.cameraCorner
            compositeImage = assets.composite
            selectedCaptureID = id
        } catch {
            show(error)
        }
    }

    func deleteSelectedCapture() {
        guard let selectedCaptureID, let index = captures.firstIndex(where: { $0.id == selectedCaptureID }) else { return }
        do {
            try history.delete(captures[index])
            captures.remove(at: index)
            if let next = captures.indices.contains(index) ? captures[index] : captures.last {
                selectCapture(next.id)
            } else {
                self.selectedCaptureID = nil
                compositeImage = nil
                capturedScreen = nil
                capturedReaction = nil
                screenPreviewImage = nil
                reactionPreviewImage = nil
            }
        } catch {
            show(error)
        }
    }

    func clearHistory() {
        do {
            try history.clear()
            captures = []
            selectedCaptureID = nil
            compositeImage = nil
            capturedScreen = nil
            capturedReaction = nil
            screenPreviewImage = nil
            reactionPreviewImage = nil
        } catch {
            show(error)
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

    private func isActive(_ captureID: UUID) -> Bool {
        activeCaptureID == captureID
    }

    private func updateComposite() throws {
        guard let capturedScreen, let capturedReaction else { return }
        compositeImage = try ImageComposer.compose(
            screen: capturedScreen,
            reaction: capturedReaction,
            corner: cameraCorner
        )
    }

    private func updateSelectedRecord() {
        guard let selectedCaptureID,
              let index = captures.firstIndex(where: { $0.id == selectedCaptureID }),
              let compositeImage else { return }
        do {
            try history.update(captures[index], composite: compositeImage, corner: cameraCorner)
            captures[index].cameraCorner = cameraCorner
            captures[index].thumbnail = compositeImage
        } catch {
            show(error)
        }
    }

    private static var fileTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}

@MainActor
private final class CaptureHistoryStore {
    private struct Metadata: Codable {
        let id: UUID
        let createdAt: Date
        let corner: CameraCorner
    }

    private let fileManager = FileManager.default
    private let directory: URL

    init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = appSupport.appendingPathComponent("RealMac/Captures", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func loadRecords() -> [CaptureRecord] {
        let urls = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url.appendingPathComponent("metadata.json")),
                  let metadata = try? JSONDecoder().decode(Metadata.self, from: data),
                  let thumbnail = NSImage(contentsOf: url.appendingPathComponent("composite.jpg")) else { return nil }
            return CaptureRecord(id: metadata.id, createdAt: metadata.createdAt, cameraCorner: metadata.corner, thumbnail: thumbnail)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func save(screen: CGImage, reaction: CGImage, composite: NSImage?, corner: CameraCorner) throws -> CaptureRecord {
        guard let composite else { throw CaptureError.photoUnavailable }
        let id = UUID()
        let createdAt = Date()
        let captureDirectory = directory.appendingPathComponent(id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        try ImageComposer.jpegData(for: screen).write(to: captureDirectory.appendingPathComponent("screen.jpg"), options: .atomic)
        try ImageComposer.jpegData(for: reaction).write(to: captureDirectory.appendingPathComponent("reaction.jpg"), options: .atomic)
        try ImageComposer.jpegData(for: composite).write(to: captureDirectory.appendingPathComponent("composite.jpg"), options: .atomic)
        try writeMetadata(Metadata(id: id, createdAt: createdAt, corner: corner), to: captureDirectory)
        return CaptureRecord(id: id, createdAt: createdAt, cameraCorner: corner, thumbnail: composite)
    }

    func loadAssets(for record: CaptureRecord) throws -> (screen: CGImage, reaction: CGImage, composite: NSImage) {
        let captureDirectory = directory.appendingPathComponent(record.id.uuidString, isDirectory: true)
        guard let screen = NSImage(contentsOf: captureDirectory.appendingPathComponent("screen.jpg"))?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let reaction = NSImage(contentsOf: captureDirectory.appendingPathComponent("reaction.jpg"))?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let composite = NSImage(contentsOf: captureDirectory.appendingPathComponent("composite.jpg")) else {
            throw CaptureError.photoUnavailable
        }
        return (screen, reaction, composite)
    }

    func update(_ record: CaptureRecord, composite: NSImage, corner: CameraCorner) throws {
        let captureDirectory = directory.appendingPathComponent(record.id.uuidString, isDirectory: true)
        try ImageComposer.jpegData(for: composite).write(to: captureDirectory.appendingPathComponent("composite.jpg"), options: .atomic)
        try writeMetadata(Metadata(id: record.id, createdAt: record.createdAt, corner: corner), to: captureDirectory)
    }

    func delete(_ record: CaptureRecord) throws {
        try fileManager.removeItem(at: directory.appendingPathComponent(record.id.uuidString, isDirectory: true))
    }

    func clear() throws {
        let urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for url in urls { try fileManager.removeItem(at: url) }
    }

    private func writeMetadata(_ metadata: Metadata, to directory: URL) throws {
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: directory.appendingPathComponent("metadata.json"), options: .atomic)
    }
}
