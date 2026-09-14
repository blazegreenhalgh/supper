#if SWIFT_PACKAGE
import SupperCore
#endif
import CoreData
import CloudKit

enum CloudProblem {
    static func accountMessage(_ status: CKAccountStatus) -> String? {
        switch status {
        case .available: return nil
        case .noAccount: return "Sign in to your Apple Account in iPhone Settings and enable iCloud for Supper."
        case .restricted: return "iCloud access is restricted on this iPhone. Check the account or device restrictions in Settings."
        case .temporarilyUnavailable: return "Your iCloud account is temporarily unavailable. Try again in a moment."
        case .couldNotDetermine: return "Unable to check your iCloud account. Check your connection and try again."
        @unknown default: return "iCloud is unavailable right now. Try again in a moment."
        }
    }

    static func shareResult(_ record: CKRecord?, error: Error?) -> Result<CKShare, Error> {
        if let error { return .failure(error) }
        guard let share = record as? CKShare else {
            return .failure(SupperError.invalid("iCloud did not return a sharing invitation. Try again."))
        }
        return .success(share)
    }

    static func requireShareURL(_ url: URL?) throws {
        guard let url, url.scheme == "https", url.host != nil else {
            throw SupperError.invalid("iCloud has not finished creating the invitation link. Wait a moment, then tap Share household again.")
        }
    }

    static func message(_ error: Error) -> String {
        let errors = underlyingErrors(error as NSError)
        let detail = errors.last(where: {
            $0.domain == CKErrorDomain && $0.code != CKError.Code.partialFailure.rawValue && $0.code != CKError.Code.batchRequestFailed.rawValue
        }) ?? errors.last ?? (error as NSError)
        guard detail.domain == CKErrorDomain, let code = CKError.Code(rawValue: detail.code) else {
            return detail.localizedDescription
        }
        let advice: String
        switch code {
        case .partialFailure: advice = "Some iCloud changes failed. Apple did not include the individual failure details. Copy iCloud diagnostics below to help investigate."
        case .notAuthenticated: advice = "Check your Apple Account in iPhone Settings and enable iCloud for Supper."
        case .networkUnavailable, .networkFailure: advice = "iCloud could not be reached. Check your internet connection and try again."
        case .quotaExceeded: advice = "Your iCloud storage is full. Free up storage, then try again."
        case .serviceUnavailable, .requestRateLimited, .zoneBusy: advice = "iCloud is busy right now. Wait a moment and try again."
        case .serverRecordChanged: advice = "The sharing invitation changed on iCloud. Tap Share household again to load the latest version."
        case .zoneNotFound, .unknownItem: advice = "The household's invitation is not available on iCloud yet. Wait for sync, then try again."
        case .permissionFailure: advice = "iCloud denied access to this household. Check the Apple Account and your sharing access."
        default: advice = "iCloud could not complete the request."
        }
        return "\(advice)\n\(detail.localizedDescription) (CloudKit \(detail.code))"
    }

    static func serverShare(from error: Error) -> CKShare? {
        underlyingErrors(error as NSError).compactMap {
            $0.userInfo[CKRecordChangedErrorServerRecordKey] as? CKShare
        }.first
    }

    static func diagnostics(_ error: Error) -> String {
        underlyingErrors(error as NSError).map { detail in
            var lines = ["\(detail.domain) \(detail.code): \(detail.localizedDescription)"]
            if let reason = detail.localizedFailureReason { lines.append(reason) }
            if let recovery = detail.localizedRecoverySuggestion { lines.append(recovery) }
            if detail.domain == CKErrorDomain && detail.code == CKError.Code.partialFailure.rawValue {
                let partial = (detail as? CKError)?.partialErrorsByItemID
                if partial?.isEmpty != false { lines.append("No per-record errors were supplied.") }
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private static func underlyingErrors(_ error: NSError, depth: Int = 0) -> [NSError] {
        guard depth < 6 else { return [error] }
        var result = [error]
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            result += underlyingErrors(underlying, depth: depth + 1)
        }
        if let details = error.userInfo["NSDetailedErrors"] as? [NSError] {
            for detail in details { result += underlyingErrors(detail, depth: depth + 1) }
        }
        if let partial = (error as? CKError)?.partialErrorsByItemID {
            for key in partial.keys.sorted(by: { String(describing: $0) < String(describing: $1) }) {
                if let detail = partial[key] { result += underlyingErrors(detail as NSError, depth: depth + 1) }
            }
        }
        return result
    }
}

/// Callback APIs may finish after a timeout or cancellation. Resume exactly once.
final class CloudRequestCompletion<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

enum CloudRequest {
    @MainActor
    static func run<Value>(timeout: TimeInterval = 30,
                           start: (@escaping @Sendable (Result<Value, Error>) -> Void) -> Void) async throws -> Value {
        guard timeout > 0 else {
            throw SupperError.invalid("iCloud took too long to respond. Check your connection and try again.")
        }
        let completion = CloudRequestCompletion<Value>()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                completion.install(continuation)
                let deadline = DispatchWorkItem { @Sendable in
                    completion.finish(.failure(SupperError.invalid("iCloud took too long to respond. Check your connection and try again.")))
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                start { result in
                    deadline.cancel()
                    completion.finish(result)
                }
            }
        } onCancel: {
            completion.finish(.failure(CancellationError()))
        }
    }
}
