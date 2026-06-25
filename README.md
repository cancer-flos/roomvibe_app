# RoomVibe

**サーバーレスP2Pチャットアプリ**

RoomVibe は、同じ空間（大学の講義室やサークルの部屋など）にいる人同士が、**インターネット（サーバー）を介さずに**、Bluetooth / Wi-Fi（Nearby Connections API）を使ってダイレクトに繋がってチャットができる Android アプリです。

---

## 特徴

- **完全サーバーレス**: インターネット接続不要。基地局もルーターも不要。
- **P2P 直接通信**: Google Nearby Connections API を使用し、BLE + Wi-Fi Direct で端末間直接通信。
- **スター型トポロジー**: 1台のホストが複数ゲストと接続。ホストがメッセージを中継することで全員に同期。
- **VIP自動再接続**: 一度接続した相手は記憶され、アプリ再起動後も完全自動で再接続。
- **LINE風UI**: 自分のメッセージは右寄せ（緑系）、相手のメッセージは左寄せ（グレー系）の吹き出し。

---

## 動作の仕組み

```
Guest1  ←→  Host  ←→  Guest2
               ↕
             Guest3
```

1. 誰か1人が「部屋を作る（Advertise）」→ **Host** になる
2. 他の人は「部屋を探す（Discover）」→ **Guest** になる
3. Host が Guest を検出し、接続を確立
4. 誰かがメッセージを送信 → Host が受信し、自分以外の全員に転送
5. 一度接続した相手は **VIPリスト** に登録され、次回からは自動接続

---

## 開発環境

| 項目 | バージョン |
|------|-----------|
| Flutter | 3.x |
| Dart | >=3.4.3 <4.0.0 |
| ターゲット | Android (minSdk 24, targetSdk 34) |
| 検証端末 | motorola edge 40 (Android 15) |

### 使用パッケージ

| パッケージ | 用途 |
|-----------|------|
| [`nearby_connections`](https://pub.dev/packages/nearby_connections) ^4.3.0 | BLE/Wi-Fi Direct P2P通信 |
| [`permission_handler`](https://pub.dev/packages/permission_handler) ^11.3.1 | Bluetooth・位置情報・Wi-Fi権限の管理 |
| [`shared_preferences`](https://pub.dev/packages/shared_preferences) ^2.3.3 | ユーザー名・VIP名簿のローカル保存 |

---

## プロジェクト構成

```
lib/
├── main.dart                          # エントリポイント
├── services/
│   └── nearby_service.dart            # Nearby Connections API ラッパー（全通信ロジック）
└── pages/
    ├── home_page.dart                 # メイン画面（Advertise/Discover/接続管理）
    └── chat_page.dart                 # チャット画面（メッセージ送受信・表示）
```

### 各ファイルの責務

| ファイル | 責務 |
|---------|------|
| `main.dart` | アプリの起動、MaterialApp 設定（9行のみ） |
| `nearby_service.dart` | BLE通信の確立・切断・メッセージ送受信・自動リカバリ・VIP管理 |
| `home_page.dart` | 端末の発見・接続・切断のUI、名前設定ダイアログ |
| `chat_page.dart` | メッセージ一覧の表示、テキスト入力・送信、吹き出しUI |

---

## セットアップ

```bash
# リポジトリをクローン
git clone https://github.com/cancer-flos/roomvibe_app.git
cd roomvibe_app

# 依存パッケージをインストール
flutter pub get

# 実機で実行（Android）
flutter run
```

### 初回起動時の注意

1. **アンインストールしてからインストール**してください（権限グループ変更のため）
2. アプリ起動後、Bluetooth・位置情報・近接デバイスの各権限を**許可**してください
3. ニックネームを入力して「決定」

---

## 使い方

### 1. 部屋を作る（Host）

1. 「部屋を作る」ボタンをタップ
2. 緑色の「部屋オープン中」表示に変わる
3. 他の端末からの接続を待機

### 2. 部屋を探す（Guest）

1. 「部屋を探す」ボタンをタップ
2. 青色の「スキャン中...」表示に変わる
3. 発見された端末がリストに表示される

### 3. 接続する（初回のみ）

1. Guest が発見リストの「入室する」をタップ
2. Host にダイアログが表示される → 「承認」
3. 両者に「接続しました」と表示される

**2回目以降**: VIPリストに登録されるため、上記の手動操作は不要。自動で接続される。

### 4. チャットする

1. 「チャットルームを開く」ボタンをタップ
2. 下部のテキストフィールドにメッセージを入力
3. 送信ボタン（または Enter）で送信

---

## 実装されている機能（フェーズ一覧）

| フェーズ | 機能 | 状態 |
|---------|------|------|
| 1 | 開発環境構築・ビルドエラー解決 | ✅ 完了 |
| 2 | Advertise / Discover 基本UI | ✅ 完了 |
| 3 | 接続リクエスト・承認ハンドシェイク | ✅ 完了 |
| 4 | チャット送受信・吹き出しUI | ✅ 完了 |
| 5 | 複数人接続・システムメッセージ | ✅ 完了 |
| 6 | 名前の永続化・isMeフラグ | ✅ 完了 |
| 7 | 自動リカバリ（切断→Advertise/Discover再開）| ✅ 完了 |
| 8 | VIPリストによる完全自動再接続 | ✅ 完了 |
| 9 | SharedPreferences永続化 + デバッグログ削除 | ✅ 完了 |
| 10 | NEARBY_WIFI_DEVICES権限対応 | ✅ 完了 |
| 11 | ホスト中継（スター型メッセージ同期） | ✅ 完了 |

---

## 技術的なポイント

### シリアライズ / デシリアライズ

メッセージは以下の流れで送受信されます：

```
送信: String → JSON(Map) → UTF-8エンコード → Uint8List → sendBytesPayload
受信: Uint8List → UTF-8デコード → JSONパース → Map → chatMessagesに追加
```

### 自動再接続の仕組み

```
切断発生
  ↓
_handleDisconnect() が呼ばれる
  ↓
接続中の端末が0台？
  ├─ Yes → isHost を確認
  │        ├─ true  → startAdvertising() を自動再開（電波発信待機）
  │        └─ false → startDiscovery() を自動再開（スキャン待機）
  └─ No  → 何もしない（他の端末とまだ接続中）
```

### VIPリストによる完全自動接続

```
初回接続成功 → _knownDeviceNames に名前を追加 → SharedPreferences に保存
  ↓
アプリ再起動 → startAdvertising/startDiscovery でVIP名簿を復元
  ↓
既知の端末を発見 → UI操作なしで requestConnection → acceptConnection
```

---

## 既知の制限 / 注意点

- **iOS未対応**: 現時点では Android のみ対応（nearby_connections は iOS でも動作しますが未検証）
- **スター型トポロジー**: Host が切断されると全員が切断される（自動リカバリで Host は再開する）
- **電波範囲**: BLE/Wi-Fi Direct の実効範囲は見通し約10〜30m程度
- **アンインストール要**: NEARBY_WIFI_DEVICES 権限追加後はアンインストール→再インストールが必要

---

## ライセンス

MIT License

Copyright (c) 2026 cancer-flos

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.