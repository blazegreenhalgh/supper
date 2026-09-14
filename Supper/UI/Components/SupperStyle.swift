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
                self.buttonStyle(.glassProminent).tint(Color(uiColor: .systemBlue))
            } else {
                self.buttonStyle(.glass)
            }
        } else if prominent {
            self.buttonStyle(.borderedProminent).tint(Color(uiColor: .systemBlue))
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


extension View {
    func supperError(_ message: Binding<String?>, title: String) -> some View {
        alert(title, isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK", role: .cancel) { message.wrappedValue = nil }
        } message: { Text(message.wrappedValue ?? "") }
    }
}

struct RecipeTransitionSource {
    let id: String
    let namespace: Namespace.ID
}

struct RecipeZoomSource: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let source: RecipeTransitionSource?
    @ViewBuilder func body(content: Content) -> some View {
        if let source, !reduceMotion {
            content.matchedTransitionSource(id: source.id, in: source.namespace)
        } else { content }
    }
}

private struct RecipeZoomDestination: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let sourceID: String
    let namespace: Namespace.ID
    @ViewBuilder func body(content: Content) -> some View {
        if reduceMotion { content }
        else { content.navigationTransition(.zoom(sourceID: sourceID, in: namespace)) }
    }
}
extension View {
    func supperRecipeZoom(sourceID: String, in namespace: Namespace.ID) -> some View {
        modifier(RecipeZoomDestination(sourceID: sourceID, namespace: namespace))
    }
}
