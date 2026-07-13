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

    private var lastMirroringState = false

    override func layoutSubviews() {
        super.layoutSubviews()
        updateOrientationAndMirroring(isMirrored: lastMirroringState)
    }

    func updateOrientationAndMirroring(isMirrored: Bool) {
        lastMirroringState = isMirrored
        guard let connection = previewLayer.connection else { return }

        NineCameraConnectionConfiguration.apply(
            to: connection,
            position: isMirrored ? .front : .back
        )
    }
}
