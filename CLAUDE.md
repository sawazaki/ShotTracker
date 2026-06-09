# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# ShotTracker — プロジェクト指示書

## 概要
複数人が写る映像の中から、タップで選択した特定の人物を追跡し、その人物が打った
バスケットボールのシュート軌道とリリース角度を計測する iOS アプリ。
個人利用・ローカル運用のみ（App Store 配布予定なし）。

## 開発環境・運用ルール（重要）
- **編集・Git管理・リファクタは VS Code 上の Claude Code（このCLI）で行う**
- **ビルドと実機転送は Xcode 専用**（コード署名・プロビジョニングのため）
- したがって、このCLIは `.swift` の編集まで担当し、ビルドは行わない
  （`xcodebuild` の実行を求められた場合のみ実行可。通常は不要）
- 新規 `.swift` ファイルを追加したら、Xcode のプロジェクトに登録が必要な旨を
  必ずユーザーに伝えること（VS Code 追加分は .xcodeproj に自動登録されない）
- `.xcodeproj` はリポジトリに含まれない。ユーザーが Xcode で空の App プロジェクトを
  作成し、`ShotTracker/` 内の8つの `.swift` を Add Files で取り込む運用

## ビルドコマンド（検証用）
シンタックス確認程度に使う。実機転送は Xcode で行うこと。

```bash
# VS Code タスクとして定義済み（Cmd+Shift+B）
xcodebuild -project ShotTracker.xcodeproj -scheme ShotTracker \
  -destination "platform=iOS Simulator,name=iPhone 15" build

xcodebuild -project ShotTracker.xcodeproj -scheme ShotTracker clean
```

## ターゲット
- iPhone / iPad 両対応（Universal）
- iOS 15.0 以上
- 横持ち（Landscape）前提

## アーキテクチャ

### コンポーネント
- `ShotTrackerApp.swift` — SwiftUI エントリポイント。`HomeView` を root とする `NavigationView` を表示。`CameraScreen`（`UIViewControllerRepresentable`）も定義
- `HomeView.swift` — ホーム画面。「過去の一覧」「新規収録」の2ボタン。「新規収録」は `.fullScreenCover` で `CameraScreen` を開く
- `SessionListView.swift` — `Documents/videos/` 内の `.mov` 一覧と再生（`AVPlayerViewController`）
- `CameraManager.swift` — `AVCaptureSession` の構築・起動・停止。解像度フォールバックあり（720p→1080p→high の順に試す）。横向き固定設定もここ
- `ShotAnalyzer.swift` — `AVCaptureVideoDataOutputSampleBufferDelegate` の実装。人物検出・選択・簡易トラッキング・軌道検出・リリース角度算出をすべて担当
- `CameraViewController.swift` — 上クラスを束ねるコーディネータ。プレビューレイヤー・オーバーレイ描画・タップジェスチャー処理・録画制御
- `RecordingManager.swift` — `AVCaptureMovieFileOutput` を所有。録画開始・停止・`Documents/videos/` への保存を管理
- `AngleLogger.swift` — リリース角度の収集・平均計算・CSV書き出し（`Documents/angles_*.csv`）

### データフロー
```
カメラフレーム（カメラキュー）
  → ShotAnalyzer.captureOutput()
      1) VNDetectHumanRectanglesRequest  → people[]
      2) タップがあれば近い人物を選択 / なければ簡易トラッキング
      3) 選択人物の周辺に regionOfInterest を設定
      4) VNDetectTrajectoriesRequest → handleTrajectories() → リリース角度算出
      5) コールバックをメインスレッドで呼ぶ
          onPeopleUpdate / onSelectedUpdate / onTrajectory / onFrameUpdate
  → CameraViewController（メインスレッド）
      → overlayLayer に人物枠・選択枠・軌道を再描画
      → angleLabel に角度テキストを表示
      → 録画中なら AngleLogger.record(angle) でデータ収集
  → 録画停止時
      → RecordingManager がファイル保存
      → AngleLogger.saveCSV() で CSV 書き出し
```

### フレームワーク依存
- `AVFoundation` — CameraManager, CameraViewController, RecordingManager, SessionListView
- `AVKit` — SessionListView（AVPlayerViewController による動画再生）
- `Vision` — ShotAnalyzer（VNDetectHumanRectanglesRequest, VNDetectTrajectoriesRequest）
- `CoreMedia / CoreGraphics` — ShotAnalyzer
- `UIKit` — CameraViewController
- `SwiftUI` — ShotTrackerApp, HomeView, SessionListView

## 座標系の注意（バグの温床なので厳守）
- Vision座標：左下原点・0〜1 の正規化
- captureDevicePoint：左上原点
- UIKit：左上原点・ピクセル
- 座標変換は `previewLayer.layerPointConverted` / `captureDevicePointConverted` を使う
- タップ変換：UIKit点 → `captureDevicePointConverted` → y を反転 → Vision点
- 描画変換：Vision矩形の角を y 反転してから `layerPointConverted` でUIKit点へ
- 角度計算では x/y の正規化尺度が異なるため、必ず映像アスペクト比で傾きを補正する
  （`realSlope = slope * (height / width)`）

## コーディング方針
- 既存の構造・命名を尊重し、targeted な差分で修正する（全面書き換えはしない）
- 検出ロジックは正規化座標で完結させ、デバイス依存を持ち込まない
- 日本語コメントは既存スタイル（簡潔・事実ベース）に合わせる
- UI更新は必ずメインスレッドで行う

## よく出る調整パラメータ（ShotAnalyzer.swift）
- `upperBodyOnly`（既定 `false`）— `false`: 全身シルエットで判定。広い条件で検出できる。`true`: 頭・肩のみで判定（より厳しい条件）
- `trajectoryLength`（軌道認定の最小フレーム数、既定8）
- `objectMinimumNormalizedRadius`（既定 `0.01`）/ `objectMaximumNormalizedRadius`（既定 `0.06`）— ボールの見かけサイズ絞り込み
- `confidence > 0.3`（handleTrajectories内、軌道の信頼度しきい値）
- ROIの上方向拡張量 `box.height + 0.5`
- 簡易トラッキングの乗り換え防止距離 `< 0.25`
