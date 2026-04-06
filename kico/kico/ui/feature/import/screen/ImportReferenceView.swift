import SwiftUI
import PhotosUI

struct ImportReferenceView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toastCenter: ToastCenter
    @EnvironmentObject private var referenceImageStore: ReferenceImageStore
    @State private var selectedItems: [PhotosPickerItem] = []

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                navigationBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionTitle("最近参考")

                        if referenceImageStore.recentImages.isEmpty {
                            emptyState
                        } else {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(referenceImageStore.recentImages) { item in
                                    Button {
                                        referenceImageStore.select(item)
                                        dismiss()
                                    } label: {
                                        Image(uiImage: item.image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(height: 100)
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(
                                                        referenceImageStore.selectedImageID == item.id
                                                            ? Color.red
                                                            : Color.clear,
                                                        lineWidth: 2
                                                    )
                                            }
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }

                        selectFromLibraryButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                }
            }
        }
        .navigationBarHidden(true)
        .overlay(alignment: .top) {
            ToastHost()
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

            Text("导入参考")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Section Title

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.stack")
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text("暂无参考图片")
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Select from Library Button

    private var selectFromLibraryButton: some View {
        PhotosPicker(
            selection: $selectedItems,
            maxSelectionCount: 1,
            matching: .images
        ) {
            HStack {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 18, weight: .medium))

                Text("从相册选择")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.red)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .onChange(of: selectedItems) { oldValue, newValue in
            Task {
                for item in newValue {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else {
                            toastCenter.showError("图片读取失败，请重新选择", source: .import)
                            continue
                        }

                        guard let image = UIImage(data: data) else {
                            toastCenter.showError("图片格式不支持，请更换图片", source: .import)
                            continue
                        }

                        referenceImageStore.addImportedImage(image)
                        dismiss()
                    } catch {
                        toastCenter.showError("导入失败，请稍后重试", source: .import)
                    }
                }
                selectedItems.removeAll()
            }
        }
        .padding(.bottom, 20)
    }
}

#Preview {
    ImportReferenceView()
        .environmentObject(ToastCenter())
        .environmentObject(ReferenceImageStore())
}
