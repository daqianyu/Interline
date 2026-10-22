import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let interlineBackup = UTType(exportedAs: "com.interline.backup", conformingTo: .data)
}

struct BackupFileExporter: UIViewControllerRepresentable {
    let backup: BackupExport
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(backup: backup, onFinish: onFinish) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [backup.url], asCopy: true)
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        // The picker can still be reading when SwiftUI starts dismissing its sheet.
        let backup: BackupExport
        let onFinish: () -> Void
        init(backup: BackupExport, onFinish: @escaping () -> Void) { self.backup = backup; self.onFinish = onFinish }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onFinish() }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onFinish() }
    }
}
