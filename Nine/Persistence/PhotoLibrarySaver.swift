import Photos
import UIKit

enum PhotoLibrarySaver {
    static func save(images: [UIImage]) async throws {
        guard !images.isEmpty else { return }

        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            throw PhotoLibraryError.authorizationDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                images.forEach { image in
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
            } completionHandler: { succeeded, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if succeeded {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: PhotoLibraryError.saveFailed)
                }
            }
        }
    }
}

enum PhotoLibraryError: LocalizedError {
    case authorizationDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .authorizationDenied: return "Photo library access is needed to save developed exposures."
        case .saveFailed: return "The developed images could not be saved to Photos."
        }
    }
}
