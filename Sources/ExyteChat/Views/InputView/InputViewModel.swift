//
//  Created by Alex.M on 20.06.2022.
//

import Foundation
import Combine
import ExyteMediaPicker

@MainActor
final class InputViewModel: ObservableObject {

    /// Maximum allowed attachment size in bytes (5MB)
    static let maxAttachmentSize: Int = 5 * 1024 * 1024

    @Published var text = ""
    @Published var attachments = InputViewAttachments()
    @Published var state: InputViewState = .empty

    @Published var showGiphyPicker = false
    @Published var showPicker = false
    @Published var showFilePicker = false

    @Published var mediaPickerMode = MediaPickerMode.photos

    @Published var showActivityIndicator = false

    /// Error message to display to the user
    @Published var errorMessage: String?

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
        subscribeValidation()
        subscribePicker()
#if GIPHY_UISDK
        subscribeGiphyPicker()
#endif
    }

    func onStop() {
        subscriptions.removeAll()
    }

    func reset() {
        showPicker = false
        showGiphyPicker = false
        showFilePicker = false
        text = ""
        saveEditingClosure = nil
        attachments = InputViewAttachments()
        subscribeValidation()
        state = .empty
    }

    func send() {
        Task {
            await recorder.stopRecording()
            await recordingPlayer?.reset()
            sendMessage()
        }
    }

    func edit(_ closure: @escaping (String) -> Void) {
        saveEditingClosure = closure
        state = .editing
    }

    func setFile(_ file: DraftFile?) {
        print("[InputViewModel] setFile called: \(file?.fileName ?? "nil"), size: \(file?.fileData.count ?? 0)")
        attachments.file = file
        showFilePicker = false
        validateDraft()
        print("[InputViewModel] After setFile - state: \(state), file attached: \(attachments.file != nil)")
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
                attachments.recording = nil
                state = .empty
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

    func subscribeValidation() {
        $attachments.sink { [weak self] _ in
            self?.validateDraft()
        }
        .store(in: &subscriptions)

        $text.sink { [weak self] _ in
            self?.validateDraft()
        }
        .store(in: &subscriptions)
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
        // Note: Don't clear medias when picker closes - they should persist
        // until the message is sent or user removes them manually.
        // The reset() function handles clearing when message is sent.
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

    func sendMessage() {
        showActivityIndicator = true
        print("[InputViewModel] sendMessage called")

        Task {
            // Check for empty content - nothing to send
            let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasMedia = !attachments.medias.isEmpty
            let hasFile = attachments.file != nil && attachments.file!.fileData.count > 0
            let hasRecording = attachments.recording != nil && attachments.recording!.duration > 0
            print("[InputViewModel] sendMessage checks: hasText=\(hasText), hasMedia=\(hasMedia), hasFile=\(hasFile), hasRecording=\(hasRecording)")

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
                    errorMessage = "Cannot send empty file."
                }
                return
            }

            // Check for empty recording (0 duration)
            if let recording = attachments.recording, recording.duration <= 0 {
                await MainActor.run {
                    showActivityIndicator = false
                    errorMessage = "Recording is empty. Please record audio first."
                }
                return
            }

            // Check file size limit
            if let file = attachments.file {
                if file.fileData.count > Self.maxAttachmentSize {
                    await MainActor.run {
                        showActivityIndicator = false
                        errorMessage = "File is too large. Maximum size is \(Self.maxAttachmentSize / 1024 / 1024)MB."
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
                                errorMessage = "Cannot send empty media."
                            }
                            return
                        }
                        if data.count > Self.maxAttachmentSize {
                            await MainActor.run {
                                showActivityIndicator = false
                                errorMessage = "Media is too large. Maximum size is \(Self.maxAttachmentSize / 1024 / 1024)MB."
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
                    text: self.text,
                    medias: attachments.medias,
                    giphyMedia: attachments.giphyMedia,
                    recording: attachments.recording,
                    replyMessage: attachments.replyMessage,
                    file: attachments.file,
                    createdAt: Date()
                )
#else
                let draft = DraftMessage(
                    text: self.text,
                    medias: attachments.medias,
                    recording: attachments.recording,
                    replyMessage: attachments.replyMessage,
                    file: attachments.file,
                    createdAt: Date()
                )
#endif
                print("[InputViewModel] Sending draft with file: \(draft.file?.fileName ?? "nil")")
                didSendMessage?(draft)
                showActivityIndicator = false
                reset()
            }
        }
    }
}
