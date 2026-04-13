//
//  MessageView.swift
//  Chat
//
//  Created by Alex.M on 23.05.2022.
//

import SwiftUI

struct MessageView: View {

    @Environment(\.chatTheme) var theme

    @ObservedObject var viewModel: ChatViewModel

    let message: Message
    let positionInUserGroup: PositionInUserGroup
    let positionInMessagesSection: PositionInMessagesSection
    let chatType: ChatType
    let avatarSize: CGFloat
    let tapAvatarClosure: ChatView.TapAvatarClosure?
    let messageStyler: (String) -> AttributedString
    let shouldShowLinkPreview: (URL) -> Bool
    let isDisplayingMessageMenu: Bool
    let showMessageTimeView: Bool
    let messageLinkPreviewLimit: Int
    var font: UIFont

    @State var avatarViewSize: CGSize = .zero
    @State var statusSize: CGSize = .zero
    @State var giphyAspectRatio: CGFloat = 1
    @State var messageSize: CGSize = .zero

    // The size of our reaction bubbles are based on the users font size,
    // Therefore we need to capture it's rendered size in order to place it correctly
    @State var bubbleSize: CGSize = .zero

    static let widthWithMedia: CGFloat = 204
    static let horizontalScreenEdgePadding: CGFloat = 12
    static let horizontalNoAvatarPadding: CGFloat = horizontalScreenEdgePadding / 2
    static let horizontalAvatarPadding: CGFloat = 8
    static let horizontalTextPadding: CGFloat = 12
    static let attachmentPadding: CGFloat = 1  // for multiple attachments
    static let statusViewSize: CGFloat = 10
    static let horizontalStatusPadding: CGFloat = horizontalScreenEdgePadding / 2
    static let horizontalBubblePadding: CGFloat = 70
    static let textTimestampTrailingInset: CGFloat = 8

    var additionalMediaInset: CGFloat {
        message.attachments.count > 1 ? MessageView.attachmentPadding * 2 : 0
    }

