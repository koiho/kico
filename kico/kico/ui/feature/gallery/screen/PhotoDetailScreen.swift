import SwiftUI
import UIKit

struct PhotoDetailView: View {
    let photo: PhotoItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                // Top bar
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                    }

                    Spacer()

                    Text(photo.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)

                    Spacer()

                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
                .padding(.horizontal, 8)

                Spacer()

                // Photo
                DiskImageView(
                    url: photo.imageURL,
                    maxPixelSize: max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * UIScreen.main.scale,
                    contentMode: .fit
                ) {
                    ProgressView()
                        .tint(.white)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 16)

                Spacer()
            }
        }
    }
}
