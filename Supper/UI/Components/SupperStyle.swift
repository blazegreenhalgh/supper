import SwiftUI

enum SupperStyle {
    static let canvas = Color("Canvas")
    static let surface = Color("Surface")
    static let subtle = Color("Subtle")
}

extension View {
    /// Keep the system button's interaction, accessibility and Liquid Glass.
    @ViewBuilder
    func supperGlassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// For the floating text field and non-button overlays only. Navigation,
    /// toolbars, pickers, sheets and tabs keep their own native appearance.
    @ViewBuilder
    func supperGlassSurface() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self.background(.regularMaterial, in: .capsule)
        }
    }
}

struct SupperGlassGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) { content }
        } else {
            content
        }
    }
}