    /// The message text with leading/trailing whitespace stripped.
    private var trimmedText: String {
        message.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when the message is purely 1-3 emoji with no attachments/recording.
    var isEmojiOnlyMessage: Bool {
        message.attachments.isEmpty
            && message.recording == nil
            && message.giphyMediaId == nil
            && message.replyMessage == nil
            && trimmedText.isEmojiOnly()
    }

    /// Font size for stand-alone emoji messages (like iMessage).
    private var emojiFontSize: CGFloat {
        switch trimmedText.emojiCount {
        case 1:  return 48
        case 2:  return 40
        default: return 32
        }
    }

    private var shouldStackTimeBelowText: Bool {
        !message.text.styled(using: messageStyler).urls.isEmpty && messageLinkPreviewLimit > 0
    }

    private var trailingTimestampReservationText: Text? {
        guard showMessageTimeView else { return nil }

        var reservation = Text(" \(message.time)")
            .font(.caption)

        if message.expiresAt != nil {
            reservation = reservation
                + Text(" ")
                    .font(.caption)
                + Text(Image(systemName: "timer"))
                    .font(.system(size: 9))
                + Text(" 88:88m")
                    .font(.caption)
        }

        return reservation
    }

    var showAvatar: Bool {
        isDisplayingMessageMenu
            || positionInUserGroup == .single
            || (chatType == .conversation && positionInUserGroup == .last)
            || (chatType == .comments && positionInUserGroup == .first)
    }

    var topPadding: CGFloat {
        if chatType == .comments { return 0 }
        return positionInUserGroup.isTop && !positionInMessagesSection.isTop ? 8 : 4
    }

    var bottomPadding: CGFloat {
        if chatType == .conversation { return 0 }
        return positionInUserGroup.isTop ? 8 : 4
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: message.user.isCurrentUser ? .trailing : .leading, spacing: 2) {
                if !isDisplayingMessageMenu, let reply = message.replyMessage?.toMessage() {
                    replyBubbleView(reply)
                        .opacity(theme.style.replyOpacity)
                        .padding(message.user.isCurrentUser ? .trailing : .leading, 10)
                        .overlay(alignment: message.user.isCurrentUser ? .trailing : .leading) {
                            Capsule()
                                .foregroundColor(theme.colors.mainTint)
                                .frame(width: 2)
                        }
                }

                bubbleView(message)
            }

            if message.user.isCurrentUser {
                if let provider = viewModel.statusProvider {
                    LiveMessageStatusView(
                        provider: provider,
                        messageId: message.id,
                        fallbackStatus: message.status
                    ) {
                        if let status = provider.statuses[message.id] ?? message.status,
                           case let .error(draft) = status {
                            viewModel.sendMessage(draft)
                        }
                    }
                    .sizeGetter($statusSize)
                } else if let status = message.status {
                    MessageStatusView(status: status) {
                        if case let .error(draft) = status {
                            viewModel.sendMessage(draft)
                        }
                    }
                    .sizeGetter($statusSize)
                }
            }
        }
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .padding(.leading, message.user.isCurrentUser ? 0 : MessageView.horizontalScreenEdgePadding)
        .padding(.trailing, message.user.isCurrentUser ? MessageView.horizontalNoAvatarPadding : 0)
        .padding(
            message.user.isCurrentUser ? .leading : .trailing, MessageView.horizontalBubblePadding
        )
        .frame(
            maxWidth: .infinity,
            alignment: message.user.isCurrentUser ? .trailing : .leading)
    }

    @ViewBuilder
    func bubbleView(_ message: Message) -> some View {
        VStack(
            alignment: message.user.isCurrentUser ? .leading : .trailing,
            spacing: -bubbleSize.height / 3
        ) {
            if !isDisplayingMessageMenu && !message.reactions.isEmpty {
                reactionsView(message)
                    .zIndex(1)
            }

            if isEmojiOnlyMessage {
                // Large stand-alone emoji (no bubble, no timestamp) – iMessage style
                Text(trimmedText)
                    .font(.system(size: emojiFontSize))
                    .padding(.horizontal, 4)
                    .zIndex(0)
            } else {
                VStack(alignment: .leading, spacing: 0) {

#if GIPHY_UISDK
                   if let giphyMediaId = message.giphyMediaId {
                       giphyView(giphyMediaId)
                   }
#endif
                    if !message.attachments.isEmpty {
                        attachmentsView(message)
                    }

                    if !message.attachments.isEmpty && message.text.isEmpty
                        && message.attachments.allSatisfy({ $0.type == .file })
                    {
                        messageTimeView()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                    }

                    if !message.text.isEmpty {
                        textWithTimeView(message)
                            .font(Font(font))
                    }

                    if let recording = message.recording {
                        VStack(alignment: .trailing, spacing: 8) {
                            recordingView(recording)
                            messageTimeView()
                                .padding(.bottom, 8)
                                .padding(.trailing, 12)
                        }
                    }
                }
                .bubbleBackground(message, theme: theme)
                .zIndex(0)
            }
        }
        .applyIf(isDisplayingMessageMenu) {
            $0.frameGetter($viewModel.messageFrame)
        }
    }

    @ViewBuilder
    func replyBubbleView(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(message.user.name)
                .fontWeight(.semibold)
                .padding(.horizontal, MessageView.horizontalTextPadding)

            if !message.attachments.isEmpty {
                attachmentsView(message)
                    .padding(.top, 4)
                    .padding(.bottom, message.text.isEmpty ? 0 : 4)
            }

            if !message.text.isEmpty {
                MessageTextView(
                    text: message.text, messageStyler: messageStyler,
                    userType: message.user.type, shouldShowLinkPreview: shouldShowLinkPreview,
                    messageLinkPreviewLimit: messageLinkPreviewLimit, trailingReservedText: nil
                )
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, MessageView.horizontalTextPadding)
            }

            if let recording = message.recording {
                recordingView(recording)
            }
        }
        .font(.caption2)
        .padding(.vertical, 8)
        .frame(
            width: message.attachments.isEmpty
                ? nil : MessageView.widthWithMedia + additionalMediaInset
        )
        .bubbleBackground(message, theme: theme, isReply: true)
    }

    @ViewBuilder
    var avatarView: some View {
        Group {
            if showAvatar {
                if let url = message.user.avatarURL {
                    AvatarImageView(url: url, avatarSize: avatarSize, avatarCacheKey: message.user.avatarCacheKey)
                        .contentShape(Circle())
                        .onTapGesture {
                            tapAvatarClosure?(message.user, message.id)
                        }
                } else {
                    AvatarNameView(name: message.user.name, avatarSize: avatarSize)
                        .contentShape(Circle())
                        .onTapGesture {
                            tapAvatarClosure?(message.user, message.id)
                        }
                }

            } else {
                Color.clear.viewSize(avatarSize)
            }
        }
        .padding(.leading, MessageView.horizontalScreenEdgePadding)
        .padding(.trailing, MessageView.horizontalAvatarPadding)
        .sizeGetter($avatarViewSize)
    }

    @ViewBuilder
    func attachmentsView(_ message: Message) -> some View {
        AttachmentsGrid(attachments: message.attachments, isCurrentUser: message.user.isCurrentUser) { attachment, isCancel in
          if isCancel {
            let update = AttachmentUploadUpdate(
              messageId: message.id,
              attachmentId: attachment.id,
              updateAction: AttachmentUploadUpdate.UpdateAction.cancel
            )
            viewModel.updateAttachmentStatus(update)
          } else {
            viewModel.presentAttachmentFullScreen(attachment)
          }
        }
        .applyIf(message.attachments.count > 1) {
            $0
                .padding(.top, MessageView.attachmentPadding)
                .padding(.horizontal, MessageView.attachmentPadding)
        }
        .overlay(alignment: .bottomTrailing) {
            if message.text.isEmpty && !message.attachments.allSatisfy({ $0.type == .file }) {
                messageTimeView(needsCapsule: true)
                    .padding(4)
            }
        }
        .contentShape(Rectangle())
    }

