// Renders NxT's app icon from the same SwiftUI view the app uses (MuseOrganizer/DesignSystem/Logo.swift).
// Run from the repo root:
//   swiftc -parse-as-library MuseOrganizer/DesignSystem/Logo.swift scripts/render-icon.swift -o /tmp/render-icon && /tmp/render-icon
import AppKit
import SwiftUI

@main
struct RenderIcon {
    @MainActor static func main() throws {
        let out = URL(fileURLWithPath: "MuseOrganizer/Assets.xcassets/AppIcon.appiconset")
        let variants: [(String, NxTMark.Style)] = [("AppIcon.png", .standard), ("AppIcon-dark.png", .dark), ("AppIcon-tinted.png", .tinted)]
        for (name, style) in variants {
            let renderer = ImageRenderer(content: NxTMark(size: 1024, style: style, rounded: false))
            renderer.scale = 1
            guard let cg = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
            let rep = NSBitmapImageRep(cgImage: cg)
            guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: out.appendingPathComponent(name))
            print("wrote", name, cg.width, "x", cg.height)
        }
    }
}
