import Foundation

/// Carries the result back to the page that started the operation.
public enum LibraryActionResult: Sendable, Equatable {
    case success
    case failure(String)

    public var errorMessage: String? {
        if case .failure(let message) = self { return message }
        return nil
    }
}

enum FileOperationFailure {
    static func message(for error: Error, operation: String) -> String? {
        if error is CancellationError { return nil }
        let value = error as NSError
        if value.domain == NSCocoaErrorDomain && value.code == CocoaError.Code.userCancelled.rawValue { return nil }
        return "\(operation)未完成：\(error.localizedDescription)"
    }
}

extension AppState {
    func actionFailure(_ message: String) -> LibraryActionResult {
        showFailure(message)
        return .failure(message)
    }
}