#if GIPHY_UISDK
   @ViewBuilder
   func giphyView(_ giphyMediaId: String) -> some View {
       GiphyMediaView(id: giphyMediaId, aspectRatio: $giphyAspectRatio)
           .frame(width: 200 * giphyAspectRatio, height: 200)
   }
#endif

    @ViewBuilder
    func textWithTimeView(_ message: Message) -> some View {
        let messageView = MessageTextView(
            text: message.text, messageStyler: messageStyler,
            userType: message.user.type, shouldShowLinkPreview: shouldShowLinkPreview,
            messageLinkPreviewLimit: messageLinkPreviewLimit,
            trailingReservedText: shouldStackTimeBelowText ? nil : trailingTimestampReservationText
        )
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, MessageView.horizontalTextPadding)

        let inlineTimeView = messageTimeView()
            .padding(.vertical, 6)
            .padding(.trailing, MessageView.textTimestampTrailingInset)

        let stackedTimeView = messageTimeView()
            .padding(.horizontal, 12)
            .padding(.trailing, MessageView.textTimestampTrailingInset)

        Group {
            if shouldStackTimeBelowText {
                VStack(alignment: .trailing, spacing: 4) {
                    messageView
                    stackedTimeView
                }
                .padding(.vertical, 6)
            } else {
                messageView
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottomTrailing) {
                        inlineTimeView
                    }
            }
        }
    }

    @ViewBuilder
    func recordingView(_ recording: Recording) -> some View {
        RecordWaveformWithButtons(
            recording: recording,
            colorButton: message.user.isCurrentUser
                ? theme.colors.messageMyBG : theme.colors.mainBG,
            colorButtonBg: message.user.isCurrentUser
                ? theme.colors.mainBG : theme.colors.messageMyBG,
            colorWaveform: theme.colors.messageText(message.user.type)
        )
        .padding(.horizontal, MessageView.horizontalTextPadding)
        .padding(.top, 8)
    }

    func messageTimeView(needsCapsule: Bool = false) -> some View {
        Group {
            if showMessageTimeView {
                if needsCapsule {
                    MessageTimeWithCapsuleView(
                        text: message.time, isCurrentUser: message.user.isCurrentUser,
                        chatTheme: theme, expiresAt: message.expiresAt)
                } else {
                    MessageTimeView(
                        text: message.time, userType: message.user.type, chatTheme: theme,
                        expiresAt: message.expiresAt)
                }
            }
        }
    }
}

extension View {

