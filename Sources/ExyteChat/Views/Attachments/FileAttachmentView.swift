//
//  FileAttachmentView.swift
//  Chat
//
//  View for displaying file attachments in chat messages
//

import SwiftUI

public struct FileAttachmentView: View {
    @Environment(\.chatTheme) private var theme

    let fileName: String
    let onTap: (() -> Void)?

    public init(fileName: String, onTap: (() -> Void)? = nil) {
        self.fileName = fileName
        self.onTap = onTap
    }

    public var body: some View {
        HStack(spacing: 12) {
            fileIcon
                .font(.system(size: 28))
                .foregroundColor(theme.colors.mainTint)

            VStack(alignment: .leading, spacing: 2) {
                Text(fileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                Text(fileExtension.uppercased())
                    .font(.caption2)
                    .opacity(0.7)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }

    private var fileExtension: String {
        let components = fileName.split(separator: ".")
        if components.count > 1 {
            return String(components.last ?? "")
        }
        return "file"
    }

    private var fileIcon: Image {
        let ext = fileExtension.lowercased()

        switch ext {
        case "pdf":
            return Image(systemName: "doc.fill")
        case "doc", "docx":
            return Image(systemName: "doc.text.fill")
        case "xls", "xlsx":
            return Image(systemName: "tablecells.fill")
        case "ppt", "pptx":
            return Image(systemName: "rectangle.split.3x1.fill")
        case "txt", "rtf":
            return Image(systemName: "doc.plaintext.fill")
        case "zip", "rar", "7z", "tar", "gz":
            return Image(systemName: "doc.zipper")
        case "mp3", "wav", "m4a", "aac":
            return Image(systemName: "waveform")
        case "mp4", "mov", "avi", "mkv":
            return Image(systemName: "play.rectangle.fill")
        case "png", "jpg", "jpeg", "gif", "heic", "webp":
            return Image(systemName: "photo.fill")
        case "json", "xml", "html", "css", "js":
            return Image(systemName: "chevron.left.forwardslash.chevron.right")
        case "swift", "py", "java", "c", "cpp", "h", "m":
            return Image(systemName: "curlybraces")
        default:
            return Image(systemName: "doc.fill")
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        FileAttachmentView(fileName: "document.pdf")
        FileAttachmentView(fileName: "spreadsheet.xlsx")
        FileAttachmentView(fileName: "presentation.pptx")
        FileAttachmentView(fileName: "archive.zip")
        FileAttachmentView(fileName: "script.swift")
        FileAttachmentView(fileName: "unknown_file")
    }
    .padding()
}
