//
//  Created by Alex.M on 20.06.2022.
//

import SwiftUI

struct AttachmentsPage: View {

    @EnvironmentObject var mediaPagesViewModel: FullscreenMediaPagesViewModel
    @Environment(\.chatTheme) private var theme

    let attachment: Attachment

    var body: some View {
        if attachment.isGIF {
            AnimatedGIFView(
                url: attachment.full,
                cacheKey: attachment.fullCacheKey,
                contentMode: .scaleAspectFit
            )
        } else if attachment.type == .image {
#if canImport(UIKit)
            ZoomableImageView(
                url: attachment.full,
                cacheKey: attachment.fullCacheKey,
                isZoomed: $mediaPagesViewModel.isZoomed
            )
#else
            CachedAsyncImage(
                url: attachment.full,
                cacheKey: attachment.fullCacheKey
            ) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                default:
                    ActivityIndicator()
                }
            }
#endif
        } else if attachment.type == .video || attachment.isVideoFile {
            // Handle both regular video attachments and video files
            VideoView(viewModel: VideoViewModel(attachment: attachment))
        } else {
            Rectangle()
                .foregroundColor(Color.gray)
                .frame(minWidth: 100, minHeight: 100)
                .frame(maxHeight: 200)
                .overlay {
                    Text("Unknown", bundle: .module)
                }
        }
    }
}
