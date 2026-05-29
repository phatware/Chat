//
//  Created by Alex.M on 20.06.2022.
//

import Foundation
import Combine
import ExyteMediaPicker
import UIKit

@MainActor
final class InputViewModel: ObservableObject {

    /// Default maximum allowed attachment size in bytes (1MB for free tier).
    static let defaultMaxAttachmentSize: Int = 1 * 1024 * 1024

    /// Default absolute hard cap (10MB). No tier — including Pro — can exceed this.
    static let defaultHardMaxAttachmentSize: Int = 10 * 1024 * 1024

    /// UserDefaults key for max attachment size.
    /// NOTE: This key must match YMConstants.UserDefaults.chatMaxAttachmentSize in the host app.
    private static let maxAttachmentSizeKey = "chat.maxAttachmentSize"

    /// UserDefaults key for the absolute hard cap.
    /// NOTE: Must match YMConstants.UserDefaults.chatHardMaxAttachmentSize in the host app.
    private static let hardMaxAttachmentSizeKey = "chat.hardMaxAttachmentSize"

    /// Maximum allowed attachment size for the current subscription tier, in bytes.
    /// Reads from UserDefaults, allowing external configuration (e.g., by SubscriptionManager).
    var maxAttachmentSize: Int {
        let stored = UserDefaults.standard.integer(forKey: Self.maxAttachmentSizeKey)
        return stored > 0 ? stored : Self.defaultMaxAttachmentSize
    }

    /// Absolute hard cap for any attachment, regardless of tier.
    var hardMaxAttachmentSize: Int {
        let stored = UserDefaults.standard.integer(forKey: Self.hardMaxAttachmentSizeKey)
        let value = stored > 0 ? stored : Self.defaultHardMaxAttachmentSize
        // Hard cap can never be smaller than the tier limit.
        return max(value, maxAttachmentSize)
    }

    /// Sets the maximum attachment size in UserDefaults.
    /// Call this when subscription status changes.
    static func setMaxAttachmentSize(_ size: Int) {
        UserDefaults.standard.set(size, forKey: maxAttachmentSizeKey)
    }

    /// Sets the absolute hard cap in UserDefaults.
    static func setHardMaxAttachmentSize(_ size: Int) {
        UserDefaults.standard.set(size, forKey: hardMaxAttachmentSizeKey)
    }

    @Published var text = "" {
        didSet {
            validateDraft()
        }
    }
    @Published var attachments = InputViewAttachments() {
        didSet {
            validateDraft()
        }
    }
    @Published var state: InputViewState = .empty

    @Published var showGiphyPicker = false
    @Published var showPicker = false
    @Published var showFilePicker = false

    @Published var mediaPickerMode = MediaPickerMode.photos

    @Published var showActivityIndicator = false

    /// Error message to display to the user
    @Published var errorMessage: String?

    /// Whether the current `errorMessage` represents a limit the user can lift by upgrading.
    /// `false` for hard caps that affect all tiers (including Pro).
    @Published var errorIsUpgradable: Bool = false

    var recordingPlayer: RecordingPlayer?
    var didSendMessage: ((DraftMessage) -> Void)?

    private var recorder = Recorder()

    private var saveEditingClosure: ((String) -> Void)?

    private var recordPlayerSubscription: AnyCancellable?
    private var subscriptions = Set<AnyCancellable>()

    func setRecorderSettings(recorderSettings: RecorderSettings = RecorderSettings()) {
        Task {
            await self.recorder.setRecorderSettings(recorderSettings)
        }
    }

    func onStart() {
        subscribePicker()
#if GIPHY_UISDK
        subscribeGiphyPicker()
#endif
    }

    func onStop() {
        subscriptions.removeAll()
        unsubscribeRecordPlayer()

        Task { @MainActor in
            if state == .isRecordingHold || state == .isRecordingTap {
                await recorder.stopRecording()
                discardRecordingAttachment()
                restoreInputStateAfterRecordingRemoval()
            }

            await recordingPlayer?.reset()
        }
    }

    func reset() {
        showPicker = false
        showGiphyPicker = false
        showFilePicker = false
        text = ""
        saveEditingClosure = nil
        attachments = InputViewAttachments()
        state = .empty
    }

    func cancelActiveRecordingIfNeeded() {
        guard state == .isRecordingHold || state == .isRecordingTap else { return }

        Task { @MainActor in
            unsubscribeRecordPlayer()
            await recorder.stopRecording()
            await recordingPlayer?.reset()
            discardRecordingAttachment()
            restoreInputStateAfterRecordingRemoval()
        }
    }

    func send() {
        // Capture and clear text immediately for responsive UI
        let capturedText = text
        text = ""
        Task {
            await recorder.stopRecording()
            await recordingPlayer?.reset()
            sendMessage(text: capturedText)
        }
    }

