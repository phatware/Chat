//
//  InputView.swift
//  Chat
//
//  Created by Alex.M on 25.05.2022.
//

import SwiftUI
import ExyteMediaPicker
#if GIPHY_UISDK
import GiphyUISDK
#endif

public enum InputViewStyle: Sendable {
    case message
    case signature
}

public enum InputViewAction: Sendable {
    case giphy
    case photo
    case add
    case camera
    case files
    case send

    case recordAudioHold
    case recordAudioTap
    case recordAudioLock
    case stopRecordAudio
    case deleteRecord
    case playRecord
    case pauseRecord
    //    case location
    //    case document

    case saveEdit
    case cancelEdit
}

public enum InputViewState: Sendable {
    case empty
    case hasTextOrMedia

    case waitingForRecordingPermission
    case isRecordingHold
    case isRecordingTap
    case hasRecording
    case playingRecording
    case pausedRecording

    case editing

    var canSend: Bool {
        switch self {
        case .hasTextOrMedia, .hasRecording, .isRecordingTap, .playingRecording, .pausedRecording: return true
        default: return false
        }
    }
}

public enum AvailableInputType: Sendable {
    case text
    case media
    case audio
    case giphy
}

public struct InputViewAttachments {
    var medias: [Media] = []
    var recording: Recording?
#if GIPHY_UISDK
    var giphyMedia: GPHMedia?
#endif
    var replyMessage: ReplyMessage?
    var file: DraftFile?
}

struct InputView: View {

    @Environment(\.chatTheme) private var theme
    @Environment(\.mediaPickerTheme) private var pickerTheme

    @EnvironmentObject private var keyboardState: KeyboardState

    @ObservedObject var viewModel: InputViewModel
    var inputFieldId: UUID
    var style: InputViewStyle
    var availableInputs: [AvailableInputType]
    var messageStyler: (String) -> AttributedString
    var recorderSettings: RecorderSettings = RecorderSettings()
    var localization: ChatLocalization

    @StateObject var recordingPlayer = RecordingPlayer()

    private var onAction: (InputViewAction) -> Void {
        viewModel.inputViewAction()
    }

    private var state: InputViewState {
        viewModel.state
    }

    @State private var overlaySize: CGSize = .zero

    @State private var recordButtonFrame: CGRect = .zero
    @State private var lockRecordFrame: CGRect = .zero
    @State private var deleteRecordFrame: CGRect = .zero

    @State private var dragStart: Date?
    @State private var tapDelayTimer: Timer?
    @State private var cancelGesture = false
    private let tapDelay = 0.2

    var body: some View {
        VStack {
            viewOnTop
            HStack(alignment: .bottom, spacing: 10) {
                HStack(alignment: .bottom, spacing: 0) {
                    leftView
                    middleView
                    rightView
                }
                .background {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(style == .message ? theme.colors.inputBG : theme.colors.inputSignatureBG)
                }

                rightOutsideButton
            }
            .padding(.horizontal, MessageView.horizontalScreenEdgePadding)
            .padding(.vertical, 8)
        }
        .background(backgroundColor)
        .onAppear {
            viewModel.recordingPlayer = recordingPlayer
            viewModel.setRecorderSettings(recorderSettings: recorderSettings)
        }
        .onDrag(towards: .bottom, ofAmount: 100...) {
            keyboardState.resignFirstResponder()
        }
    }

    @ViewBuilder
    var leftView: some View {
        if [.isRecordingTap, .isRecordingHold, .hasRecording, .playingRecording, .pausedRecording].contains(state) {
            deleteRecordButton
        } else {
            switch style {
            case .message:
                attachMenuButton
            case .signature:
                if viewModel.mediaPickerMode == .cameraSelection {
                    addButton
                } else {
                    Color.clear.frame(width: 12, height: 1)
                }
            }
        }
    }

    @ViewBuilder
    var middleView: some View {
        Group {
            switch state {
            case .hasRecording, .playingRecording, .pausedRecording:
                recordWaveform
            case .isRecordingHold, .isRecordingTap:
                recordingInProgress
            default:
                TextInputView(
                    text: $viewModel.text,
                    inputFieldId: inputFieldId,
                    style: style,
                    availableInputs: availableInputs,
                    localization: localization
                )
            }
        }
        .frame(minHeight: 48)
    }

    @ViewBuilder
    var rightView: some View {
        Group {
            switch state {
            case .empty, .waitingForRecordingPermission:
                if isAudioAvailable() {
                    inlineRecordButton
                } else {
                    Color.clear.frame(width: 8, height: 1)
                }
            case .isRecordingHold, .isRecordingTap:
                recordDurationInProcess
            case .hasRecording:
                recordDuration
            case .playingRecording, .pausedRecording:
                recordDurationLeft
            default:
                Color.clear.frame(width: 8, height: 1)
            }
        }
        .frame(minHeight: 48)
    }

