import SwiftUI

struct EditableRollTitleView: View {
    enum Style: Equatable {
        case reveal
        case archive

        var font: Font {
            switch self {
            case .reveal:
                AfterimageType.rollTitle
            case .archive:
                AfterimageType.archiveTitle
            }
        }

        var foregroundOpacity: Double {
            switch self {
            case .reveal: 0.82
            case .archive: 0.9
            }
        }
    }

    let title: String
    let style: Style
    let alignment: TextAlignment
    let onCommit: (String) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField("Roll title", text: $draft)
                    .font(style.font)
                    .multilineTextAlignment(alignment)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($isFocused)
                    .foregroundStyle(.white.opacity(style.foregroundOpacity))
                    .onSubmit(commit)
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commit() }
                    }
            } else {
                Text(title)
                    .font(style.font)
                    .multilineTextAlignment(alignment)
                    .foregroundStyle(.white.opacity(style.foregroundOpacity))
                    .lineLimit(style == .reveal ? 2 : 1)
                    .minimumScaleFactor(0.72)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: beginEditing)
                    .accessibilityAddTraits(.isButton)
            }
        }
    }

    private func beginEditing() {
        draft = title
        withAnimation(AfterimageMotion.quick) {
            isEditing = true
        }
        isFocused = true
    }

    private func commit() {
        let trimmedTitle = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        withAnimation(AfterimageMotion.quick) {
            isEditing = false
        }
        guard !trimmedTitle.isEmpty, trimmedTitle != title else { return }
        onCommit(trimmedTitle)
    }
}
