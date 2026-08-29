import SwiftUI

struct ContentView: View {
    @ObservedObject var model: CaptureModel

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()

            if let image = model.compositeImage {
                preview(image)
            } else {
                emptyState
            }

            if model.isWorking { captureOverlay }
        }
        .frame(minWidth: 720, minHeight: 500)
        .alert("Capture failed", isPresented: $model.isShowingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(model.errorMessage)
        }
    }

    private func preview(_ image: NSImage) -> some View {
        VStack(spacing: 16) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 20, y: 8)
                .padding(.horizontal, 24)
                .padding(.top, 24)

            HStack(spacing: 12) {
                Button { Task { await model.startCapture() } } label: {
                    Label("Retake", systemImage: "arrow.clockwise")
                }
                Spacer()
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
                .foregroundStyle(.secondary)
            Text("Capture your Mac moment").font(.title2.bold())
            Text("Your screen becomes the main image, with your reaction in the corner.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button { Task { await model.startCapture() } } label: {
                Label("Capture Now", systemImage: "camera.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text("or press ⌘⇧B anywhere")
                .font(.caption)
                .foregroundStyle(.tertiary)
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
                } else {
                    ProgressView().controlSize(.large).tint(.white)
                    Text(model.statusText).font(.title3.weight(.semibold))
                }
            }
            .foregroundStyle(.white)
        }
        .animation(.snappy, value: model.countdown)
    }
}
