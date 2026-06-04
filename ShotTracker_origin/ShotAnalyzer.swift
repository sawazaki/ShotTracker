import AVFoundation
import Vision
import CoreMedia
import CoreGraphics

/// 人物検出（方法B）＋ タップ選択 ＋ 簡易トラッキング ＋ ROI付き軌道検出 ＋ リリース角度算出
final class ShotAnalyzer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - 外部へ渡すコールバック（UI更新用、常にメインスレッドで呼ぶ）

    /// 検出された全人物の矩形（Vision座標：左下原点・0〜1）
    var onPeopleUpdate: (([CGRect]) -> Void)?
    /// 現在選択中の人物の矩形（未選択なら nil）
    var onSelectedUpdate: ((CGRect?) -> Void)?
    /// 確定した軌道の点列（Vision座標）とリリース角度（度）
    var onTrajectory: (([CGPoint], Double) -> Void)?

    // MARK: - 内部状態

    /// タップで選択中の人物の矩形（前フレームの位置）。簡易トラッキングの基準に使う
    private var selectedBox: CGRect?
    /// 直近フレームの映像サイズ（角度のアスペクト補正に使用）
    private var imageSize: CGSize = .init(width: 1280, height: 720)
    /// 「次フレームでタップ位置から人物を選び直す」フラグとタップ座標
    private var pendingTapPoint: CGPoint?

    private let sequenceHandler = VNSequenceRequestHandler()

    // 軌道検出リクエスト（再利用する）
    private lazy var trajectoryRequest: VNDetectTrajectoriesRequest = {
        let req = VNDetectTrajectoriesRequest(frameAnalysisSpacing: .zero,
                                              trajectoryLength: 8) { [weak self] request, _ in
            self?.handleTrajectories(request)
        }
        // バスケットボールの見かけサイズで絞る（環境に応じて調整）
        req.objectMinimumNormalizedRadius = 0.01
        req.objectMaximumNormalizedRadius = 0.2
        return req
    }()

    // MARK: - 外部API

    /// プレビュー上のタップを受け取る（Vision座標に変換済みの点を渡す）
    func selectPerson(atVisionPoint point: CGPoint) {
        pendingTapPoint = point
    }

    /// 選択を解除
    func clearSelection() {
        selectedBox = nil
        DispatchQueue.main.async { [weak self] in
            self?.onSelectedUpdate?(nil)
        }
    }

    // MARK: - フレーム処理

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        imageSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                           height: CVPixelBufferGetHeight(pixelBuffer))

        // 1) 人物検出
        let humanRequest = VNDetectHumanRectanglesRequest()
        // 上半身だけでなく全身も拾いたい場合は false 寄り。環境で調整
        humanRequest.upperBodyOnly = false

        do {
            try sequenceHandler.perform([humanRequest, trajectoryRequest],
                                        on: pixelBuffer,
                                        orientation: .up)
        } catch {
            return
        }

        let people = (humanRequest.results as? [VNHumanObservation])?.map { $0.boundingBox } ?? []

        // 2) タップがあれば、その位置に最も近い人物を選択
        if let tap = pendingTapPoint {
            pendingTapPoint = nil
            if let chosen = people.min(by: {
                distance(center($0), tap) < distance(center($1), tap)
            }) {
                selectedBox = chosen
            }
        } else if let prev = selectedBox, !people.isEmpty {
            // 3) 簡易トラッキング：前フレームの選択人物に最も近い人物を選び続ける
            if let nearest = people.min(by: {
                distance(center($0), center(prev)) < distance(center($1), center(prev))
            }) {
                // 飛びすぎ（別人へ乗り換え）を防ぐため、近い場合のみ更新
                if distance(center(nearest), center(prev)) < 0.25 {
                    selectedBox = nearest
                }
            }
        }

        // 4) 選択中人物の周辺にROIを設定（次フレームの軌道検出に効く）
        if let box = selectedBox {
            let roi = CGRect(
                x: max(0, box.minX - 0.1),
                y: box.minY,
                width: min(1 - max(0, box.minX - 0.1), box.width + 0.2),
                height: min(1 - box.minY, box.height + 0.5) // 上方向に拡張
            )
            trajectoryRequest.regionOfInterest = roi
        } else {
            trajectoryRequest.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        // 5) UI更新
        DispatchQueue.main.async { [weak self] in
            self?.onPeopleUpdate?(people)
            self?.onSelectedUpdate?(self?.selectedBox)
        }
    }

    // MARK: - 軌道ハンドラ

    private func handleTrajectories(_ request: VNRequest) {
        guard let results = request.results as? [VNTrajectoryObservation] else { return }
        for trajectory in results where trajectory.confidence > 0.8 {
            let points = trajectory.detectedPoints.map { CGPoint(x: $0.x, y: $0.y) }
            guard let angle = releaseAngle(for: trajectory) else { continue }
            DispatchQueue.main.async { [weak self] in
                self?.onTrajectory?(points, angle)
            }
        }
    }

    /// リリース角度（軌道の最初の点での接線角度、アスペクト補正済み）
    private func releaseAngle(for trajectory: VNTrajectoryObservation) -> Double? {
        let coeffs = trajectory.equationCoefficients   // [a, b, c]
        let a = Double(coeffs[0])
        let b = Double(coeffs[1])

        guard let first = trajectory.detectedPoints.min(by: { $0.x < $1.x }) else { return nil }

        let slope = 2 * a * first.x + b
        // 正規化座標 → 実ピクセル比に補正
        let aspect = imageSize.height / imageSize.width
        let realSlope = slope * Double(aspect)
        let degrees = atan(realSlope) * 180 / .pi
        return abs(degrees) // リリース角の大きさ（向きに依らず正）
    }

    // MARK: - 補助

    private func center(_ r: CGRect) -> CGPoint {
        CGPoint(x: r.midX, y: r.midY)
    }
    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
