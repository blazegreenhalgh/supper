import SwiftUI
import UIKit

struct RecipeImage: View {
    let data: Data?

    var body: some View {
        // The parent owns the layout. A fill image must never contribute its
        // intrinsic aspect ratio to a grid cell, thumbnail, or navigation inset.
        GeometryReader { geometry in
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                ZStack {
                    Rectangle().fill(SupperStyle.subtle)
                    Image(systemName: "fork.knife")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
