//
//  Created by Alex.M on 14.06.2022.
//

import SwiftUI
import UIKit

struct TextInputView: View {

    @Environment(\.chatTheme) private var theme

    @EnvironmentObject private var globalFocusState: GlobalFocusState

    @Binding var text: String
    var inputFieldId: UUID
    var style: InputViewStyle
    var availableInputs: [AvailableInputType]
    var localization: ChatLocalization
    var onPasteImage: ((UIImage) -> Void)?
    var onPasteVideo: ((Data, String) -> Void)?
    var onPasteFileData: ((Data, String, String) -> Void)?

    var body: some View {
        PastableTextView(
            text: $text,
            placeholder: style == .message ? localization.inputPlaceholder : localization.signatureText,
            textColor: UIColor(style == .message ? theme.colors.inputText : theme.colors.inputSignatureText),
            placeholderColor: UIColor(style == .message ? theme.colors.inputPlaceholderText : theme.colors.inputSignaturePlaceholderText),
            font: .preferredFont(forTextStyle: .body),
            isFocused: globalFocusState.focus == .uuid(inputFieldId),
            onFocusChange: { focused in
                if focused {
                    globalFocusState.focus = .uuid(inputFieldId)
                }
            },
            onPasteImage: onPasteImage,
            onPasteVideo: onPasteVideo,
            onPasteFileData: onPasteFileData
        )
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 10)
        .padding(.leading, !isMediaGiphyAvailable() ? 12 : 0)
    }

    private func isMediaGiphyAvailable() -> Bool {
        return availableInputs.contains(AvailableInputType.media)
        || availableInputs.contains(AvailableInputType.giphy)
    }
}

