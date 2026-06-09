# ShotTracker システム仕様書

## 1. アプリ概要

### 目的
複数人が写る映像の中から、タップで選択した特定の人物を追跡し、その人物が打ったバスケットボールのシュート軌道とリリース角度を計測する iOS アプリ。

### 対象ユーザー
バスケットボール選手・コーチ（個人利用）

### 運用環境
- プラットフォーム：iPhone / iPad（Universal）
- 最小 iOS バージョン：iOS 15.0
- 画面向き：横持ち（Landscape）固定
- 配布：App Store 非公開・個人利用のみ

---

## 2. 画面構成と遷移フロー

```
起動
 └─ ホーム画面（HomeView）
       ├─ 「過去の一覧」→ 動画一覧画面（SessionListView）
       │         └─ 動画タップ → フルスクリーン再生（AVPlayerViewController）
       │                  └─ [×] で一覧に戻る
       └─ 「新規収録」→ カメラ画面（CameraViewController）※fullScreenCover
                  └─ [←] で ホームに戻る
```

### ホーム画面（HomeView）
- 黒背景 + アプリタイトル
- 2つのメニューボタン（横並び）
  - 「過去の一覧」：clock アイコン、グレー系
  - 「新規収録」：video アイコン、赤系

### 動画一覧画面（SessionListView）
- `Documents/videos/` 内の `.mov` ファイルを新しい順にリスト表示
- 各行：サムネイル（先頭フレーム）＋ 日時
- 空の場合：「録画がありません」
- タップで `AVPlayerViewController` によるフルスクリーン再生

### カメラ画面（CameraViewController）
| 位置 | 要素 | 説明 |
|---|---|---|
| 上部中央 | タイマー `00:28` | 録画中のみ表示 |
| 下部左 | `N IN A ROW` | 録画中のシュート検出数 |
| 下部中央 | `46°` + `RELEASE ANGLE` | 最新リリース角度 |
| 下部中央（角度下） | `平均: 45.2°` | 録画中の平均角度 |
| 下部右 | `⏺ REC` / `⏹ STOP` ボタン | 録画開始・停止 |
| オーバーレイ | 人物枠（白・細） | 全検出人物 |
| オーバーレイ | 選択枠（オレンジ・太） | タップで選択中の人物 |
| オーバーレイ | ゴールマーカー（水色） | 長押しで登録・更新、マーカー付近の長押しで解除するゴール位置 |
| オーバーレイ | 軌跡線（黄） | 検出されたシュート軌道。ゴール登録済みの場合はゴールまで補完（2秒で消える） |

---

## 3. ファイル構成と各クラスの責務

```
ShotTracker/
├── ShotTrackerApp.swift        — SwiftUI エントリポイント
├── HomeView.swift              — ホーム画面
├── SessionListView.swift       — 動画一覧・再生
├── CameraViewController.swift  — カメラUI・オーバーレイ・録画制御
├── CameraManager.swift         — AVCaptureSession 管理
├── ShotAnalyzer.swift          — 人物検出・軌道検出・角度算出
├── RecordingManager.swift      — 動画録画ライフサイクル
└── AngleLogger.swift           — 角度記録・平均・CSV書き出し
```

### ShotTrackerApp.swift
- `@main` エントリポイント
- `NavigationView { HomeView() }` をルートに設定（`.stack` スタイル）
- `CameraScreen`：`CameraViewController` を SwiftUI に橋渡しする `UIViewControllerRepresentable`

### HomeView.swift
- ホーム画面の SwiftUI View
- 「新規収録」は `.fullScreenCover` で `CameraScreen` を表示
- カメラ画面に `chevron.left` 戻るボタンをオーバーレイ

### SessionListView.swift
- `Documents/videos/` から `.mov` ファイルを読み込みリスト表示
- `AVAssetImageGenerator` でサムネイルを非同期生成（`Task.detached`）
- ファイル名のタイムスタンプから録画日時を復元
- `AVPlayerViewController` で動画再生

### CameraViewController.swift
- `viewDidLoad`：UI構築・コールバック配線・カメラ設定（`configure`のみ）
- `viewDidAppear`：`camera.start()`
- `viewWillDisappear`：`camera.stop()` + タイマー停止
- `handleTap`：UIKit座標 → Vision座標に変換して `analyzer.selectPerson()` を呼ぶ
- `handleGoalLongPress`：長押し位置を Vision 座標に変換し、ゴール位置として登録・更新。既存マーカー付近の長押しなら解除
- `redraw()`：全オーバーレイを毎フレーム再描画
- `handleRecTap()`：録画開始時に `logger.reset()` + `recording.startRecording()`
- `bindAnalyzer()`：`onTrajectory` コールバックで角度表示・集計を更新
- `bindRecording()`：`onRecordingStopped` コールバックで CSV 保存

