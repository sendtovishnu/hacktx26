import SwiftUI
import UIKit
import PhotosUI

/// Profile photos, saved on this device by user id and shown by every Avatar.
/// The real server also gets a copy (POST /api/me/photo) so friends on other phones see it.
final class AvatarStore: ObservableObject {
    static let shared = AvatarStore()

    @Published private(set) var images: [String: UIImage] = [:]
    private let folder: URL

    private init() {
        folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "jpg" {
            if let image = UIImage(contentsOfFile: file.path) {
                images[file.deletingPathExtension().lastPathComponent] = image
            }
        }
    }

    func image(for id: String?) -> UIImage? {
        guard let id else { return nil }
        return images[id]
    }

    /// Crops to a square, shrinks to 512 px, saves, and returns the JPEG to upload.
    @discardableResult
    func save(_ image: UIImage, for id: String) -> Data? {
        guard let jpeg = Self.squareJPEG(from: image) else { return nil }
        try? jpeg.write(to: url(for: id), options: .atomic)
        images[id] = UIImage(data: jpeg)
        return jpeg
    }

    func remove(for id: String) {
        try? FileManager.default.removeItem(at: url(for: id))
        images[id] = nil
    }

    private func url(for id: String) -> URL {
        folder.appendingPathComponent("\(id).jpg")
    }

    static func squareJPEG(from image: UIImage, side: CGFloat = 512) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = max(side / size.width, side / size.height)
        let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
        let origin = CGPoint(x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let square = renderer.image { _ in
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
        return square.jpegData(compressionQuality: 0.85)
    }
}

/// Wraps any label in a photo picker that sets the signed-in person's profile photo.
struct ProfilePhotoPicker<Label: View>: View {
    @EnvironmentObject private var state: AppState
    @State private var item: PhotosPickerItem?
    @ViewBuilder let label: () -> Label

    var body: some View {
        PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
            label()
        }
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                await apply(newItem)
                item = nil
            }
        }
    }

    private func apply(_ item: PhotosPickerItem) async {
        guard let id = state.me?.id,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpeg = AvatarStore.shared.save(image, for: id) else { return }
        if let user = try? await state.api.uploadPhoto(jpeg) {
            state.updateMe(user)
        }
    }
}
