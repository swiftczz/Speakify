import SwiftUI

package struct SpeechCommandActions {
    var canGenerate: Bool
    var isGenerating: Bool
    var isPlaying: Bool
    var play: () -> Void
    var stop: () -> Void
    var cancel: () -> Void
    var export: () -> Void
    var focusEditor: () -> Void

    package init(
        canGenerate: Bool,
        isGenerating: Bool,
        isPlaying: Bool,
        play: @escaping () -> Void,
        stop: @escaping () -> Void,
        cancel: @escaping () -> Void,
        export: @escaping () -> Void,
        focusEditor: @escaping () -> Void
    ) {
        self.canGenerate = canGenerate
        self.isGenerating = isGenerating
        self.isPlaying = isPlaying
        self.play = play
        self.stop = stop
        self.cancel = cancel
        self.export = export
        self.focusEditor = focusEditor
    }
}

extension FocusedValues {
    @Entry package var speechActions: SpeechCommandActions?
}

package struct SpeechCommands: Commands {
    @FocusedValue(\.speechActions) private var actions

    package init() {}

    package var body: some Commands {
        CommandMenu(Text(verbatim: L10n.string("Speech", defaultValue: "Speech"))) {
            Button {
                guard let actions else { return }
                if actions.isGenerating {
                    actions.cancel()
                } else if actions.isPlaying {
                    actions.stop()
                } else {
                    actions.play()
                }
            } label: {
                Text(verbatim: playCommandTitle)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(playCommandIsDisabled)

            Button {
                actions?.export()
            } label: {
                Text(verbatim: L10n.string("Export Audio…", defaultValue: "Export Audio…"))
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(actions?.canGenerate != true)

            Divider()

            Button {
                actions?.focusEditor()
            } label: {
                Text(verbatim: L10n.string("Focus Editor", defaultValue: "Focus Editor"))
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(actions == nil)
        }
    }

    private var playCommandTitle: String {
        if actions?.isGenerating == true {
            return L10n.string("Cancel Generation", defaultValue: "Cancel Generation")
        }
        if actions?.isPlaying == true {
            return L10n.string("Stop", defaultValue: "Stop")
        }
        return L10n.string("Play", defaultValue: "Play")
    }

    private var playCommandIsDisabled: Bool {
        guard let actions else { return true }
        return actions.canGenerate == false
            && actions.isPlaying == false
            && actions.isGenerating == false
    }
}