    func edit(_ closure: @escaping (String) -> Void) {
        saveEditingClosure = closure
        state = .editing
    }

    func setFile(_ file: DraftFile?) {
#if DEBUG
        print("[InputViewModel] setFile called: \(file?.fileName ?? "nil"), size: \(file?.fileData.count ?? 0)")
#endif
        attachments.file = file
        showFilePicker = false
        validateDraft()
#if DEBUG
        print("[InputViewModel] After setFile - state: \(state), file attached: \(attachments.file != nil)")
#endif
    }

    /// Handle an image pasted from the clipboard.
    func handlePastedImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let file = DraftFile(
            fileName: "pasted_image.jpg",
            fileData: data,
            mimeType: "image/jpeg"
        )
        setFile(file)
    }

    /// Handle video data pasted from the clipboard.
    func handlePastedVideo(_ data: Data, fileName: String) {
        let ext = fileName.split(separator: ".").last?.lowercased() ?? "mp4"
        let mime = ext == "mov" ? "video/quicktime" : "video/mp4"
        let file = DraftFile(
            fileName: fileName,
            fileData: data,
            mimeType: mime
        )
        setFile(file)
    }

    /// Handle file data pasted from the clipboard.
    func handlePastedFile(_ data: Data, fileName: String, mimeType: String) {
        let file = DraftFile(
            fileName: fileName,
            fileData: data,
            mimeType: mimeType
        )
        setFile(file)
    }

    func inputViewAction() -> (InputViewAction) -> Void {
        { [weak self] in
            self?.inputViewActionInternal($0)
        }
    }

    private func inputViewActionInternal(_ action: InputViewAction) {
        switch action {
        case .giphy:
            showGiphyPicker = true
        case .photo:
            mediaPickerMode = .photos
            showPicker = true
        case .add:
            mediaPickerMode = .camera
        case .camera:
            mediaPickerMode = .camera
            showPicker = true
        case .files:
            showFilePicker = true
        case .send:
            send()
        case .recordAudioTap:
            state = .isRecordingTap
            startRecording()
        case .recordAudioHold:
            state = .isRecordingHold
            startRecording()
        case .recordAudioLock:
            state = .isRecordingTap
        case .stopRecordAudio:
            Task {
                await recorder.stopRecording()
                if let _ = attachments.recording {
                    state = .hasRecording
                }
                await recordingPlayer?.reset()
            }
        case .deleteRecord:
            Task {
                unsubscribeRecordPlayer()
                await recorder.stopRecording()
                discardRecordingAttachment()
                restoreInputStateAfterRecordingRemoval()
            }
        case .playRecord:
            state = .playingRecording
            if let recording = attachments.recording {
                Task {
                    subscribeRecordPlayer()
                    await recordingPlayer?.play(recording)
                }
            }
        case .pauseRecord:
            state = .pausedRecording
            Task {
                await recordingPlayer?.pause()
            }
        case .saveEdit:
            saveEditingClosure?(text)
            reset()
        case .cancelEdit:
            reset()
        }
    }

    private func startRecording() {
        Task { @MainActor in
            // Check if already recording
            if await recorder.isRecording {
                return
            }

            // Check permission
            let hasPermission = await recorder.isAllowedToRecordAudio
            if !hasPermission {
                state = .waitingForRecordingPermission
            }

            // Start recording
            attachments.recording = Recording()
            let url = await recorder.startRecording { [weak self] duration, samples in
                Task { @MainActor [weak self] in
                    self?.attachments.recording?.duration = duration
                    self?.attachments.recording?.waveformSamples = samples
                }
            }

            // Update state if we were waiting for permission
            if state == .waitingForRecordingPermission {
                state = .isRecordingTap
            }

            // If recording failed (url is nil), reset state
            if url == nil {
                attachments.recording = nil
                state = .empty
            } else {
                attachments.recording?.url = url
            }
        }
    }
}

private extension InputViewModel {

    func restoreInputStateAfterRecordingRemoval() {
        state = .empty
        validateDraft()
    }

    func discardRecordingAttachment() {
        if let url = attachments.recording?.url {
            try? FileManager.default.removeItem(at: url)
        }
        attachments.recording = nil
    }

    func validateDraft() {
        // Don't interfere with editing or recording states
        switch state {
        case .editing, .isRecordingHold, .isRecordingTap, .hasRecording, .playingRecording, .pausedRecording, .waitingForRecordingPermission:
            return
        default:
            break
        }

        let hasText = !self.text.isEmpty
        let hasMedias = !self.attachments.medias.isEmpty
        let hasFile = self.attachments.file != nil

        if hasText || hasMedias || hasFile {
            self.state = .hasTextOrMedia
        } else if self.text.isEmpty,
                  self.attachments.medias.isEmpty,
                  self.attachments.recording == nil,
                  self.attachments.file == nil {
            self.state = .empty
        }
    }

#if GIPHY_UISDK
   func subscribeGiphyPicker() {
       $showGiphyPicker
           .sink { [weak self] value in
               if !value {
                 self?.attachments.giphyMedia = nil
               }
           }
           .store(in: &subscriptions)
   }
#endif

