//
//  Created by Alex.M on 16.06.2022.
//

import SwiftUI

struct AttachmentsGrid: View {
    let onTap: (_ attachment: Attachment, _ isCancel: Bool) -> Void
    let isCurrentUser: Bool
    let maxImages: Int = 4 // TODO: Make injectable

    private let single: (Attachment)?
    private let grid: [Attachment]
    private let onlyOne: Bool
    private let fileAttachments: [Attachment]
    private let mediaAttachments: [Attachment]

    private let hidden: String?
    private let showMoreAttachmentId: String?

    init(attachments: [Attachment], isCurrentUser: Bool,
         onTap: @escaping (_ attachment: Attachment, _ isCancel: Bool) -> Void) {
        // Separate file attachments from media (image/video/gif)
        // GIF file attachments are treated as media so they display with animation in the image grid
        self.fileAttachments = attachments.filter { $0.type == .file && !$0.isGIF }
        self.mediaAttachments = attachments.filter { $0.type != .file || $0.isGIF }

        var toShow = mediaAttachments

        if toShow.count > maxImages {
            toShow = mediaAttachments.prefix(maxImages).map({ $0 })
            hidden = "+\(mediaAttachments.count - (maxImages - 1))"
            showMoreAttachmentId = mediaAttachments[safe: (maxImages - 1)]?.id
        } else {
            hidden = nil
            showMoreAttachmentId = nil
        }
        if toShow.count % 2 == 0 {
            single = nil
            grid = toShow
        } else {
            single = toShow.first
            grid = toShow.dropFirst().map { $0 }
        }
        self.onlyOne = mediaAttachments.count == 1 && fileAttachments.isEmpty
        self.onTap = onTap
        self.isCurrentUser = isCurrentUser
    }

    var columns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        // Media bubble width (2/3 of screen, capped) drives all attachment sizes so
        // the image fills the bubble instead of staying at the old fixed 204pt.
        let mediaWidth = MessageView.widthWithMedia
        let gridSpacing: CGFloat = 4
        let pairCell = (mediaWidth - gridSpacing) / 2

        return VStack(spacing: gridSpacing) {
            // File attachments shown as a vertical list
            ForEach(fileAttachments) { file in
                AttachmentCell(attachment: file, size: CGSize(width: mediaWidth, height: 60),
                               showCancel: isCurrentUser, onTap: onTap)
                    .frame(width: mediaWidth)
            }

            // Media attachments shown as grid
            if let attachment = single {
                AttachmentCell(attachment: attachment,
                               size: CGSize(width: mediaWidth,
                                            height: grid.isEmpty ? mediaWidth * (200.0 / 204.0) : pairCell),
                               showCancel: isCurrentUser, onTap: onTap)
                .clipped()
                .cornerRadius(onlyOne ? 0 : 12)
            }
            if !grid.isEmpty {
                ForEach(pair(), id: \.id) { pair in
                    HStack(spacing: gridSpacing) {
                        AttachmentCell(attachment: pair.left, size: CGSize(width: pairCell, height: pairCell),
                                       showCancel: isCurrentUser, onTap: onTap)
                            .clipped()
                            .cornerRadius(12)
                        AttachmentCell(attachment: pair.right, size: CGSize(width: pairCell, height: pairCell),
                                       showCancel: isCurrentUser, onTap: onTap)
                            .clipped()
                            .overlay {
                                if pair.right.id == showMoreAttachmentId, let hidden = hidden {
                                    ZStack {
                                        RadialGradient(
                                            colors: [
                                                .black.opacity(0.8),
                                                .black.opacity(0.6),
                                            ],
                                            center: .center,
                                            startRadius: 0,
                                            endRadius: 90
                                        )
                                        Text(hidden)
                                            .font(.body)
                                            .bold()
                                            .foregroundColor(.white)
                                    }
                                    .allowsHitTesting(false)
                                }
                            }
                            .cornerRadius(12)
                    }
                }
            }
        }
    }
}

private extension AttachmentsGrid {
    func pair() -> Array<AttachmentsPair> {
        return stride(from: 0, to: grid.count - 1, by: 2)
            .map { AttachmentsPair(left: grid[$0], right: grid[$0+1]) }
    }
}

struct AttachmentsPair {
    let left: Attachment
    let right: Attachment

    var id: String {
        left.id + "+" + right.id
    }
}

#if DEBUG
struct AttachmentsGrid_Preview: PreviewProvider {
    private static let examples = [1, 2, 3, 4, 5, 10]

    static var previews: some View {
        Group {
            ForEach(examples, id: \.self) { count in
                ScrollView {
                    AttachmentsGrid(attachments: .random(count: count), isCurrentUser: true, onTap: { _,_ in } )
                        .padding()
                        .background(Color.white)
                }
            }
            .padding()
            .background(Color.secondary)
        }
    }
}

extension Array where Element == Attachment {
    static func random(count: Int) -> [Attachment] {
        return Swift.Array(repeating: 0, count: count)
            .map { _ in randomAttachment() }
    }

    private static func randomAttachment() -> Attachment {
        if Int.random(in: 0...3) == 0 {
            return Attachment.randomVideo()
        } else {
            return Attachment.randomImage()
        }
    }
}

extension Attachment {
    static func randomImage() -> Attachment {
        Attachment(id: UUID().uuidString, url: URL(string: "https://placeimg.com/640/480/sepia")!, type: .image)
    }
    // TODO get video, not image
    static func randomVideo() -> Attachment {
        Attachment(id: UUID().uuidString, url: URL(string: "https://placeimg.com/640/480/sepia")!, type: .video)
    }
}
#endif
