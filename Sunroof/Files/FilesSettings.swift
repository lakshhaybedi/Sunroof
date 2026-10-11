import SwiftUI

struct FilesSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Files") {
                FolderPicker(title: "Store files in", url: $settings.filesFolder)
            }
        }
        .formStyle(.grouped)
    }
}
