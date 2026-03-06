//
//  Created by Alex.M on 22.06.2022.
//

import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct FullscreenMediaPages: View {

    @Environment(\.chatTheme) private var theme

    @StateObject var viewModel: FullscreenMediaPagesViewModel
    var safeAreaInsets: EdgeInsets
    var onClose: () -> Void

    private var isPad: Bool {
#if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .pad
#else
        false
#endif
    }

    var body: some View {
        let closeGesture = DragGesture()
            .onChanged { viewModel.offset = closeSize(from: $0.translation) }
            .onEnded {
                withAnimation {
                    viewModel.offset = .zero
                }
                if $0.translation.height >= 100 {
                    onClose()
                }
            }

        ZStack {
            theme.colors.mainBG
                .opacity(max((200.0 - viewModel.offset.height) / 200.0, 0.5))
            VStack {
                TabView(selection: $viewModel.index) {
                    ForEach(viewModel.attachments.enumerated().map({ $0 }), id: \.offset) { (index, attachment) in
                        AttachmentsPage(attachment: attachment)
                            .tag(index)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)
                            .ignoresSafeArea()
                    }
                    .ignoresSafeArea()
                }
                .environmentObject(viewModel)
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .offset(viewModel.offset)
            .gesture(closeGesture)
            .onTapGesture {
                withAnimation {
                    viewModel.showMinis.toggle()
                }
            }

            VStack {
                Spacer()
                ScrollViewReader { proxy in
                    if viewModel.showMinis {
                        ScrollView(.horizontal) {
                            HStack(spacing: 2) {
                                ForEach(viewModel.attachments
                                    .filter { $0.fullUploadStatus == nil || $0.fullUploadStatus == .complete  }
                                    .enumerated().map({ $0 }), id: \.offset) { (index, attachment) in
                                    AttachmentCell(attachment: attachment, size: CGSize(width: 100, height: 100)) { _,_ in
                                        withAnimation {
                                            viewModel.index = index
                                        }
                                    }
                                    .cornerRadius(4)
                                    .clipped()
                                    .id(index)
                                    .overlay {
                                        if viewModel.index == index {
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(theme.colors.sendButtonBackground, lineWidth: 2)
                                        }
                                    }
                                    .padding(.vertical, 1)
                                }
                            }
                        }
                        .padding([.top, .horizontal], 12)
                        .background(theme.colors.mainBG)
                        .onAppear {
                            proxy.scrollTo(viewModel.index)
                        }
                        .onChange(of: viewModel.index) { _, newValue in
                            withAnimation {
                                proxy.scrollTo(newValue, anchor: .center)
                            }
                        }
                    }
                }
                .offset(y: -safeAreaInsets.bottom)
            }
            .offset(viewModel.offset)
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            if viewModel.showMinis {
                Text("\(viewModel.index + 1)/\(viewModel.attachments.count)")
                    .foregroundColor(theme.colors.mainText)
                    .offset(y: safeAreaInsets.top)
            }
        }
        .overlay(alignment: .topLeading) {
            if !isPad {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .padding(.leading, 15)
                .offset(y: safeAreaInsets.top + 5)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isPad {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .padding(.trailing, 15)
                .offset(y: safeAreaInsets.top + 5)
            }
        }
        .overlay(alignment: .topTrailing) {
            let currentAttachment = viewModel.attachments[viewModel.index]
            if viewModel.showMinis, (currentAttachment.type == .video || currentAttachment.isVideoFile) {
                HStack(spacing: 10) {
                    (viewModel.videoPlaying ? theme.images.fullscreenMedia.pause : theme.images.fullscreenMedia.play)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .padding(5)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.toggleVideoPlaying()
                        }

                    (viewModel.videoMuted ? theme.images.fullscreenMedia.unmute : theme.images.fullscreenMedia.mute)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .padding(5)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.toggleVideoMuted()
                        }
                }
                .foregroundColor(.white)
                .padding(.top, 5)
                .padding(.leading, 10)
                .padding(.trailing, isPad ? 60 : 10)
                .offset(y: safeAreaInsets.top)
            }
        }
    }
}

private extension FullscreenMediaPages {
    func closeSize(from size: CGSize) -> CGSize {
        CGSize(width: 0, height: max(size.height, 0))
    }
}
