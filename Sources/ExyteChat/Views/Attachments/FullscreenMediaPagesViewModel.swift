//
//  Created by Alex.M on 22.06.2022.
//

import Foundation
import Combine

public final class FullscreenMediaPagesViewModel: ObservableObject {
    public var attachments: [Attachment]
    @Published public var index: Int

    @Published public var showMinis = true
    @Published public var offset: CGSize = .zero

    @Published public var isZoomed = false

    @Published public var videoPlaying = false
    @Published public var videoMuted = false

    @Published public var toggleVideoPlaying = {}
    @Published public var toggleVideoMuted = {}

    public init(attachments: [Attachment], index: Int) {
        self.attachments = attachments
        self.index = index
    }
}
