import SwiftUI

struct NotesSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Notes") {
                FolderPicker(title: "Write notes to", url: $settings.notesFolder)
                Picker("Font size", selection: $settings.noteFontSize) {
                    ForEach(AppSettings.noteFontSizes, id: \.self) { Text("\(Int($0)) pt").tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }
}