### CameraManager.swift
- `configure(delegate:movieOutput:)`：セッションを構築（`beginConfiguration` / `commitConfiguration` 内でまとめて設定）
  - 解像度フォールバック：`hd1280x720` → `hd1920x1080` → `high`
  - `AVCaptureVideoDataOutput`：Vision 解析用（`32BGRA` 形式、カメラキューで処理）
  - `AVCaptureMovieFileOutput`：録画用（`AVCaptureVideoDataOutput` と並列共存可）
  - 両 Output の orientation を `.landscapeRight` 固定
- `start()` / `stop()`：セッションの開始・停止（カメラキューで非同期実行）

### ShotAnalyzer.swift
- `AVCaptureVideoDataOutputSampleBufferDelegate` の実装
- フレームごとに2つの Vision リクエストを実行：
  1. `VNDetectRectanglesRequest`（`minimumAspectRatio = 0.1`、`maximumObservations = 10`）
  2. `VNDetectTrajectoriesRequest`（`trajectoryLength = 8`）
- タップ選択：`pendingTapPoint` に Vision 座標を蓄積し、次フレームで最近傍の人物を選択
- 簡易トラッキング：前フレーム選択人物との距離が `0.25` 未満の最近傍人物を追跡
- ROI：選択人物の周囲（上方向に `+0.5` 拡張）に軌道検出を絞り込む
- 全コールバックをメインスレッドで呼び出す

### RecordingManager.swift
- `AVCaptureMovieFileOutput` を所有
- `startRecording()`：`Documents/videos/recording_[timestamp].mov` に直接保存
- `AVCaptureFileOutputRecordingDelegate` extension で `isRecording` フラグとコールバックを管理

### AngleLogger.swift
- `record(_:)`：角度を配列に追記
- `average`：現在の平均値（計算プロパティ）
- `saveCSV()`：`Documents/angles_yyyyMMdd_HHmmss.csv` に書き出し
  - フォーマット：1行目 `angle`、以降1行1角度、末尾に `average,XX.XX`

---

## 4. データフロー

```
カメラフレーム（カメラキュー）
  └─ ShotAnalyzer.captureOutput()
        1. VNDetectHumanRectanglesRequest → people[]
        2. タップがあれば近い人物を選択、なければ簡易トラッキング
        3. 選択人物の周辺に ROI を設定
        4. VNDetectTrajectoriesRequest → handleTrajectories() → releaseAngle()
        5. メインスレッドでコールバック呼び出し

長押し（メインスレッド）
  └─ CameraViewController.handleGoalLongPress()
        1. UIKit座標 → Vision座標に変換
        2. 既存マーカー付近なら goalPoint を解除、それ以外は goalPoint として保存
        3. 軌道描画時に検出点列をゴール方向に並べ、終点として goalPoint を追加
             onPeopleUpdate(people)
             onSelectedUpdate(selectedBox)
             onTrajectory(points, angle)

メインスレッド（CameraViewController）
  ├─ onPeopleUpdate  → people[] を更新 → redraw()
  ├─ onSelectedUpdate → selected を更新 → redraw()
  └─ onTrajectory    → angleValueLabel 更新
                      → 録画中なら logger.record(angle) + shotCount++
                      → redraw()
                      → 2秒後に軌跡をクリア → redraw()
```

---

## 5. 主要アルゴリズム

### リリース角度の算出（ShotAnalyzer.releaseAngle）

`VNDetectTrajectoriesRequest` は検出した軌跡を二次曲線でフィットし、`equationCoefficients` として係数 `[a, b, c]`（`y = ax² + bx + c`）を返す。

```swift
// 軌跡の最初の点（最小 x）での接線の傾きを計算
let slope = 2 * a * firstPoint.x + b

// 正規化座標のアスペクト比を補正（x と y のスケールが異なるため）
let realSlope = slope * (imageHeight / imageWidth)

// 度数に変換（符号によらず正の値）
let degrees = abs(atan(realSlope) * 180 / π)
```

**補正が必要な理由：** Vision の正規化座標は 0〜1 に収まるが、映像の横幅と縦幅は実際には異なるピクセル数。補正しないと見かけの角度が実際の角度とずれる。

**カリブレーション不要の理由：** カメラを水平・横持ちに固定すれば、アスペクト比補正のみで実際の角度に近い値が得られる。絶対精度が必要な場合はカメラを水平に固定することが前提条件。

### 人物トラッキング（ShotAnalyzer）

1. タップ時：Vision 座標空間で全検出人物との距離を計算し、最近傍を選択
2. 次フレーム以降：前フレームの選択人物と各人物の中心距離を比較
   - 最近傍が `0.25`（正規化距離）未満 → 選択を更新（同一人物として追跡）
   - `0.25` 以上 → 更新しない（別人への乗り換えを防ぐ）

---

## 6. データ保存仕様

