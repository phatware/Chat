//
//  Created by Alex.M on 17.06.2022.
//

import Foundation
import ExyteMediaPicker
#if GIPHY_UISDK
import GiphyUISDK
#endif

#if GIPHY_UISDK
public struct DraftMessage: Sendable {
    public var id: String?
    public let text: String
    public let medias: [Media]
    public let giphyMedia: GPHMedia?
    public let recording: Recording?
    public let replyMessage: ReplyMessage?
    public let createdAt: Date

    public init(id: String? = nil,
                text: String,
                medias: [Media],
                giphyMedia: GPHMedia?,
                recording: Recording?,
                replyMessage: ReplyMessage?,
                createdAt: Date) {
        self.id = id
        self.text = text
        self.medias = medias
        self.giphyMedia = giphyMedia
        self.recording = recording
        self.replyMessage = replyMessage
        self.createdAt = createdAt
    }
}
#else
public struct DraftMessage: Sendable {
    public var id: String?
    public let text: String
    public let medias: [Media]
    public let recording: Recording?
    public let replyMessage: ReplyMessage?
    public let createdAt: Date

    public init(id: String? = nil,
                text: String,
                medias: [Media],
                recording: Recording?,
                replyMessage: ReplyMessage?,
                createdAt: Date) {
        self.id = id
        self.text = text
        self.medias = medias
        self.recording = recording
        self.replyMessage = replyMessage
        self.createdAt = createdAt
    }
}
#endif

