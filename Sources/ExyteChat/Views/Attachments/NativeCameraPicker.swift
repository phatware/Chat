import SwiftUI
import UIKit
import ExyteMediaPicker
import UniformTypeIdentifiers

public struct NativeCameraPicker: UIViewControllerRepresentable {
    private let onSelect: (Media) -> Void
    private let onCancel: () -> Void

    public init(onSelect: @escaping (Media) -> Void, onCancel: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

    public func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = context.coordinator
        return picker
    }

    public func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onCancel: onCancel)
    }

    public final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onSelect: (Media) -> Void
        private let onCancel: () -> Void

        init(onSelect: @escaping (Media) -> Void, onCancel: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onCancel = onCancel
        }

        public func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage,
                  let url = CameraMediaStorage.store(image: image) else {
                onCancel()
                return
            }

            onSelect(Media(source: CameraImageMediaModel(url: url)))
        }

        public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

private struct CameraImageMediaModel: MediaModelProtocol {
    let url: URL

    var mediaType: MediaType? { .image }
    var duration: CGFloat? { get async { nil } }

    func getURL() async -> URL? {
        url
    }

    func getThumbnailURL() async -> URL? {
        guard let thumbnailData = await getThumbnailData() else { return url }
        return CameraMediaStorage.store(data: thumbnailData)
    }

    func getData() async throws -> Data? {
        try Data(contentsOf: url)
    }

    func getThumbnailData() async -> Data? {
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        return image.cameraThumbnailData()
    }
}

private enum CameraMediaStorage {
    static func store(image: UIImage) -> URL? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        return store(data: data)
    }

    static func store(data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

private extension UIImage {
    func cameraThumbnailData(maxPixelSize: CGFloat = 600) -> Data? {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxPixelSize else {
            return jpegData(compressionQuality: 0.75)
        }

        let scale = maxPixelSize / longestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let thumbnail = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return thumbnail.jpegData(compressionQuality: 0.75)
    }
}
