import AppKit
import SwiftUI

// MARK: - Geometry

/// Where the notch is (or where a floating pill goes on Macs without one).
struct NotchGeometry: Equatable {
    var screenFrame: CGRect
    var hasNotch: Bool
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var menuBarHeight: CGFloat

    static func current() -> NotchGeometry {
        // The first screen is the one with the menu bar.
        guard let screen = NSScreen.screens.first else {
            return NotchGeometry(screenFrame: .zero, hasNotch: false, notchWidth: 0, notchHeight: 0, menuBarHeight: 24)
        }
        let top = screen.safeAreaInsets.top
        var notchWidth: CGFloat = 0
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = screen.frame.width - left.width - right.width
        }
        let menuBar = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        return NotchGeometry(
            screenFrame: screen.frame,
            hasNotch: top > 0 && notchWidth > 0,
            notchWidth: notchWidth,
            notchHeight: top,
            menuBarHeight: menuBar
        )
    }
}

// MARK: - Model

struct OverlayButton: Identifiable {
    let id = UUID()
    let title: String
    let isPrimary: Bool
    let action: () -> Void
}

@MainActor
final class OverlayModel: ObservableObject {
    /// The black tab has grown out of the notch.
    @Published var expanded = false
    /// The speech bubble is visible (appears just after the tab).
    @Published var bubbleShown = false
    @Published var primary: Utterance?
    @Published var secondary: Utterance?
    @Published var buttons: [OverlayButton] = []

    /// Transparent window; only the tab and bubble are drawn, clicks elsewhere pass through.
    static let panelSize = CGSize(width: 820, height: 380)
}

// MARK: - Panel

/// A borderless, non-activating panel that sits over the menu bar and never
/// steals focus from the app you're working in.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // Allow the panel to sit over the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Lets the bubble's buttons respond to the first click without activating the app.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Shapes

/// Rounded rectangle with separate top and bottom corner radii
/// (square top so the tab hangs flush from the notch or screen edge).
struct IslandShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let limit = min(rect.width, rect.height) / 2
        let t = min(topRadius, limit)
        let b = min(bottomRadius, limit)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + t), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - b, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - b), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// The little comic tail on the bubble's left edge, pointing up at the character.
struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + 6, y: rect.minY + 28))
        p.addQuadCurve(to: CGPoint(x: rect.minX - 17, y: rect.minY + 16),
                       control: CGPoint(x: rect.minX - 5, y: rect.minY + 30))
        p.addQuadCurve(to: CGPoint(x: rect.minX + 6, y: rect.minY + 54),
                       control: CGPoint(x: rect.minX - 6, y: rect.minY + 44))
        p.closeSubpath()
        return p
    }
}

// MARK: - Views

struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    let geo: NotchGeometry

    private let tabShape = IslandShape(topRadius: 0, bottomRadius: 30)
    private let bubbleWidth: CGFloat = 300
    private let faceSize: CGFloat = 132

    /// Space at the top of the tab hidden behind the notch (or a small margin without one).
    private var topInset: CGFloat { geo.hasNotch ? geo.notchHeight : 10 }

    /// Who is in the tab right now: one character, or two for tag-team lines.
    private var speakers: [FamilyMember] {
        var list: [FamilyMember] = []
        for u in [model.primary, model.secondary].compactMap({ $0 }) where !list.contains(u.character) {
            list.append(u.character)
        }
        return list
    }

    private var tabWidth: CGFloat {
        let base = max(geo.hasNotch ? geo.notchWidth : 0, 196)
        return speakers.count > 1 ? base + 110 : base
    }
    private var tabHeight: CGFloat { topInset + 122 }
    private var collapsedWidth: CGFloat { geo.hasNotch ? geo.notchWidth : tabWidth }
    private var collapsedHeight: CGFloat { geo.hasNotch ? geo.notchHeight : 0 }

    var body: some View {
        let panelWidth = OverlayModel.panelSize.width
        let tabX = panelWidth / 2 - tabWidth / 2

        ZStack(alignment: .topLeading) {
            tab
                .frame(width: panelWidth, alignment: .top)

            if model.bubbleShown {
                bubble
                    .offset(x: tabX + tabWidth - 46, y: topInset + 34)
                    .transition(.scale(scale: 0.4, anchor: .topLeading).combined(with: .opacity))
            }
        }
        .frame(width: panelWidth, height: OverlayModel.panelSize.height, alignment: .topLeading)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: model.expanded)
        .animation(.spring(response: 0.34, dampingFraction: 0.7), value: model.bubbleShown)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.secondary)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.primary)
    }

    // The black tab hanging from the notch, holding only the character(s).
    private var tab: some View {
        ZStack(alignment: .bottom) {
            tabShape.fill(Color.black)
            if model.expanded {
                HStack(alignment: .bottom, spacing: -16) {
                    ForEach(speakers, id: \.self) { member in
                        CharacterFace(member: member, mood: mood(for: member))
                            .frame(width: faceSize, height: faceSize)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .offset(y: 6) // hands rest on the bottom edge
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(width: model.expanded ? tabWidth : collapsedWidth,
               height: model.expanded ? tabHeight : collapsedHeight)
        .clipShape(tabShape)
        .shadow(color: .black.opacity(model.expanded ? 0.22 : 0), radius: 12, y: 4)
    }

    // The white speech bubble beside the tab.
    private var bubble: some View {
        let twoSpeakers = model.secondary != nil
        return VStack(alignment: .leading, spacing: 14) {
            if let p = model.primary { line(p, showName: twoSpeakers) }
            if let s = model.secondary {
                line(s, showName: true)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if !model.buttons.isEmpty {
                HStack(spacing: 8) {
                    ForEach(model.buttons) { b in
                        Button(b.title, action: b.action)
                            .buttonStyle(BubbleButtonStyle(isPrimary: b.isPrimary))
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(width: bubbleWidth, alignment: .leading)
        .background(
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.white)
                BubbleTail().fill(Color.white)
            }
        )
        .compositingGroup()
        .shadow(color: .black.opacity(0.13), radius: 18, y: 8)
    }

    private func line(_ u: Utterance, showName: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if showName {
                Text(u.character.displayName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(Color(white: 0.55))
            }
            Text(u.text)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Color(white: 0.07))
                .fixedSize(horizontal: false, vertical: true)
            if let sub = u.subtitle {
                Text(sub)
                    .font(.system(size: 14.5))
                    .foregroundColor(Color(white: 0.43))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func mood(for member: FamilyMember) -> Mood {
        if let s = model.secondary, s.character == member { return s.mood }
        return model.primary?.mood ?? .neutral
    }
}

struct BubbleButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundColor(isPrimary ? .white : Color(white: 0.15))
            .background(Capsule().fill(isPrimary ? Color(white: 0.08) : Color(white: 0.93)))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Controller

@MainActor
final class OverlayController {
    let model = OverlayModel()

    private var panel: NotchPanel?
    private var hostingView: FirstClickHostingView<OverlayView>?
    private var geo = NotchGeometry.current()
    private var timeoutTask: Task<Void, Never>?
    private var secondaryTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    private(set) var isShowing = false

    func show(primary: Utterance,
              secondary: Utterance?,
              buttons: [OverlayButton],
              timeout: TimeInterval,
              onTimeout: @escaping () -> Void) {
        cancelTasks()
        preparePanel()

        model.expanded = false
        model.bubbleShown = false
        model.primary = primary
        model.secondary = nil
        model.buttons = buttons
        isShowing = true
        panel?.orderFrontRegardless()

        // The tab grows out of the notch, then the bubble pops out beside it.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            self.model.expanded = true
            try? await Task.sleep(for: .milliseconds(240))
            if self.model.expanded { self.model.bubbleShown = true }
        }

        if let secondary {
            secondaryTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.8))
                guard !Task.isCancelled else { return }
                self.model.secondary = secondary
            }
        }

        timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self.hide()
            onTimeout()
        }
    }

    /// Replaces the bubble with a reaction line, then tucks back into the notch.
    func react(_ utterance: Utterance, hideAfter: TimeInterval) {
        cancelTasks()
        model.buttons = []
        model.secondary = nil
        model.primary = utterance
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(hideAfter))
            guard !Task.isCancelled else { return }
            self.hide()
        }
    }

    func hide() {
        cancelTasks()
        model.bubbleShown = false
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self.model.expanded = false
            try? await Task.sleep(for: .milliseconds(480))
            guard !Task.isCancelled, !self.model.expanded else { return }
            self.panel?.orderOut(nil)
            self.model.primary = nil
            self.model.secondary = nil
            self.model.buttons = []
            self.isShowing = false
        }
    }

    private func cancelTasks() {
        timeoutTask?.cancel()
        secondaryTask?.cancel()
        hideTask?.cancel()
        timeoutTask = nil
        secondaryTask = nil
        hideTask = nil
    }

    private func preparePanel() {
        geo = NotchGeometry.current()
        let size = OverlayModel.panelSize
        let frame = NSRect(x: geo.screenFrame.midX - size.width / 2,
                           y: geo.screenFrame.maxY - size.height,
                           width: size.width,
                           height: size.height)

        if panel == nil {
            let p = NotchPanel(contentRect: frame)
            let host = FirstClickHostingView(rootView: OverlayView(model: model, geo: geo))
            host.frame = NSRect(origin: .zero, size: size)
            p.contentView = host
            panel = p
            hostingView = host
        } else {
            hostingView?.rootView = OverlayView(model: model, geo: geo)
        }
        panel?.setFrame(frame, display: false)
    }
}
