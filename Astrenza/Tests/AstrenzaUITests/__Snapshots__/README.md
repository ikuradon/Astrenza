# Timeline UI Snapshot Baselines

Timeline Rowの外観基準は、実際のSimulator compositorを使い、次の環境でのみ生成・比較します。

- Simulator: iPhone 17
- Runtime: iOS 26.5
- Render scale: 3x
- Color scheme: Dark
- Dynamic Type: Large
- Locale: `en_US_POSIX`

基準画像を意図的に更新する場合だけ、次を実行します。

```sh
xcodebuild test \
  -project Astrenza.xcodeproj \
  -scheme Astrenza \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:AstrenzaUITests/TimelineSnapshotUITests \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG ASTRENZA_RECORD_SNAPSHOTS'
```

通常のテストは基準画像を変更せず、連続するcompositor frameの一致、RGBA pixel差分、およびmetadata/OGP後着時の同一画面上での可視更新を検証します。
