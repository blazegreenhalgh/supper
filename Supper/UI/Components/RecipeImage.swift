import SwiftUI
import UIKit

struct RecipeImage: View {
    let data: Data?

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "fork.knife")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .clipped()
    }
}
