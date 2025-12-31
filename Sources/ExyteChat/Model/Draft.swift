//
//  Created by Alex.M on 17.06.2022.
//

import Foundation
import ExyteMediaPicker
#if GIPHY_UISDK
import GiphyUISDK
#endif

/// Represents a file attachment in a draft message
public struct DraftFile: Sendable {
    public let fileName: String
    public let fileData: Data
    public let mimeType: String

    public init(fileName: String, fileData: Data, mimeType: String) {
        self.fileName = fileName
        self.fileData = fileData
        self.mimeType = mimeType
    }
}

#if GIPHY_UISDK
public struct DraftMessage: Sendable {
    public var id: String?
    public let text: String
    public let medias: [Media]
    public let giphyMedia: GPHMedia?
    public let recording: Recording?
    public let replyMessage: ReplyMessage?
    public let file: DraftFile?
    public let createdAt: Date

    public init(id: String? = nil,
                text: String,
                medias: [Media],
                giphyMedia: GPHMedia?,
                recording: Recording?,
                replyMessage: ReplyMessage?,
                file: DraftFile? = nil,
                createdAt: Date) {
        self.id = id
        self.text = text
        self.medias = medias
        self.giphyMedia = giphyMedia
        self.recording = recording
        self.replyMessage = replyMessage
        self.file = file
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
    public let file: DraftFile?
    public let createdAt: Date

    public init(id: String? = nil,
                text: String,
                medias: [Media],
                recording: Recording?,
                replyMessage: ReplyMessage?,
                file: DraftFile? = nil,
                createdAt: Date) {
        self.id = id
        self.text = text
        self.medias = medias
        self.recording = recording
        self.replyMessage = replyMessage
        self.file = file
        self.createdAt = createdAt
    }
}
#endif

