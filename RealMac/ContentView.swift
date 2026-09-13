import SwiftUI

struct ContentView: View {
    @ObservedObject var model: CaptureModel

    var body: some View {
        NavigationSplitView {
            historySidebar
        } detail: {
            ZStack {
                Color.black.ignoresSafeArea()

                if let image = model.compositeImage {
                    preview(image)
                } else {
                    emptyState
                }

                if model.isWorking { captureOverlay }
            }
        }
        .frame(minWidth: 720, minHeight: 500)
        .alert("Capture failed", isPresented: $model.isShowingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(model.errorMessage)
        }
    }

    private var historySidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent captures").font(.headline)
                Spacer()
                if !model.captures.isEmpty {
                    Button("Clear") { model.clearHistory() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)

            if model.captures.isEmpty {
                ContentUnavailableView("No captures yet", systemImage: "photo.on.rectangle.angled")
                    .font(.caption)
            } else {
                List(model.captures) { capture in
                    Button {
                        model.selectCapture(capture.id)
                    } label: {
                        HStack(spacing: 10) {
                            Image(nsImage: capture.thumbnail)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 54, height: 38)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(capture.title).font(.subheadline.weight(.medium))
                                Text(capture.cameraCorner.label).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                    .listRowBackground(model.selectedCaptureID == capture.id ? Color.accentColor.opacity(0.16) : Color.clear)
                }
                .listStyle(.sidebar)
            }

            Divider()
            Button { Task { await model.startCapture() } } label: {
                Label("New Capture", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isWorking)
            .padding(12)
        }
        .frame(minWidth: 220)
    }

    private func preview(_ image: NSImage) -> some View {
        VStack(spacing: 16) {
            if let screen = model.screenPreviewImage, let reaction = model.reactionPreviewImage {
                DraggableCapturePreview(
                    screen: screen,
                    reaction: reaction,
                    corner: model.cameraCorner,
                    snapCamera: model.moveCamera(to:in:)
                )
                .padding(.horizontal, 24)
                .padding(.top, 24)
            } else {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.22), radius: 20, y: 8)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
            }

            Text("Drag the camera tile to any corner · \(model.cameraCorner.label)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))

            HStack(spacing: 12) {
                Button { Task { await model.startCapture() } } label: {
                    Label("Retake", systemImage: "arrow.clockwise")
                }
                Spacer()
                Button(role: .destructive) { model.deleteSelectedCapture() } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button { model.share() } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Button { model.save() } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "macbook.and.iphone")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.white.opacity(0.62))
            Text("Capture your Mac moment").font(.title2.bold()).foregroundStyle(.white)
            Text("Your screen becomes the main image, with your reaction in the corner. Choose a timer, then capture whenever the moment is right.")
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button { Task { await model.startCapture() } } label: {
                Label("Capture Now", systemImage: "camera.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text("Use the menu bar to set a timer, or press ⌘⇧B anywhere")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(40)
    }

    private var captureOverlay: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.58)).ignoresSafeArea()
            VStack(spacing: 16) {
                if let countdown = model.countdown {
                    Text("\(countdown)")
                        .font(.system(size: 112, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("Look at the camera").font(.title3.weight(.semibold))
                    Button("Cancel") { model.cancelCapture() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                } else {
                    ProgressView().controlSize(.large).tint(.white)
                    Text(model.statusText).font(.title3.weight(.semibold))
                    Button("Cancel") { model.cancelCapture() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
            }
            .foregroundStyle(.white)
        }
        .animation(.snappy, value: model.countdown)
    }
}

private struct DraggableCapturePreview: View {
    let screen: NSImage
    let reaction: NSImage
    let corner: CameraCorner
    let snapCamera: (CGPoint, CGSize) -> Void

    @State private var dragPosition: CGPoint?
    @State private var dragStart: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let screenRect = aspectFitRect(for: screen.size, in: proxy.size)
            let tileSize = CGSize(width: screenRect.width * 0.25, height: screenRect.width * 0.25 * 4 / 3)
            let margin = max(12, screenRect.width * 0.025)
            let restingPosition = tileCenter(for: corner, in: screenRect, tileSize: tileSize, margin: margin)
            let position = dragPosition ?? restingPosition

            ZStack(alignment: .topLeading) {
                Image(nsImage: screen)
                    .resizable()
                    .scaledToFit()
                    .frame(width: screenRect.width, height: screenRect.height)
                    .position(x: screenRect.midX, y: screenRect.midY)

                Image(nsImage: reaction)
                    .resizable()
                    .scaledToFill()
                    .frame(width: tileSize.width, height: tileSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: tileSize.width * 0.08, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: tileSize.width * 0.08, style: .continuous)
                            .stroke(.white, lineWidth: 3)
                    }
                    .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
                    .position(position)
                    .gesture(dragGesture(in: screenRect, tileSize: tileSize, restingPosition: restingPosition))
                    .animation(.spring(response: 0.32, dampingFraction: 0.78), value: dragPosition == nil ? corner : nil)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.22), radius: 20, y: 8)
        }
        .aspectRatio(screen.size.width / max(screen.size.height, 1), contentMode: .fit)
    }

    private func dragGesture(in screenRect: CGRect, tileSize: CGSize, restingPosition: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = dragStart ?? restingPosition
                if dragStart == nil { dragStart = start }
                dragPosition = clamped(
                    CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height),
                    in: screenRect,
                    tileSize: tileSize
                )
            }
            .onEnded { value in
                let start = dragStart ?? restingPosition
                let finalPosition = clamped(
                    CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height),
                    in: screenRect,
                    tileSize: tileSize
                )
                let relativePosition = CGPoint(x: finalPosition.x - screenRect.minX, y: finalPosition.y - screenRect.minY)
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    snapCamera(relativePosition, screenRect.size)
                    dragPosition = nil
                    dragStart = nil
                }
            }
    }

    private func tileCenter(for corner: CameraCorner, in rect: CGRect, tileSize: CGSize, margin: CGFloat) -> CGPoint {
        let left = rect.minX + margin + tileSize.width / 2
        let right = rect.maxX - margin - tileSize.width / 2
        let top = rect.minY + margin + tileSize.height / 2
        let bottom = rect.maxY - margin - tileSize.height / 2
        return switch corner {
        case .topLeft: CGPoint(x: left, y: top)
        case .topRight: CGPoint(x: right, y: top)
        case .bottomLeft: CGPoint(x: left, y: bottom)
        case .bottomRight: CGPoint(x: right, y: bottom)
        }
    }

    private func clamped(_ point: CGPoint, in rect: CGRect, tileSize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX + tileSize.width / 2), rect.maxX - tileSize.width / 2),
            y: min(max(point.y, rect.minY + tileSize.height / 2), rect.maxY - tileSize.height / 2)
        )
    }

    private func aspectFitRect(for imageSize: CGSize, in size: CGSize) -> CGRect {
        let scale = min(size.width / max(imageSize.width, 1), size.height / max(imageSize.height, 1))
        let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
    }
}
