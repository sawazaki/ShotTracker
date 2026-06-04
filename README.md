# ShotTracker セットアップ手順

複数人の中から特定の人物をタップで選択・追跡し、その人物が打ったバスケットボールの
軌道とリリース角度を計測する iOS アプリ（iPhone / iPad 両対応）。

## フォルダ構成

```
ShotTracker/
├── .devcontainer/
│   └── devcontainer.json        # Dev Container定義（Claude Code feature入り）
├── .vscode/
│   └── tasks.json               # VS Codeからxcodebuildを呼ぶビルドタスク（任意）
├── ShotTracker/                 # ← Xcodeで .swift をAdd Filesする対象
│   ├── ShotTrackerApp.swift     # エントリポイント
│   ├── CameraManager.swift      # カメラ管理
│   ├── ShotAnalyzer.swift       # 人物検出＋追跡＋軌道検出＋角度算出
│   └── CameraViewController.swift # プレビュー＋オーバーレイ描画
├── .gitignore                   # iOS/Xcode用
├── CLAUDE.md                    # Claude Code向けプロジェクト指示書
└── README.md                    # このファイル
```

> 注意：このフォルダには `.xcodeproj` は含まれません。Xcode で空の App プロジェクトを
> 作成し、`ShotTracker/` 内の4つの `.swift` を Add Files で取り込んでください
> （手順は下記「1. Xcode プロジェクトを作る」を参照）。

## 1. Xcode プロジェクトを作る

1. Xcode を開き **File > New > Project**
2. **iOS > App** を選択
3. 設定：
   - Product Name: `ShotTracker`
   - Interface: **SwiftUI**
   - Language: **Swift**
4. 作成したプロジェクトに、付属の `.swift` 4ファイルを追加（既存の `ContentView.swift` や
   自動生成された `App` ファイルは削除し、本ファイル群で置き換える）：
   - `ShotTrackerApp.swift`
   - `CameraManager.swift`
   - `ShotAnalyzer.swift`
   - `CameraViewController.swift`

## 2. iPhone / iPad 両対応にする

プロジェクト設定 > **General > Deployment Info**：
- **Supported Destinations** に iPhone と iPad の両方を含める（Universal）
- **iPad Multitasking**：カメラ利用のためフルスクリーン前提なら
  `Requires full screen` にチェックを入れてもよい
- **Device Orientation**：Landscape Left / Landscape Right を有効化
  （横持ち計測のため。Portrait を外すと向きが安定する）
- **Deployment Target**：iOS 15.0 以上を推奨

## 3. カメラ権限

プロジェクト設定 > **Info**（または Info.plist）に追加：
- Key: `Privacy - Camera Usage Description`
  (`NSCameraUsageDescription`)
- Value: `シュート軌道の計測にカメラを使用します`

これが無いとカメラ起動時にクラッシュする。

## 4. 実機ビルド

- シミュレータはカメラ非対応。**実機が必須**
- 配布しない個人利用なら、無料の Apple ID で署名可能
  - Signing & Capabilities > Team に自分の Apple ID を設定
  - 無料アカウントの場合、ビルドは **7日で失効** するので都度再ビルド
- iPhone と iPad の両方でテストするなら、それぞれを Mac に繋いでビルドする

## 5. 使い方

1. アプリ起動 → カメラが起動
2. 画面に映った人物に白い枠が表示される
3. 計測したい人物を **タップ** → 緑の太枠に変わり、その人物を追跡
4. 選択人物がシュートを打つと、黄色い軌道線と
   「リリース角度: XX.X°」が画面上部に表示される

## 6. 調整ポイント（精度が出ない場合）

`ShotAnalyzer.swift` 内の値を環境に合わせて調整：

| パラメータ | 役割 | 調整の方向 |
|---|---|---|
| `trajectoryLength`（既定8） | 軌道と認定する最小フレーム数 | 誤検出が多い→大きく / 検出が遅い→小さく |
| `objectMinimumNormalizedRadius` | ボールの最小見かけ半径 | 小さいボールを拾えない→下げる |
| `objectMaximumNormalizedRadius` | ボールの最大見かけ半径 | 人や大物を拾う→下げる |
| `confidence > 0.8`（handleTrajectories内） | 軌道の信頼度しきい値 | 誤検出が多い→上げる |
| ROIの上方向拡張 `box.height + 0.5` | 軌道検出範囲 | 高いシュートが切れる→大きく |
| 乗り換え防止 `< 0.25`（簡易トラッキング） | 別人に飛ぶのを防ぐ距離 | 追跡が外れやすい→大きく |

## 制約・注意

- **カメラは三脚等で固定**することを強く推奨。手持ちだと背景の動きを
  軌道と誤検出しやすく、人物トラッキングも不安定になる
- 選択人物が他人と長く重なる・画面外に出ると、簡易トラッキングが
  別人に乗り換わることがある。その場合は再度タップで選び直す
- `VNDetectTrajectoriesRequest` は「放物線を描く小さな物体」を拾う汎用検出。
  ボールが確実に区別できないなら、Core ML のボール検出モデル併用が次の手
