import AVFoundation
import UIKit

/// カメラ入力の管理。iPhone/iPad 共通。解像度はフォールバックで安全に設定
final class CameraManager {

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.video.queue")

    /// セッション構築。delegate に ShotAnalyzer を渡す
    func configure(delegate: AVCaptureVideoDataOutputSampleBufferDelegate) throws {
        session.beginConfiguration()

        // 解像度フォールバック：機種で使えるものを上から試す
        for preset in [AVCaptureSession.Preset.hd1280x720,
                       .hd1920x1080,
                       .high] {
            if session.canSetSessionPreset(preset) {
                session.sessionPreset = preset
                break
            }
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .back) else {
            throw NSError(domain: "Camera", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "背面カメラが利用できません"])
        }
        let input = try AVCaptureDeviceInput(device: device)
        if session.canAddInput(input) { session.addInput(input) }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings =
            [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.setSampleBufferDelegate(delegate, queue: queue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        // 横向き固定（バスケ計測は横持ち想定）
        if let conn = videoOutput.connection(with: .video),
           conn.isVideoOrientationSupported {
            conn.videoOrientation = .landscapeRight
        }

        session.commitConfiguration()
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }
}
