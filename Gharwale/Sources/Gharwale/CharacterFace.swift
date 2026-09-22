import AppKit
import SwiftUI

/// Loads character art: Characters/<member>-<mood>-<n>.png
/// (e.g. maa-happy-1.png, maa-happy-2.png). Several images per mood are
/// picked at random for variety. Missing art falls back to the drawn faces.
enum CharacterArt {
    private static var cache: [String: [NSImage]] = [:]

    static func images(for member: FamilyMember, mood: Mood) -> [NSImage] {
        let key = "\(member.rawValue)-\(mood.rawValue)"
        if let hit = cache[key] { return hit }

        var found: [NSImage] = []
        for dir in searchDirectories() {
            var n = 1
            while let img = NSImage(contentsOf: dir.appendingPathComponent("\(key)-\(n).png")) {
                found.append(img)
                n += 1
            }
            if !found.isEmpty { break }
        }
        cache[key] = found
        return found
    }

    /// User art in Application Support wins, then the app bundle, then the
    /// source tree (for `swift run`).
    private static func searchDirectories() -> [URL] {
        var dirs = [AppPaths.supportDir.appendingPathComponent("Characters", isDirectory: true)]
        if let res = Bundle.main.resourceURL {
            dirs.append(res.appendingPathComponent("Characters", isDirectory: true))
        }
        dirs.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Characters", isDirectory: true))
        return dirs
    }
}

/// Maa or Papa in a given mood, with a small head-bob when they appear or react.
struct CharacterFace: View {
    let member: FamilyMember
    let mood: Mood

    @State private var tilt: Double = 0
    @State private var seed = Int.random(in: 0..<1000)

    var body: some View {
        face
            .rotationEffect(.degrees(tilt), anchor: .bottom)
            .task(id: "\(member.rawValue)-\(mood.rawValue)") {
                for angle in [5.0, -4.0, 2.0, 0.0] {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { tilt = angle }
                    try? await Task.sleep(nanoseconds: 150_000_000)
                }
            }
            .accessibilityLabel("\(member.displayName), \(mood.rawValue)")
    }

    @ViewBuilder
    private var face: some View {
        let art = CharacterArt.images(for: member, mood: mood)
        if !art.isEmpty {
            Image(nsImage: art[seed % art.count])
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Canvas { ctx, size in
                ctx.scaleBy(x: size.width / 100, y: size.height / 100)
                FaceDrawing(member: member, mood: mood).draw(in: &ctx)
            }
        }
    }
}

private struct FaceDrawing {
    let member: FamilyMember
    let mood: Mood

    private let skin = Color(red: 0.80, green: 0.58, blue: 0.42)
    private let hair = Color(white: 0.13)
    private let ink = Color(red: 0.22, green: 0.13, blue: 0.10)
    private let lip = Color(red: 0.62, green: 0.20, blue: 0.20)

    private var eyeY: CGFloat { member == .maa ? 56 : 55 }
    private var mouthY: CGFloat { member == .maa ? 74 : 79 }
    private let leftEyeX: CGFloat = 39
    private let rightEyeX: CGFloat = 61

    func draw(in ctx: inout GraphicsContext) {
        switch member {
        case .maa: drawMaa(&ctx)
        case .papa: drawPapa(&ctx)
        }
        drawEyes(&ctx)
        drawBrows(&ctx)
        if member == .papa { drawGlasses(&ctx); drawMustache(&ctx) }
        drawMouth(&ctx)
        if mood == .proud || mood == .happy { drawBlush(&ctx) }
    }

    // MARK: Heads