### 動画ファイル
| 項目 | 内容 |
|---|---|
| 保存先 | `[Documents]/videos/recording_[Unix timestamp].mov` |
| フォーマット | QuickTime Movie（H.264 / HEVC、音声なし） |
| 削除 | アプリ削除時に消える（iCloud バックアップ対象外） |

### 角度CSVファイル
| 項目 | 内容 |
|---|---|
| 保存先 | `[Documents]/angles_yyyyMMdd_HHmmss.csv` |
| タイミング | 録画停止時に自動生成 |
| フォーマット | 1行目：`angle`、2行目以降：各シュートの角度、末尾：`average,XX.XX` |
| 閲覧方法 | iOS の「ファイル」アプリ → ShotTracker |

### サンプル CSV
```
angle
45.23
43.10
47.82
44.55
average,45.18
```

---

## 7. フレームワーク依存関係

| フレームワーク | 利用ファイル | 用途 |
|---|---|---|
| `AVFoundation` | CameraManager, CameraViewController, RecordingManager, SessionListView | カメラセッション、録画、動画再生 |
| `Vision` | ShotAnalyzer | 矩形検出、軌道検出 |
| `AVKit` | SessionListView | `AVPlayerViewController` による動画再生 |
| `UIKit` | CameraViewController | UI構築、オーバーレイ描画 |
| `SwiftUI` | ShotTrackerApp, HomeView, SessionListView | 画面構成 |
| `CoreMedia` | ShotAnalyzer | `CMSampleBuffer`, `CMTime` |
| `CoreGraphics` | ShotAnalyzer | `CGRect`, `CGPoint` |

---

## 8. 座標系の注意事項

アプリ内では3つの座標系が混在する。変換を誤るとタップ選択や描画がずれる。

| 座標系 | 原点 | スケール | 使用箇所 |
|---|---|---|---|
| Vision 座標 | 左下 | 0〜1 正規化 | `ShotAnalyzer` 内部、`onPeopleUpdate` / `onTrajectory` の引数 |
| captureDevicePoint | 左上 | 0〜1 正規化 | `previewLayer` の座標変換 API |
| UIKit 座標 | 左上 | ピクセル | `CameraViewController` の描画・タップ処理 |

### 変換ルール

**タップ（UIKit → Vision）**
```swift
let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: tapPoint)
let visionPoint = CGPoint(x: devicePoint.x, y: 1 - devicePoint.y)  // y 反転
```

**描画（Vision → UIKit）**
```swift
let devicePoint = CGPoint(x: visionPoint.x, y: 1 - visionPoint.y)  // y 反転
let layerPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: devicePoint)
```

**矩形の変換**
Vision 矩形は左下原点なので、`minY`/`maxY` が UIKit と逆になる点に注意：
```swift
let topLeftVision    = CGPoint(x: rect.minX, y: rect.maxY)  // Vision の上端 = maxY
let bottomRightVision = CGPoint(x: rect.maxX, y: rect.minY)  // Vision の下端 = minY
```

---

## 9. 調整可能パラメータ一覧（ShotAnalyzer.swift）

| パラメータ | デフォルト値 | 説明 |
|---|---|---|
| `trajectoryLength` | `8` | 軌道と認定するのに必要な最小フレーム数 |
| `objectMinimumNormalizedRadius` | `0.01` | ボールとして検出する最小サイズ（正規化） |
| `objectMaximumNormalizedRadius` | `0.06` | ボールとして検出する最大サイズ（正規化） |
| `confidence > 0.3` | `0.3` | 軌道の信頼度しきい値（`handleTrajectories` 内） |
| ROI 上方向拡張 | `box.height + 0.5` | 選択人物周囲の ROI を上方向に拡張する量 |
| トラッキング乗り換え距離 | `0.25` | この距離を超えた場合は別人として無視 |

---

## 10. ビルド・開発環境

### 開発ツール分担
| 作業 | ツール |
|---|---|
| Swift ファイルの編集 | VS Code + Claude Code（このリポジトリ） |
| ビルド・実機転送 | Xcode（コード署名・プロビジョニングのため） |
| `.xcodeproj` 管理 | Xcode 専用（リポジトリには含まない） |

### Xcode プロジェクトのセットアップ手順
1. Xcode で新規 App プロジェクトを作成（SwiftUI, iOS 15.0+）
2. `ShotTracker/` 内の 8 つの `.swift` ファイルを「Add Files to ...」でプロジェクトに追加
3. Info.plist に以下のキーを追加：
   - `NSCameraUsageDescription`：カメラへのアクセス理由

### Info.plist 必須キー
```xml
<key>NSCameraUsageDescription</key>
<string>シュート計測のためカメラを使用します</string>
```

### 検証用ビルドコマンド（シンタックス確認用）
```bash
xcodebuild -project ShotTracker.xcodeproj -scheme ShotTracker \
  -destination "platform=iOS Simulator,name=iPhone 15" build
```
