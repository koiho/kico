import SwiftUI

struct GalleryView: View {
    @StateObject private var viewModel = GalleryViewModel()
    @Environment(\.dismiss) private var dismiss
    let photos: [PhotoItem]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    init(photos: [PhotoItem]) {
        self.photos = photos
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                navigationBar

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(viewModel.state.photos) { photo in
                            photoCell(photo)
                                .onTapGesture {
                                    viewModel.selectPhoto(photo)
                                }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 36)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            viewModel.loadPhotos(photos)
        }
        .fullScreenCover(item: $viewModel.state.selectedPhoto) { photo in
            PhotoDetailView(photo: photo)
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }

            Text("作品")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Photo Cell

    private func photoCell(_ photo: PhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            DiskImageView(
                url: photo.thumbnailURL,
                maxPixelSize: 480,
                contentMode: .fill
            ) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.25))
            }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(photo.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(photo.dateString)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
        }
    }
}