    private func drawMaa(_ ctx: inout GraphicsContext) {
        // Bun and hair behind the face.
        ctx.fill(Path(ellipseIn: CGRect(x: 38, y: 2, width: 24, height: 20)), with: .color(hair))
        ctx.fill(Path(ellipseIn: CGRect(x: 15, y: 13, width: 70, height: 62)), with: .color(hair))
        // Face.
        ctx.fill(Path(ellipseIn: CGRect(x: 20, y: 22, width: 60, height: 68)), with: .color(skin))
        // Centre-parted fringe.
        var fringe = Path()
        fringe.move(to: CGPoint(x: 20, y: 46))
        fringe.addQuadCurve(to: CGPoint(x: 50, y: 25), control: CGPoint(x: 24, y: 24))
        fringe.addQuadCurve(to: CGPoint(x: 80, y: 46), control: CGPoint(x: 76, y: 24))
        fringe.addQuadCurve(to: CGPoint(x: 50, y: 20), control: CGPoint(x: 78, y: 16))
        fringe.addQuadCurve(to: CGPoint(x: 20, y: 46), control: CGPoint(x: 22, y: 16))
        ctx.fill(fringe, with: .color(hair))
        // Bindi and earrings.
        ctx.fill(Path(ellipseIn: CGRect(x: 47.5, y: 43, width: 5, height: 5)), with: .color(Color(red: 0.85, green: 0.12, blue: 0.18)))
        let gold = Color(red: 0.93, green: 0.74, blue: 0.25)
        ctx.fill(Path(ellipseIn: CGRect(x: 15, y: 62, width: 7, height: 7)), with: .color(gold))
        ctx.fill(Path(ellipseIn: CGRect(x: 78, y: 62, width: 7, height: 7)), with: .color(gold))
    }

    private func drawPapa(_ ctx: inout GraphicsContext) {
        // Ears.
        ctx.fill(Path(ellipseIn: CGRect(x: 15, y: 50, width: 10, height: 14)), with: .color(skin))
        ctx.fill(Path(ellipseIn: CGRect(x: 75, y: 50, width: 10, height: 14)), with: .color(skin))
        // Face.
        ctx.fill(Path(ellipseIn: CGRect(x: 20, y: 18, width: 60, height: 72)), with: .color(skin))
        // Short hair with grey sides.
        var top = Path()
        top.move(to: CGPoint(x: 21, y: 44))
        top.addQuadCurve(to: CGPoint(x: 79, y: 44), control: CGPoint(x: 50, y: 0))
        top.addQuadCurve(to: CGPoint(x: 21, y: 44), control: CGPoint(x: 50, y: 26))
        ctx.fill(top, with: .color(hair))
        let grey = Color(white: 0.62)
        ctx.fill(Path(ellipseIn: CGRect(x: 19, y: 38, width: 6, height: 12)), with: .color(grey))
        ctx.fill(Path(ellipseIn: CGRect(x: 75, y: 38, width: 6, height: 12)), with: .color(grey))
    }

    // MARK: Features

    private func drawEyes(_ ctx: inout GraphicsContext) {
        for x in [leftEyeX, rightEyeX] {
            switch mood {
            case .happy, .proud:
                var arc = Path()
                arc.move(to: CGPoint(x: x - 4.5, y: eyeY + 1.5))
                arc.addQuadCurve(to: CGPoint(x: x + 4.5, y: eyeY + 1.5), control: CGPoint(x: x, y: eyeY - 4.5))
                ctx.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            default:
                ctx.fill(Path(ellipseIn: CGRect(x: x - 3.3, y: eyeY - 3.3, width: 6.6, height: 6.6)), with: .color(ink))
            }
        }
    }

