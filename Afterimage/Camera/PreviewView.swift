import AVFoundation
import SwiftUI
import UIKit

struct PreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var isMirrored = false

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.updateOrientationAndMirroring(isMirrored: isMirrored)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.previewLayer.session = session
        uiView.updateOrientationAndMirroring(isMirrored: isMirrored)
    }
}

final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    func updateOrientationAndMirroring(isMirrored: Bool) {
        guard let connection = previewLayer.connection else { return }

        if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = isMirrored
        }
    }
}
