//
//  Recorder.swift
//  
//
//  Created by Alisa Mylnikova on 09.03.2023.
//

import Foundation
@preconcurrency import AVFoundation

final actor Recorder {

    // duration and waveform samples
    typealias ProgressHandler = @Sendable (Double, [CGFloat]) -> Void

    private let audioSession = AVAudioSession.sharedInstance()
    private var audioRecorder: AVAudioRecorder?
    private var timerTask: Task<Void, Never>?

    private var soundSamples: [CGFloat] = []
    private var recorderSettings = RecorderSettings()

    var isAllowedToRecordAudio: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    var isRecording: Bool {
        audioRecorder?.isRecording ?? false
    }

    func setRecorderSettings(_ recorderSettings: RecorderSettings) {
        self.recorderSettings = recorderSettings
    }

    func startRecording(durationProgressHandler: @escaping ProgressHandler) async -> URL? {
        if !isAllowedToRecordAudio {
            let granted = await audioSession.requestRecordPermission()
            if granted {
                return startRecordingInternal(durationProgressHandler)
            }
            return nil
        } else {
            return startRecordingInternal(durationProgressHandler)
        }
    }
    
    private func startRecordingInternal(_ durationProgressHandler: @escaping ProgressHandler) -> URL? {
        let settings: [String : Any] = [
            AVFormatIDKey: Int(recorderSettings.audioFormatID),
            AVSampleRateKey: recorderSettings.sampleRate,
            AVNumberOfChannelsKey: recorderSettings.numberOfChannels,
            AVEncoderBitRateKey: recorderSettings.encoderBitRateKey,
            AVLinearPCMBitDepthKey: recorderSettings.linearPCMBitDepth,
            AVLinearPCMIsFloatKey: recorderSettings.linearPCMIsFloatKey,
            AVLinearPCMIsBigEndianKey: recorderSettings.linearPCMIsBigEndianKey,
            AVLinearPCMIsNonInterleaved: recorderSettings.linearPCMIsNonInterleaved,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        soundSamples = []
        guard let fileExt = fileExtension(for: recorderSettings.audioFormatID) else{
            return nil
        }
        let recordingUrl = FileManager.tempDirPath.appendingPathComponent(UUID().uuidString + fileExt)

        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
            audioRecorder = try AVAudioRecorder(url: recordingUrl, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            let started = audioRecorder?.record() ?? false
            print("[Recorder] Recording started: \(started), URL: \(recordingUrl)")
            durationProgressHandler(0.0, [])

            // Start timer task for duration updates
            timerTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    guard !Task.isCancelled else { break }
                    await self?.onTimer(durationProgressHandler)
                }
            }

            return recordingUrl
        } catch {
            print("[Recorder] Failed to start recording: \(error)")
            stopRecording()
            return nil
        }
    }

    func onTimer(_ durationProgressHandler: @escaping ProgressHandler) {
        guard let recorder = audioRecorder else {
            // Recorder is nil - stop the timer task
            timerTask?.cancel()
            timerTask = nil
            return
        }
        guard recorder.isRecording else {
            // Recording stopped - stop the timer task
            timerTask?.cancel()
            timerTask = nil
            return
        }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        // power from 0 db (max) to -60 db (roughly min)
        let adjustedPower = 1 - (max(power, -60) / 60 * -1)
        soundSamples.append(CGFloat(adjustedPower))

        let time = recorder.currentTime
        durationProgressHandler(time, soundSamples)
    }

    func stopRecording() {
        timerTask?.cancel()
        timerTask = nil
        audioRecorder?.stop()
        audioRecorder = nil
    }

    private func fileExtension(for formatID: AudioFormatID) -> String? {
        switch formatID {
        case kAudioFormatMPEG4AAC:
            return ".aac"
        case kAudioFormatLinearPCM:
            return ".wav"
        case kAudioFormatMPEGLayer3:
            return ".mp3"
        case kAudioFormatAppleLossless:
            return ".m4a"
        case kAudioFormatOpus:
            return ".opus"
        case kAudioFormatAC3:
            return ".ac3"
        case kAudioFormatFLAC:
            return ".flac"
        case kAudioFormatAMR:
            return ".amr"
        case kAudioFormatMIDIStream:
            return ".midi"
        case kAudioFormatULaw:
            return ".ulaw"
        case kAudioFormatALaw:
            return ".alaw"
        case kAudioFormatAMR_WB:
            return ".awb"
        case kAudioFormatEnhancedAC3:
            return ".eac3"
        case kAudioFormatiLBC:
            return ".ilbc"
        default:
            return nil
        }
    }
}

public struct RecorderSettings : Codable,Hashable {
    var audioFormatID: AudioFormatID
    var sampleRate: CGFloat
    var numberOfChannels: Int
    var encoderBitRateKey: Int
    // pcm
    var linearPCMBitDepth: Int
    var linearPCMIsFloatKey: Bool
    var linearPCMIsBigEndianKey: Bool
    var linearPCMIsNonInterleaved: Bool

    public init(audioFormatID: AudioFormatID = kAudioFormatMPEG4AAC,
                sampleRate: CGFloat = 22050,
                numberOfChannels: Int = 1,
                encoderBitRateKey: Int = 64000,
                linearPCMBitDepth: Int = 16,
                linearPCMIsFloatKey: Bool = false,
                linearPCMIsBigEndianKey: Bool = false,
                linearPCMIsNonInterleaved: Bool = false) {
        self.audioFormatID = audioFormatID
        self.sampleRate = sampleRate
        self.numberOfChannels = numberOfChannels
        self.encoderBitRateKey = encoderBitRateKey
        self.linearPCMBitDepth = linearPCMBitDepth
        self.linearPCMIsFloatKey = linearPCMIsFloatKey
        self.linearPCMIsBigEndianKey = linearPCMIsBigEndianKey
        self.linearPCMIsNonInterleaved = linearPCMIsNonInterleaved
    }
}

extension AVAudioSession {
    func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