    @ViewBuilder
    func bubbleBackground(_ message: Message, theme: ChatTheme, isReply: Bool = false) -> some View
    {
        let hasFileAttachment = message.attachments.contains { $0.type == .file }
        let radius: CGFloat = !message.attachments.isEmpty ? 12 : 20
        let additionalMediaInset: CGFloat = message.attachments.count > 1 ? 2 : 0
        self
            .frame(
                width: message.attachments.isEmpty
                    ? nil : MessageView.widthWithMedia + additionalMediaInset
            )
            .foregroundColor(theme.colors.messageText(message.user.type))
            .background {
                if isReply || !message.text.isEmpty || message.recording != nil || hasFileAttachment {
                    RoundedRectangle(cornerRadius: radius)
                        .foregroundColor(theme.colors.messageBG(message.user.type))
                        .opacity(isReply ? theme.style.replyOpacity : 1)
                }
            }
            .cornerRadius(radius)
    }
}

#if DEBUG
    struct MessageView_Preview: PreviewProvider {
        static let stan = User(id: "stan", name: "Stan", avatarURL: nil, isCurrentUser: false)
        static let john = User(id: "john", name: "John", avatarURL: nil, isCurrentUser: true)

        static private var extraShortText = "Sss"
        static private var extraShortTextWithNewline = "H\nJ"
        static private var shortText = "Hi, buddy!"
        static private var longText =
            "Hello hello hello hello hello hello hello hello hello hello hello hello hello\n hello hello hello hello d d d d d d d d"

        static private var replyedMessage = Message(
            id: UUID().uuidString,
            user: stan,
            status: .read,
            text: longText,
            attachments: [
                Attachment.randomImage(),
                Attachment.randomImage(),
                Attachment.randomImage(),
                Attachment.randomImage(),
                Attachment.randomImage(),
            ],
            reactions: [
                Reaction(
                    user: john, createdAt: Date.now.addingTimeInterval(-70), type: .emoji("🔥"),
                    status: .sent),
                Reaction(
                    user: stan, createdAt: Date.now.addingTimeInterval(-60), type: .emoji("🥳"),
                    status: .sent),
                Reaction(
                    user: stan, createdAt: Date.now.addingTimeInterval(-50), type: .emoji("🤠"),
                    status: .sent),
                Reaction(
                    user: stan, createdAt: Date.now.addingTimeInterval(-40), type: .emoji("🧠"),
                    status: .sent),
                Reaction(
                    user: stan, createdAt: Date.now.addingTimeInterval(-30), type: .emoji("🥳"),
                    status: .sent),
                Reaction(
                    user: stan, createdAt: Date.now.addingTimeInterval(-20), type: .emoji("🤯"),
                    status: .sent),
                Reaction(
                    user: john, createdAt: Date.now.addingTimeInterval(-10), type: .emoji("🥰"),
                    status: .sending),
            ]
        )

        static private var message = Message(
            id: UUID().uuidString,
            user: stan,
            status: .read,
            text: shortText,
            replyMessage: replyedMessage.toReplyMessage()
        )

        static private var shortMessage = Message(
            id: UUID().uuidString,
            user: stan,
            status: .read,
            text: extraShortText
        )

        static private var extrShortMessage = Message(
            id: UUID().uuidString,
            user: stan,
            status: .read,
            text: extraShortTextWithNewline
        )

        static var previews: some View {
            ZStack {
                Color.yellow.ignoresSafeArea()

                VStack {
                    MessageView(
                        viewModel: ChatViewModel(),
                        message: extrShortMessage,
                        positionInUserGroup: .single,
                        positionInMessagesSection: .single,
                        chatType: .conversation,
                        avatarSize: 32,
                        tapAvatarClosure: nil,
                        messageStyler: AttributedString.init,
                        shouldShowLinkPreview: { _ in true },
                        isDisplayingMessageMenu: false,
                        showMessageTimeView: true,
                        messageLinkPreviewLimit: 8,
                        font: UIFontMetrics.default.scaledFont(for: UIFont.systemFont(ofSize: 15))
                    )

                    MessageView(
                        viewModel: ChatViewModel(),
                        message: replyedMessage,
                        positionInUserGroup: .single,
                        positionInMessagesSection: .single,
                        chatType: .conversation,
                        avatarSize: 32,
                        tapAvatarClosure: nil,
                        messageStyler: AttributedString.init,
                        shouldShowLinkPreview: { _ in true },
                        isDisplayingMessageMenu: false,
                        showMessageTimeView: true,
                        messageLinkPreviewLimit: 8,
                        font: UIFontMetrics.default.scaledFont(for: UIFont.systemFont(ofSize: 15))
                    )
                }

            }
        }
    }
#endif