    @ViewBuilder
    var editingButtons: some View {
        HStack {
            Button {
                onAction(.cancelEdit)
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.white)
                    .fontWeight(.bold)
                    .padding(5)
                    .background(Circle().foregroundStyle(.red))
            }

            Button {
                onAction(.saveEdit)
            } label: {
                Image(systemName: "checkmark")
                    .foregroundStyle(.white)
                    .fontWeight(.bold)
                    .padding(5)
                    .background(Circle().foregroundStyle(.green))
            }
        }
    }

    @ViewBuilder
    var rightOutsideButton: some View {
        if state == .editing {
            editingButtons
                .frame(height: 48)
        }
        else if [.isRecordingTap, .isRecordingHold].contains(state) {
            // Recording in progress - show simple stop button
            Button {
                onAction(.stopRecordAudio)
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.red))
            }
            .viewSize(48)
        }
        else if state.canSend {
            // Has content to send - show send button
            sendButton
                .viewSize(48)
        }
        else {
            // Empty state - mic is inline, show nothing outside
            EmptyView()
        }
    }

    @ViewBuilder
    var viewOnTop: some View {
        VStack(spacing: 0) {
            // Media (image) attachment preview
            if let media = viewModel.attachments.medias.first {
                MediaAttachmentPreview(media: media) {
                    viewModel.attachments.medias = []
                }
                .environmentObject(viewModel)
            }

            // File attachment preview
            if let file = viewModel.attachments.file {
                fileAttachmentPreview(file)
            }

            // Reply message preview
            if let message = viewModel.attachments.replyMessage {
                VStack(spacing: 8) {
                    Rectangle()
                        .foregroundColor(theme.colors.messageFriendBG)
                        .frame(height: 2)

                    HStack {
                        theme.images.reply.replyToMessage
                        Capsule()
                            .foregroundColor(theme.colors.messageMyBG)
                            .frame(width: 2)
                        VStack(alignment: .leading) {
                            Text(localization.replyToText + " " + message.user.name)
                                .font(.caption2)
                                .foregroundColor(theme.colors.mainCaptionText)
                            if !message.text.isEmpty {
                                textView(message.text)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .foregroundColor(theme.colors.mainText)
                            }
                        }
                        .padding(.vertical, 2)

                        Spacer()

                        if let first = message.attachments.first {
                            AsyncImageView(attachment: first, size: CGSize(width: 30, height: 30))
                                .viewSize(30)
                                .cornerRadius(4)
                                .padding(.trailing, 16)
                        }

                        if let _ = message.recording {
                            theme.images.inputView.microphone
                                .renderingMode(.template)
                                .foregroundColor(theme.colors.mainTint)
                        }

                        theme.images.reply.cancelReply
                            .onTapGesture {
                                viewModel.attachments.replyMessage = nil
                            }
                    }
                    .padding(.horizontal, 26)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    func fileAttachmentPreview(_ file: DraftFile) -> some View {
        VStack(spacing: 8) {
            Rectangle()
                .foregroundColor(theme.colors.messageFriendBG)
                .frame(height: 2)

            HStack(spacing: 12) {
                Image(systemName: fileIcon(for: file.fileName))
                    .font(.system(size: 24))
                    .foregroundColor(theme.colors.mainTint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.fileName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(theme.colors.mainText)
                        .lineLimit(1)

                    Text(formatFileSize(file.fileData.count))
                        .font(.caption2)
                        .foregroundColor(theme.colors.mainCaptionText)
                }

                Spacer()

                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(theme.colors.mainCaptionText)
                    .onTapGesture {
                        viewModel.setFile(nil)
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func fileIcon(for fileName: String) -> String {
        let ext = fileName.split(separator: ".").last?.lowercased() ?? ""
        switch ext {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx": return "tablecells.fill"
        case "ppt", "pptx": return "rectangle.split.3x1.fill"
        case "txt", "rtf": return "doc.plaintext.fill"
        case "zip", "rar", "7z", "tar", "gz": return "doc.zipper"
        case "mp3", "wav", "m4a", "aac": return "waveform"
        case "mp4", "mov", "avi", "mkv": return "play.rectangle.fill"
        case "png", "jpg", "jpeg", "gif", "heic", "webp": return "photo.fill"
        default: return "doc.fill"
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }

    @ViewBuilder
    func textView(_ text: String) -> some View {
        Text(text.styled(using: messageStyler))
    }

    var attachButton: some View {
        Button {
            onAction(.photo)
        } label: {
            theme.images.inputView.attach
                .viewSize(24)
                .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 6))
        }
    }

    var attachMenuButton: some View {
        Menu {
            Button {
                onAction(.camera)
            } label: {
                Label("Camera", systemImage: "camera")
            }
            Button {
                onAction(.photo)
            } label: {
                Label("Pictures", systemImage: "photo.on.rectangle")
            }
            Button {
                onAction(.files)
            } label: {
                Label("Files", systemImage: "doc")
            }
        } label: {
            Image(systemName: "paperclip")
                .font(.system(size: 20))
                .foregroundColor(theme.colors.mainTint)
                .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 8))
        }
    }

    var giphyButton: some View {
        Button {
            onAction(.giphy)
        } label: {
            theme.images.inputView.sticker
                .resizable()
                .viewSize(24)
                .padding(EdgeInsets(top: 12, leading: 6, bottom: 12, trailing: 12))
        }
    }

    var addButton: some View {
        Button {
            onAction(.add)
        } label: {
            theme.images.inputView.add
                .viewSize(24)
                .circleBackground(theme.colors.sendButtonBackground)
                .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 8))
        }
    }

    var cameraButton: some View {
        Button {
            onAction(.camera)
        } label: {
            theme.images.inputView.attachCamera
                .viewSize(24)
                .padding(EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 12))
        }
    }

    var sendButton: some View {
        Button {
            onAction(.send)
        } label: {
            theme.images.inputView.arrowSend
                .viewSize(48)
                .circleBackground(theme.colors.sendButtonBackground)
        }
    }

    var recordButton: some View {
        theme.images.inputView.microphone
            .viewSize(48)
            .circleBackground(theme.colors.sendButtonBackground)
            .frameGetter($recordButtonFrame)
    }

    var inlineRecordButton: some View {
        Button {
            onAction(.recordAudioTap)
        } label: {
            theme.images.inputView.microphone
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .foregroundColor(theme.colors.mainTint)
                .padding(EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 12))
        }
        .frameGetter($recordButtonFrame)
    }

    var deleteRecordButton: some View {
        Button {
            onAction(.deleteRecord)
        } label: {
            theme.images.recordAudio.deleteRecord
                .viewSize(24)
                .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 8))
        }
        .frameGetter($deleteRecordFrame)
    }

    var stopRecordButton: some View {
        Button {
            onAction(.stopRecordAudio)
        } label: {
            theme.images.recordAudio.stopRecord
                .viewSize(28)
                .background(
                    Capsule()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.4), radius: 1)
                )
        }
    }

    var lockRecordButton: some View {
        Button {
            onAction(.recordAudioLock)
        } label: {
            VStack(spacing: 20) {
                theme.images.recordAudio.lockRecord
                theme.images.recordAudio.sendRecord
            }
            .frame(width: 28)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.4), radius: 1)
            )
        }
        .frameGetter($lockRecordFrame)
    }

    var swipeToCancel: some View {
        HStack {
            Spacer()
            Button {
                onAction(.deleteRecord)
            } label: {
                HStack {
                    theme.images.recordAudio.cancelRecord
                        .renderingMode(.template)
                        .foregroundStyle(theme.colors.mainText)
                    Text(localization.cancelButtonText)
                        .font(.footnote)
                        .foregroundColor(theme.colors.mainText)
                }
            }
            Spacer()
        }
    }

    var recordingInProgress: some View {
        HStack {
            Spacer()
            Text(localization.recordingText)
                .font(.footnote)
                .foregroundColor(theme.colors.mainText)
            Spacer()
        }
    }

    var recordDurationInProcess: some View {
        HStack {
            Circle()
                .foregroundColor(theme.colors.recordDot)
                .viewSize(6)
            recordDuration
        }
    }

    var recordDuration: some View {
        Text(DateFormatter.timeString(Int(viewModel.attachments.recording?.duration ?? 0)))
            .foregroundColor(theme.colors.mainText)
            .opacity(0.6)
            .font(.caption2)
            .monospacedDigit()
            .padding(.trailing, 12)
    }

    var recordDurationLeft: some View {
        Text(DateFormatter.timeString(Int(recordingPlayer.secondsLeft)))
            .foregroundColor(theme.colors.mainText)
            .opacity(0.6)
            .font(.caption2)
            .monospacedDigit()
            .padding(.trailing, 12)
    }

    var playRecordButton: some View {
        Button {
            onAction(.playRecord)
        } label: {
            theme.images.recordAudio.playRecord
        }
        .foregroundColor(theme.colors.sendButtonBackground)
    }

    var pauseRecordButton: some View {
        Button {
            onAction(.pauseRecord)
        } label: {
            theme.images.recordAudio.pauseRecord
        }
        .foregroundColor(theme.colors.sendButtonBackground)
    }

    @ViewBuilder
    var recordWaveform: some View {
        if let samples = viewModel.attachments.recording?.waveformSamples {
            HStack(spacing: 8) {
                Group {
                    if state == .hasRecording || state == .pausedRecording {
                        playRecordButton
                    } else if state == .playingRecording {
                        pauseRecordButton
                    }
                }
                .frame(width: 20)

                RecordWaveformPlaying(samples: samples, progress: recordingPlayer.progress, color: theme.colors.mainText, addExtraDots: true) { progress in
                    Task {
                        await recordingPlayer.seek(with: viewModel.attachments.recording!, to: progress)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    var backgroundColor: Color {
        switch style {
        case .message:
            return theme.colors.mainBG
        case .signature:
            return pickerTheme.main.pickerBackground
        }
    }

    func dragGesture() -> some Gesture {
        DragGesture(minimumDistance: 0.0, coordinateSpace: .global)
            .onChanged { [state] value in
                if dragStart == nil {
                    dragStart = Date()
                    cancelGesture = false
                    tapDelayTimer = Timer.scheduledTimer(withTimeInterval: tapDelay, repeats: false) { _ in
                        if state != .isRecordingTap, state != .waitingForRecordingPermission {
                            DispatchQueue.main.async {
                                self.onAction(.recordAudioHold)
                            }
                        }
                    }
                }

                if value.location.y < lockRecordFrame.minY,
                   value.location.x > recordButtonFrame.minX {
                    cancelGesture = true
                    onAction(.recordAudioLock)
                }

                if value.location.x < UIScreen.main.bounds.width/2,
                   value.location.y > recordButtonFrame.minY {
                    cancelGesture = true
                    onAction(.deleteRecord)
                }
            }
            .onEnded() { value in
                if !cancelGesture {
                    tapDelayTimer = nil
                    if recordButtonFrame.contains(value.location) {
                        if let dragStart = dragStart, Date().timeIntervalSince(dragStart) < tapDelay {
                            onAction(.recordAudioTap)
                        }
                        else if state != .waitingForRecordingPermission {
                            onAction(.send)
                        }
                    }
                    else if lockRecordFrame.contains(value.location) {
                        onAction(.recordAudioLock)
                    }
                    else if deleteRecordFrame.contains(value.location) {
                        onAction(.deleteRecord)
                    }
                    else {
                        onAction(.send)
                    }
                }
                dragStart = nil
            }
    }

    private func isAudioAvailable() -> Bool {
        return availableInputs.contains(AvailableInputType.audio)
    }

    private func isGiphyAvailable() -> Bool {
        return availableInputs.contains(AvailableInputType.giphy)
    }

    private func isMediaAvailable() -> Bool {
        return availableInputs.contains(AvailableInputType.media)
    }
}

// MARK: - Media Attachment Preview

struct MediaAttachmentPreview: View {
    @Environment(\.chatTheme) private var theme

    let media: Media
    let onRemove: () -> Void

    @State private var thumbnailImage: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            Rectangle()
                .foregroundColor(theme.colors.messageFriendBG)
                .frame(height: 2)

            HStack(spacing: 12) {
                // Thumbnail
                Group {
                    if let image = thumbnailImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.colors.messageFriendBG)
                            .frame(width: 44, height: 44)
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundColor(theme.colors.mainTint)
                            }
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(media.type == .video ? "Video" : "Photo")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(theme.colors.mainText)
                        .lineLimit(1)

                    Text("Tap send to share")
                        .font(.caption2)
                        .foregroundColor(theme.colors.mainCaptionText)
                }

                Spacer()

                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(theme.colors.mainCaptionText)
                    .onTapGesture {
                        onRemove()
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .fixedSize(horizontal: false, vertical: true)
        .task(id: media.id) {
            thumbnailImage = nil
            if let data = await media.getThumbnailData(), let image = UIImage(data: data) {
                thumbnailImage = image
                return
            }

            if media.type == .image, let data = await media.getData(), let image = UIImage(data: data) {
                thumbnailImage = image
            }
        }
    }
}

@MainActor
func performBatchTableUpdates(_ tableView: UITableView, closure: ()->()) async {
    await withCheckedContinuation { continuation in
        tableView.performBatchUpdates {
            closure()
        } completion: { _ in
            continuation.resume()
        }
    }
}
