//
//  DocumentPicker.swift
//  Chat
//
//  SwiftUI wrapper for UIDocumentPickerViewController
//

import SwiftUI
import UniformTypeIdentifiers

/// Represents a selected file from the document picker
public struct SelectedFile: Identifiable, Sendable {
    public let id = UUID()
    public let url: URL
    public let fileName: String
    public let fileData: Data
    public let mimeType: String

    public init(url: URL, fileName: String, fileData: Data, mimeType: String) {
        self.url = url
        self.fileName = fileName
        self.fileData = fileData
        self.mimeType = mimeType
    }
}

/// SwiftUI wrapper for the system document picker
public struct DocumentPicker: UIViewControllerRepresentable {
    let allowedContentTypes: [UTType]
    let onFilePicked: (SelectedFile?) -> Void

    public init(allowedContentTypes: [UTType] = [.item],
         onFilePicked: @escaping (SelectedFile?) -> Void) {
        self.allowedContentTypes = allowedContentTypes
        self.onFilePicked = onFilePicked
    }

    public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    public func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(onFilePicked: onFilePicked)
    }

    public class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFilePicked: (SelectedFile?) -> Void

        init(onFilePicked: @escaping (SelectedFile?) -> Void) {
            self.onFilePicked = onFilePicked
        }

        public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onFilePicked(nil)
                return
            }

            // Try to access security-scoped resource (may not be needed for copied files)
            let needsSecurityScope = url.startAccessingSecurityScopedResource()

            defer {
                if needsSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let fileData = try Data(contentsOf: url)
                let fileName = url.lastPathComponent
                let mimeType = determineMimeType(from: url)

                let selectedFile = SelectedFile(
                    url: url,
                    fileName: fileName,
                    fileData: fileData,
                    mimeType: mimeType
                )
                onFilePicked(selectedFile)
            } catch {
                print("[DocumentPicker] Failed to read file: \(error)")
                onFilePicked(nil)
            }
        }

        public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onFilePicked(nil)
        }

        private func determineMimeType(from url: URL) -> String {
            let pathExtension = url.pathExtension.lowercased()

            // Common MIME types
            let mimeTypes: [String: String] = [
                "pdf": "application/pdf",
                "doc": "application/msword",
                "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                "xls": "application/vnd.ms-excel",
                "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                "ppt": "application/vnd.ms-powerpoint",
                "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
                "txt": "text/plain",
                "rtf": "application/rtf",
                "csv": "text/csv",
                "json": "application/json",
                "xml": "application/xml",
                "zip": "application/zip",
                "gz": "application/gzip",
                "tar": "application/x-tar",
                "rar": "application/vnd.rar",
                "7z": "application/x-7z-compressed",
                "mp3": "audio/mpeg",
                "wav": "audio/wav",
                "mp4": "video/mp4",
                "mov": "video/quicktime",
                "avi": "video/x-msvideo",
                "png": "image/png",
                "jpg": "image/jpeg",
                "jpeg": "image/jpeg",
                "gif": "image/gif",
                "heic": "image/heic",
                "webp": "image/webp",
                "svg": "image/svg+xml",
                "html": "text/html",
                "css": "text/css",
                "js": "application/javascript",
                "py": "text/x-python",
                "swift": "text/x-swift",
                "java": "text/x-java-source",
                "c": "text/x-c",
                "cpp": "text/x-c++",
                "h": "text/x-c",
                "m": "text/x-objective-c",
                "md": "text/markdown"
            ]

            return mimeTypes[pathExtension] ?? "application/octet-stream"
        }
    }
}
