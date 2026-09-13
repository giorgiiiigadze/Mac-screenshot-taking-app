import AppKit
import AVFoundation
import ImageIO
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case cameraPermissionDenied
    case cameraUnavailable
    case screenUnavailable
    case photoUnavailable

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied:
            "Camera access is required. Enable RealMac in System Settings › Privacy & Security › Camera."
        case .cameraUnavailable:
            "No available camera was found."
        case .screenUnavailable:
            "Screen Recording access is required. Enable RealMac in System Settings › Privacy & Security › Screen & System Audio Recording."
        case .photoUnavailable:
            "The camera did not return a photo. Please try again."
        }
    }
}

final class ScreenCaptureService: Sendable {
    func captureMainDisplay() async throws -> CGImage {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.screenUnavailable
        }

        guard let display = selectedDisplay(from: content.displays) else {
            throw CaptureError.screenUnavailable
        }
        // Excluding our process makes the result safe even if AppKit has not yet
        // completed the window-ordering update for the countdown UI.
        let ownWindows = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.showsCursor = true
        configuration.capturesAudio = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    private func selectedDisplay(from displays: [SCDisplay]) -> SCDisplay? {
        guard let screen = NSScreen.main,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return displays.first
        }
        return displays.first { $0.displayID == number.uint32Value } ?? displays.first
    }
}

final class CameraCaptureService: @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "app.realmac.camera")
    private var delegate: PhotoCaptureDelegate?
    private var isPrepared = false

    func prepare() async throws {
        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: authorized = true
        case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
        default: authorized = false
        }
        guard authorized else { throw CaptureError.cameraPermissionDenied }

        if !isPrepared {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    do {
                        try configureSession()
                        isPrepared = true
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }

        if !session.isRunning {
            await withCheckedContinuation { continuation in
                queue.async { [self] in
                    session.startRunning()
                    continuation.resume()
                }
            }
            // A still-photo request issued in the first few hardware frames can be
            // black on built-in and USB cameras. This is only a brief warm-up; the
            // user still gets an immediate capture with no visible countdown.
            try await Task.sleep(for: .milliseconds(450))
        }
    }

    func capturePhoto() async throws -> CGImage {
        try await prepare()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                let delegate = PhotoCaptureDelegate { [weak self] result in
                    self?.delegate = nil
                    continuation.resume(with: result)
                }
                self.delegate = delegate
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                output.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    func stop() async {
        guard session.isRunning else { return }
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if session.isRunning {
                    session.stopRunning()
                }
                continuation.resume()
            }
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        guard let camera = discovery.devices.first(where: { $0.position == .front }) ?? discovery.devices.first else {
            throw CaptureError.cameraUnavailable
        }
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw CaptureError.cameraUnavailable
        }
        session.addInput(input)
        session.addOutput(output)
    }
}

private nonisolated final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let completion: (Result<CGImage, Error>) -> Void

    init(completion: @escaping (Result<CGImage, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            completion(.failure(error))
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096
              ] as CFDictionary) else {
            completion(.failure(CaptureError.photoUnavailable))
            return
        }
        completion(.success(image))
    }
}