    func subscribePicker() {
        $showPicker
            .removeDuplicates()
            .sink { [weak self] isPresented in
                guard let self else { return }
                if !isPresented {
                    // Ensure next open doesn't start in camera preview mode.
                    self.mediaPickerMode = .photos
                }
            }
            .store(in: &subscriptions)
    }

    func subscribeRecordPlayer() {
        Task { @MainActor in
            if let recordingPlayer {
                recordPlayerSubscription = recordingPlayer.didPlayTillEnd
                    .sink { [weak self] in
                        self?.state = .hasRecording
                    }
            }
        }
    }

    func unsubscribeRecordPlayer() {
        recordPlayerSubscription = nil
    }
}

private extension InputViewModel {

    func sendMessage(text messageText: String) {
        showActivityIndicator = true
#if DEBUG
        print("[InputViewModel] sendMessage called")
#endif
        Task {
            // Check for empty content - nothing to send
            let hasText = !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasMedia = !attachments.medias.isEmpty
            let hasFile = attachments.file != nil && attachments.file!.fileData.count > 0
            let hasRecording = attachments.recording != nil && attachments.recording!.duration > 0
#if DEBUG
            print("[InputViewModel] sendMessage checks: hasText=\(hasText), hasMedia=\(hasMedia), hasFile=\(hasFile), hasRecording=\(hasRecording)")
#endif

            if !hasText && !hasMedia && !hasFile && !hasRecording {
                await MainActor.run {
                    showActivityIndicator = false
                    // Silently ignore empty messages - just reset
                    reset()
                }
                return
            }

            // Check for empty file
            if let file = attachments.file, file.fileData.isEmpty {
                await MainActor.run {
                    showActivityIndicator = false
                    self.text = messageText // Restore text on error
                    errorMessage = "Cannot send empty file."
                }
                return
            }

            // Check for empty recording (0 duration)
            if let recording = attachments.recording, recording.duration <= 0 {
                await MainActor.run {
                    showActivityIndicator = false
                    self.text = messageText // Restore text on error
                    errorMessage = "Recording is empty. Please record audio first."
                }
                return
            }

            // Check file size limit
            if let file = attachments.file {
                if file.fileData.count > self.maxAttachmentSize {
                    let exceedsHardCap = file.fileData.count > self.hardMaxAttachmentSize
                    let limitMB = (exceedsHardCap ? self.hardMaxAttachmentSize : self.maxAttachmentSize) / 1024 / 1024
                    await MainActor.run {
                        showActivityIndicator = false
                        self.text = messageText // Restore text on error
                        errorIsUpgradable = !exceedsHardCap
                        errorMessage = "File is too large. Maximum size is \(limitMB)MB."
                    }
                    return
                }
            }

            // Check media size limit
            for media in attachments.medias {
                if let url = await media.getURL() {
                    do {
                        let data = try Data(contentsOf: url)
                        if data.count == 0 {
                            await MainActor.run {
                                showActivityIndicator = false
                                self.text = messageText // Restore text on error
                                errorMessage = "Cannot send empty media."
                            }
                            return
                        }
                        if data.count > self.maxAttachmentSize {
                            let exceedsHardCap = data.count > self.hardMaxAttachmentSize
                            let limitMB = (exceedsHardCap ? self.hardMaxAttachmentSize : self.maxAttachmentSize) / 1024 / 1024
                            await MainActor.run {
                                showActivityIndicator = false
                                self.text = messageText // Restore text on error
                                errorIsUpgradable = !exceedsHardCap
                                errorMessage = "Media is too large. Maximum size is \(limitMB)MB."
                            }
                            return
                        }
                    } catch {
                        // If we can't read the file, let it proceed and handle error later
                    }
                }
            }

            await MainActor.run {
#if GIPHY_UISDK
                let draft = DraftMessage(
                    text: messageText,
                    medias: attachments.medias,
                    giphyMedia: attachments.giphyMedia,
                    recording: attachments.recording,
                    replyMessage: attachments.replyMessage,
                    file: attachments.file,
                    createdAt: Date()
                )
#else
                let draft = DraftMessage(
                    text: messageText,
                    medias: attachments.medias,
                    recording: attachments.recording,
                    replyMessage: attachments.replyMessage,
                    file: attachments.file,
                    createdAt: Date()
                )
#endif
#if DEBUG
                print("[InputViewModel] Sending draft with file: \(draft.file?.fileName ?? "nil")")
#endif
                didSendMessage?(draft)
                showActivityIndicator = false
                reset()
            }
        }
    }
}
