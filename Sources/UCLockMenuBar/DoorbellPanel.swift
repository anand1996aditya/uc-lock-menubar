import AppKit
import SwiftUI

@MainActor
final class DoorbellCardModel: ObservableObject {
    @Published var activity: Activity
    init(activity: Activity) { self.activity = activity }
}

@MainActor
final class DoorbellPanelController {
    private var panel: NSPanel?
    private var cardModel: DoorbellCardModel?
    private var closeWork: DispatchWorkItem?

    func show(activity: Activity, onOpen: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        close()
        let model = DoorbellCardModel(activity: activity)
        cardModel = model
        let card = DoorbellCardView(
            model: model,
            onOpen: { [weak self] in
                self?.close()
                onOpen()
            },
            onDismiss: { [weak self] in
                self?.close()
                onDismiss()
            }
        )
        let hosting = NSHostingController(rootView: card)
        let size = NSSize(width: 372, height: 470)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentViewController = hosting
        position(panel)
        panel.orderFrontRegardless()
        self.panel = panel

        let work = DispatchWorkItem { [weak self] in self?.close() }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
    }

    func updatePhoto(_ url: URL, for activity: Activity) {
        guard let model = cardModel, model.activity.id == activity.id else { return }
        model.activity = model.activity.withImageURL(url)
    }

    func close() {
        closeWork?.cancel()
        closeWork = nil
        panel?.orderOut(nil)
        panel = nil
        cardModel = nil
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = panel.frame
        let x = screen.visibleFrame.maxX - frame.width - 14
        let y = screen.visibleFrame.maxY - frame.height - 10
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

struct DoorbellCardView: View {
    @ObservedObject var model: DoorbellCardModel
    let onOpen: () -> Void
    let onDismiss: () -> Void

    private var activity: Activity { model.activity }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                Text("Someone is at your door")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(activity.timeText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            photo
                .frame(height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 14)

            VStack(alignment: .leading, spacing: 4) {
                Text(activity.title)
                    .font(.system(size: 13, weight: .medium))
                Text("Visitor photo captured by the doorbell. The door stays locked until you unlock it.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Text("Dismiss")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)
                Spacer()
                Text("Open UC Lock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.accentColor, in: Capsule())
                    .contentShape(Capsule())
                    .onTapGesture(perform: onOpen)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 372, height: 470)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var photo: some View {
        if let url = activity.imageURL, let cached = ImageCache.shared.image(for: url) {
            Image(nsImage: cached).resizable().scaledToFill()
        } else if let url = activity.imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: loadingPlaceholder
                }
            }
        } else {
            loadingPlaceholder
        }
    }

    private var loadingPlaceholder: some View {
        ZStack {
            Color.gray.opacity(0.13)
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for the visitor photo")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
