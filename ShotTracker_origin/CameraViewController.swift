import UIKit
import AVFoundation

/// プレビュー＋オーバーレイ描画。タップで人物選択。iPhone/iPad共通
final class CameraViewController: UIViewController {

    private let camera = CameraManager()
    private let analyzer = ShotAnalyzer()
    private var previewLayer: AVCaptureVideoPreviewLayer!

    // オーバーレイ用レイヤー
    private let overlayLayer = CALayer()
    // 角度表示ラベル
    private let angleLabel = UILabel()

    // 最新の検出データ
    private var people: [CGRect] = []
    private var selected: CGRect?
    private var trajectoryPoints: [CGPoint] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPreview()
        setupOverlay()
        setupLabel()
        setupGesture()
        bindAnalyzer()
        setupCamera()
    }

    // MARK: - セットアップ

    private func setupPreview() {
        previewLayer = AVCaptureVideoPreviewLayer(session: camera.session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
    }

    private func setupOverlay() {
        overlayLayer.frame = view.bounds
        view.layer.addSublayer(overlayLayer)
    }

    private func setupLabel() {
        angleLabel.textColor = .white
        angleLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .bold)
        angleLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        angleLabel.textAlignment = .center
        angleLabel.layer.cornerRadius = 8
        angleLabel.clipsToBounds = true
        angleLabel.text = "人物をタップして選択"
        angleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(angleLabel)
        NSLayoutConstraint.activate([
            angleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            angleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            angleLabel.heightAnchor.constraint(equalToConstant: 44),
            angleLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])
    }

    private func setupGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tap)
    }

    private func setupCamera() {
        do {
            try camera.configure(delegate: analyzer)
            camera.start()
        } catch {
            angleLabel.text = "カメラ初期化エラー"
        }
    }

    // MARK: - Analyzer バインド

    private func bindAnalyzer() {
        analyzer.onPeopleUpdate = { [weak self] boxes in
            self?.people = boxes
            self?.redraw()
        }
        analyzer.onSelectedUpdate = { [weak self] box in
            self?.selected = box
            self?.redraw()
        }
        analyzer.onTrajectory = { [weak self] points, angle in
            self?.trajectoryPoints = points
            self?.angleLabel.text = String(format: "リリース角度: %.1f°", angle)
            self?.redraw()
            // 軌道は少し残してから消す
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self?.trajectoryPoints = []
                self?.redraw()
            }
        }
    }

    // MARK: - タップ → 人物選択

    @objc private func handleTap(_ gr: UITapGestureRecognizer) {
        let p = gr.location(in: view)
        // プレビュー(UIKit座標) → Vision座標(左下原点・0〜1)
        // previewLayer の座標変換を使うと resizeAspectFill のズレを補正できる
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: p)
        // captureDevicePoint は (0,0)=左上 / (1,1)=右下。Vision は左下原点なので y を反転
        let visionPoint = CGPoint(x: devicePoint.x, y: 1 - devicePoint.y)
        analyzer.selectPerson(atVisionPoint: visionPoint)
    }

    // MARK: - レイアウト

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        overlayLayer.frame = view.bounds
    }

    // MARK: - 描画

    private func redraw() {
        overlayLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

        // 人物枠（白・細）
        for box in people {
            let rect = layerRect(from: box)
            overlayLayer.addSublayer(strokeRect(rect, color: .white, width: 1, alpha: 0.4))
        }
        // 選択枠（緑・太）
        if let sel = selected {
            let rect = layerRect(from: sel)
            overlayLayer.addSublayer(strokeRect(rect, color: .green, width: 3, alpha: 1))
        }
        // 軌道（黄）
        if trajectoryPoints.count > 1 {
            let path = UIBezierPath()
            let pts = trajectoryPoints.map { layerPoint(from: $0) }
            path.move(to: pts[0])
            pts.dropFirst().forEach { path.addLine(to: $0) }
            let line = CAShapeLayer()
            line.path = path.cgPath
            line.strokeColor = UIColor.yellow.cgColor
            line.fillColor = UIColor.clear.cgColor
            line.lineWidth = 3
            overlayLayer.addSublayer(line)
        }
    }

    // Vision座標(左下原点) の点 → プレビュー上の点
    private func layerPoint(from visionPoint: CGPoint) -> CGPoint {
        // captureDevicePoint は左上原点なので y を戻す
        let devicePoint = CGPoint(x: visionPoint.x, y: 1 - visionPoint.y)
        return previewLayer.layerPointConverted(fromCaptureDevicePoint: devicePoint)
    }

    // Vision座標の矩形 → プレビュー上の矩形
    private func layerRect(from visionRect: CGRect) -> CGRect {
        let topLeftVision = CGPoint(x: visionRect.minX, y: visionRect.maxY)
        let bottomRightVision = CGPoint(x: visionRect.maxX, y: visionRect.minY)
        let tl = layerPoint(from: topLeftVision)
        let br = layerPoint(from: bottomRightVision)
        return CGRect(x: min(tl.x, br.x), y: min(tl.y, br.y),
                      width: abs(br.x - tl.x), height: abs(br.y - tl.y))
    }

    private func strokeRect(_ rect: CGRect, color: UIColor,
                            width: CGFloat, alpha: CGFloat) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = UIBezierPath(roundedRect: rect, cornerRadius: 6).cgPath
        layer.strokeColor = color.withAlphaComponent(alpha).cgColor
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = width
        return layer
    }
}
