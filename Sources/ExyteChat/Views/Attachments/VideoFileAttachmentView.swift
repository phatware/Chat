//
//  VideoFileAttachmentView.swift
//  Chat
//
//  View for displaying video file attachments in chat messages with playback capability
//

import SwiftUI
import AVFoundation

public struct VideoFileAttachmentView: View {
    @Environment(\.chatTheme) private var theme

    let attachment: Attachment
    let onTap: (() -> Void)?

    @State private var thumbnailImage: UIImage?
    @State private var isLoadingThumbnail = true
    @State private var canPlay = false

    public init(attachment: Attachment, onTap: (() -> Void)? = nil) {
        self.attachment = attachment
        self.onTap = onTap
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Thumbnail or fallback icon
            thumbnailView
                .frame(width: 60, height: 60)
                .background(Color.primary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName ?? "Video")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                Text(fileExtension.uppercased())
                    .font(.caption2)
                    .opacity(0.7)
            }
            .padding(.leading, 12)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .task {
            await generateThumbnail()
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        ZStack {
            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoadingThumbnail {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                // Fallback: show video icon
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(theme.colors.mainTint)
            }

            // Play button overlay (only if can play)
            if canPlay {
                Circle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .offset(x: 1)
                    )
            }
        }
    }

    private var fileExtension: String {
        guard let fileName = attachment.fileName else { return "video" }
        let components = fileName.split(separator: ".")
        if components.count > 1 {
            return String(components.last ?? "")
        }
        return "video"
    }

    private func generateThumbnail() async {
        let url = attachment.full

        // First check if the video can be played
        let asset = AVURLAsset(url: url)

        // Check if the asset is playable
        do {
            let isPlayable = try await asset.load(.isPlayable)
            await MainActor.run {
                canPlay = isPlayable
            }
        } catch {
            await MainActor.run {
                canPlay = false
            }
        }

        // Generate thumbnail
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 120, height: 120)

        do {
            let cgImage = try await imageGenerator.image(at: .zero).image
            let uiImage = UIImage(cgImage: cgImage)
            await MainActor.run {
                thumbnailImage = uiImage
                isLoadingThumbnail = false
            }
        } catch {
            await MainActor.run {
                thumbnailImage = nil
                isLoadingThumbnail = false
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        VideoFileAttachmentView(
            attachment: Attachment(
                id: "1",
                url: URL(string: "file:///example.mp4")!,
                type: .file,
                fileName: "sample_video.mp4",
                mimeType: "video/mp4"
            )
        )
        VideoFileAttachmentView(
            attachment: Attachment(
                id: "2",
                url: URL(string: "file:///example.mov")!,
                type: .file,
                fileName: "recording_2024_01_15_very_long_filename.mov",
                mimeType: "video/quicktime"
            )
        )
    }
    .padding()
}
