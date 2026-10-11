import Foundation

/// Calls `onChange` (coalesced 0.2 s) when a folder's direct contents change. Event-driven, no polling.
@MainActor
final class FolderWatcher {
    private nonisolated let source: DispatchSourceFileSystemObject?
    private let onChange: @MainActor () -> Void
    private var pending: DispatchWorkItem?
    let url: URL

    init(url: URL, onChange: @escaping @MainActor () -> Void) {
        self.url = url
        self.onChange = onChange
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { source = nil; return }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source = s
        s.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.schedule() }
        }
        s.setCancelHandler { close(fd) }
        s.resume()
    }

    deinit { source?.cancel() }

    private func schedule() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.onChange() }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }
}