    private func drawBrows(_ ctx: inout GraphicsContext) {
        let y = eyeY - 9
        let lineWidth: CGFloat = member == .papa ? 3 : 2
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        let sides: [(CGFloat, CGFloat)] = [(leftEyeX, -1), (rightEyeX, 1)]
        for (x, side) in sides {
            var brow = Path()
            let outer = CGPoint(x: x + 6 * side, y: y)
            let inner = CGPoint(x: x - 5 * side, y: y)
            switch mood {
            case .stern:
                brow.move(to: CGPoint(x: outer.x, y: y - 2))
                brow.addLine(to: CGPoint(x: inner.x, y: y + 3))
            case .worried:
                brow.move(to: CGPoint(x: outer.x, y: y + 2))
                brow.addLine(to: CGPoint(x: inner.x, y: y - 3))
            case .happy, .proud:
                brow.move(to: CGPoint(x: outer.x, y: y))
                brow.addQuadCurve(to: inner, control: CGPoint(x: x, y: y - 4))
            case .neutral:
                brow.move(to: outer)
                brow.addLine(to: inner)
            }
            ctx.stroke(brow, with: .color(hair), style: style)
        }
    }

    private func drawGlasses(_ ctx: inout GraphicsContext) {
        let frame = Color(white: 0.18)
        let style = StrokeStyle(lineWidth: 1.8)
        for x in [leftEyeX, rightEyeX] {
            ctx.stroke(Path(roundedRect: CGRect(x: x - 9, y: eyeY - 7, width: 18, height: 14), cornerRadius: 5),
                       with: .color(frame), style: style)
        }
        var bridge = Path()
        bridge.move(to: CGPoint(x: leftEyeX + 9, y: eyeY - 1))
        bridge.addLine(to: CGPoint(x: rightEyeX - 9, y: eyeY - 1))
        ctx.stroke(bridge, with: .color(frame), style: style)
    }

    private func drawMustache(_ ctx: inout GraphicsContext) {
        var m = Path()
        m.move(to: CGPoint(x: 50, y: 68))
        m.addQuadCurve(to: CGPoint(x: 31, y: 73), control: CGPoint(x: 38, y: 63))
        m.addQuadCurve(to: CGPoint(x: 50, y: 72), control: CGPoint(x: 40, y: 76))
        m.addQuadCurve(to: CGPoint(x: 69, y: 73), control: CGPoint(x: 60, y: 76))
        m.addQuadCurve(to: CGPoint(x: 50, y: 68), control: CGPoint(x: 62, y: 63))
        ctx.fill(m, with: .color(hair))
    }

    private func drawMouth(_ ctx: inout GraphicsContext) {
        let y = mouthY
        let style = StrokeStyle(lineWidth: 2.4, lineCap: .round)
        var p = Path()
        switch mood {
        case .neutral:
            p.move(to: CGPoint(x: 44, y: y))
            p.addLine(to: CGPoint(x: 56, y: y))
            ctx.stroke(p, with: .color(lip), style: style)
        case .happy:
            p.move(to: CGPoint(x: 41, y: y - 2))
            p.addQuadCurve(to: CGPoint(x: 59, y: y - 2), control: CGPoint(x: 50, y: y + 7))
            ctx.stroke(p, with: .color(lip), style: style)
        case .proud:
            p.move(to: CGPoint(x: 40, y: y - 3))
            p.addQuadCurve(to: CGPoint(x: 60, y: y - 3), control: CGPoint(x: 50, y: y + 11))
            p.closeSubpath()
            ctx.fill(p, with: .color(lip))
        case .stern:
            p.move(to: CGPoint(x: 42, y: y + 2))
            p.addQuadCurve(to: CGPoint(x: 58, y: y + 2), control: CGPoint(x: 50, y: y - 4))
            ctx.stroke(p, with: .color(lip), style: style)
        case .worried:
            ctx.stroke(Path(ellipseIn: CGRect(x: 46, y: y - 3, width: 8, height: 7)), with: .color(lip), style: style)
        }
    }

    private func drawBlush(_ ctx: inout GraphicsContext) {
        let blush = Color(red: 0.95, green: 0.45, blue: 0.45).opacity(0.35)
        ctx.fill(Path(ellipseIn: CGRect(x: 26, y: 63, width: 10, height: 7)), with: .color(blush))
        ctx.fill(Path(ellipseIn: CGRect(x: 64, y: 63, width: 10, height: 7)), with: .color(blush))
    }
}
