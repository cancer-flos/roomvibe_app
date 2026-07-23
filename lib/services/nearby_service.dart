import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Nearby Connections API をラップするサービスクラス。
///
/// 発見・広告・接続・ペイロードのコールバックを一元管理し、
/// UI 側はこのクラスのメソッドを呼ぶだけで操作できる。
class NearbyService {
  static const String serviceId = "com.example.roomvibe.p2p";

  /// SharedPreferences にVIP名簿を保存するキー
  static const String _vipPrefKey = "vip_device_names";

  // ---------- チャットメッセージ ----------

  /// 送信者名とテキストのペアのリスト
  final List<Map<String, String>> chatMessages = [];

  /// メッセージ一覧が更新されたときにUIへ通知するコールバック
  VoidCallback? onChatMessagesUpdated;

  // ---------- 内部状態 ----------

  /// 自身の表示名
  String? _myDisplayName;

  /// 最後に Advertise / Discover に使った表示名（自動リカバリ用）
  String? _lastDisplayName;

  /// 自身が Host（Advertise中）か Guest（Discover中）かを示すフラグ
  ///
  /// 切断時の自動リカバリ（再接続待機状態への復帰）の際に、
  /// どちらのロールで再開すべきかを判断するために使用する。
  bool isHost = false;

  /// 現在接続中のエンドポイントID一覧
  final List<String> _connectedEndpointIds = [];

  /// エンドポイントID → 表示名 のマッピング
  /// onConnectionInitiated で名前を保存し、切断時に参照する
  final Map<String, String> _endpointNames = {};

  /// 受信中のファイルペイロードを一時的に記録するマップ。
  /// key: payload.id, value: payload.uri（ファイルの一時保存先URI）
  /// onPayloadReceived(FILE) でセットし、onPayloadTransferUpdate(SUCCESS) で参照・削除する。
  final Map<int, String> _incomingFiles = {};

  /// ファイル転送中（送受信問わず）であることをUIに通知するためのValueNotifier。
  final ValueNotifier<bool> isTransferring = ValueNotifier(false);

  /// 過去に接続が成功した相手の表示名の集合。
  ///
  /// この内容は SharedPreferences に永続化されており、
  /// アプリ再起動後も自動再接続が機能する。
  /// 切断後に同じ相手が再発見された場合、この Set に名前が含まれていると
  /// UI操作を一切介さずに自動的に requestConnection / acceptConnection を実行する。
  final Set<String> _knownDeviceNames = {};

  /// VIP名簿を一度でも SharedPreferences から読み込んだかを示すフラグ。
  /// startAdvertising / startDiscovery の重複読み込みを防ぐ。
  bool _vipNamesLoaded = false;

  // ---------- コールバック（UI側でセットする） ----------

  /// 発見側：端末が見つかった
  void Function(String endpointId, String endpointName)? onEndpointFound;

  /// 発見側：端末を見失った（endpointId は null の可能性あり）
  void Function(String? endpointId)? onEndpointLost;

  /// 両側：接続リクエストを受信した
  void Function(String endpointId, ConnectionInfo info)?
      onConnectionInitiated;

  /// 両側：接続結果が確定した
  void Function(String endpointId, Status status)? onConnectionResult;

  /// 両側：切断された
  void Function(String endpointId)? onDisconnected;

  /// 両側：ペイロード（データ）を受信した
  void Function(String endpointId, Payload payload)? onPayloadReceived;

  /// 両側：ペイロード転送の進捗
  void Function(String endpointId, PayloadTransferUpdate update)?
      onPayloadTransferUpdate;

  // ---------- 表示名 ----------

  /// 自身の表示名
  String? get myDisplayName => _myDisplayName;

  /// 自身の表示名を設定する（チャット送信時のsender名として使用）
  void setDisplayName(String name) {
    _myDisplayName = name;
  }

  // ---------- VIP名簿の永続化 ----------

  /// SharedPreferencesAsync からVIP名簿を読み込み、_knownDeviceNames に復元する。
  ///
  /// SharedPreferencesAsync は SharedPreferences と違い、
  /// getInstance() のような非同期ファクトリが不要で、直接インスタンス化できる。
  /// 初回のみ実行される（_vipNamesLoaded でガード）。
  Future<void> _loadVipNames() async {
    if (_vipNamesLoaded) return;
    _vipNamesLoaded = true;

    final prefs = SharedPreferencesAsync();
    final saved = await prefs.getStringList(_vipPrefKey);
    if (saved != null) {
      _knownDeviceNames.addAll(saved);
    }
  }

  /// _knownDeviceNames の内容を SharedPreferencesAsync に保存する。
  /// Set → List に変換してから書き込む。
  Future<void> _saveVipNames() async {
    final prefs = SharedPreferencesAsync();
    await prefs.setStringList(_vipPrefKey, _knownDeviceNames.toList());
  }

  // ---------- 公開メソッド ----------

  /// Advertise（部屋を作る）を開始する
  Future<bool> startAdvertising(String displayName) async {
    isHost = true;
    _lastDisplayName = displayName;
    await _loadVipNames();
    return await Nearby().startAdvertising(
      displayName,
      Strategy.P2P_CLUSTER,
      onConnectionInitiated: _onAdvertConnectionInitiated,
      onConnectionResult: (id, status) {
        _onConnectionResult(id, status);
        onConnectionResult?.call(id, status);
      },
      onDisconnected: (id) {
        _handleDisconnect(id);
        onDisconnected?.call(id);
      },
      serviceId: serviceId,
    );
  }

  /// Advertise を停止する
  Future<void> stopAdvertising() async {
    await Nearby().stopAdvertising();
  }

  /// Discover（部屋を探す）を開始する
  Future<bool> startDiscovery(String displayName) async {
    isHost = false;
    _lastDisplayName = displayName;
    await _loadVipNames();
    return await Nearby().startDiscovery(
      displayName,
      Strategy.P2P_CLUSTER,
      onEndpointFound: _onDiscoverEndpointFound,
      onEndpointLost: (id) => onEndpointLost?.call(id),
      serviceId: serviceId,
    );
  }

  /// Discover を停止する
  Future<void> stopDiscovery() async {
    await Nearby().stopDiscovery();
  }

  /// 相手に接続リクエストを送信する
  Future<bool> requestConnection(
    String displayName,
    String endpointId,
  ) async {
    return await Nearby().requestConnection(
      displayName,
      endpointId,
      onConnectionInitiated: (id, info) {
        _endpointNames[id] = info.endpointName;
        onConnectionInitiated?.call(id, info);
      },
      onConnectionResult: (id, status) {
        _onConnectionResult(id, status);
        onConnectionResult?.call(id, status);
      },
      onDisconnected: (id) {
        _handleDisconnect(id);
        onDisconnected?.call(id);
      },
    );
  }

  /// 接続を承認する
  Future<bool> acceptConnection(String endpointId) async {
    return await Nearby().acceptConnection(
      endpointId,
      onPayLoadRecieved: (id, payload) =>
          _handlePayloadReceived(id, payload),
      onPayloadTransferUpdate: (eid, update) =>
          _handlePayloadTransferUpdate(eid, update),
    );
  }

  /// 接続を拒否する
  Future<bool> rejectConnection(String endpointId) async {
    return await Nearby().rejectConnection(endpointId);
  }

  /// 特定のエンドポイントから切断する
  Future<void> disconnectFromEndpoint(String endpointId) async {
    _connectedEndpointIds.remove(endpointId);
    await Nearby().disconnectFromEndpoint(endpointId);
  }

  /// すべてのエンドポイントを切断する
  Future<void> stopAllEndpoints() async {
    _connectedEndpointIds.clear();
    await Nearby().stopAllEndpoints();
  }

  /// 画像ファイルを接続中の全端末に送信する
  ///
  /// 1. 指定された filePath の画像ファイルを sendFilePayload で各端末に送信
  /// 2. 自分自身には届かないため、ローカルエコーとして chatMessages に追加
  Future<void> sendImagePayload(String filePath) async {
    if (_myDisplayName == null) return;
    if (_connectedEndpointIds.isEmpty) return;

    isTransferring.value = true;

    final now = _formatTime(DateTime.now());

    for (final endpointId in _connectedEndpointIds) {
      Nearby().sendFilePayload(endpointId, filePath);
    }

    chatMessages.add({
      'type': 'image',
      'sender': _myDisplayName!,
      'filePath': filePath,
      'time': now,
      'isMe': 'true',
    });
    onChatMessagesUpdated?.call();
  }

  /// メッセージを接続中の全端末に送信する
  ///
  /// 1. テキストを {"sender": "端末名", "text": "本文", "time": "HH:mm"} のJSONに変換
  /// 2. UTF-8エンコードでUint8Listに変換
  /// 3. 接続中の全エンドポイントに sendBytesPayload で一斉送信
  /// 4. 自分自身には送られないため、ローカルにもメッセージを追加
  void sendMessage(String text) {
    if (_myDisplayName == null) return;
    if (text.trim().isEmpty) return;

    final now = _formatTime(DateTime.now());

    final jsonStr = jsonEncode({
      'sender': _myDisplayName,
      'text': text,
      'time': now,
    });
    final bytes = Uint8List.fromList(utf8.encode(jsonStr));

    for (final endpointId in _connectedEndpointIds) {
      Nearby().sendBytesPayload(endpointId, bytes);
    }

    chatMessages.add({
      'sender': _myDisplayName!,
      'text': text,
      'time': now,
      'isMe': 'true',
    });
    onChatMessagesUpdated?.call();
  }

  // ---------- 内部処理：コールバック ----------

  /// Advertise側: 接続リクエストを受信した時の共通処理。
  ///
  /// VIPリストに含まれる端末 → 自動accept（UIコールバック呼ばず）
  /// 未知の端末            → UIコールバック（ダイアログ表示用）
  void _onAdvertConnectionInitiated(String id, ConnectionInfo info) {
    _endpointNames[id] = info.endpointName;

    if (_knownDeviceNames.contains(info.endpointName)) {
      Nearby().acceptConnection(
        id,
        onPayLoadRecieved: (eid, payload) =>
            _handlePayloadReceived(eid, payload),
        onPayloadTransferUpdate: (eid, update) =>
            _handlePayloadTransferUpdate(eid, update),
      );
      return;
    }

    onConnectionInitiated?.call(id, info);
  }

  /// Discover側: 端末を発見した時の共通処理。
  ///
  /// VIPリストに含まれる端末 → 自動 requestConnection + accept（UIコールバック呼ばず）
  /// 未知の端末            → UIコールバック（リスト表示用）
  void _onDiscoverEndpointFound(String id, String name, String sid) {
    if (_knownDeviceNames.contains(name)) {
      final displayName = _lastDisplayName;
      if (displayName == null) return;

      Nearby().requestConnection(
        displayName,
        id,
        onConnectionInitiated: (cid, info) {
          _endpointNames[cid] = info.endpointName;
          if (_knownDeviceNames.contains(info.endpointName)) {
            Nearby().acceptConnection(
              cid,
              onPayLoadRecieved: (eid, payload) =>
                  _handlePayloadReceived(eid, payload),
              onPayloadTransferUpdate: (eid, update) =>
                  _handlePayloadTransferUpdate(eid, update),
            );
          }
        },
        onConnectionResult: (cid, status) {
          _onConnectionResult(cid, status);
          onConnectionResult?.call(cid, status);
        },
        onDisconnected: (cid) {
          _handleDisconnect(cid);
          onDisconnected?.call(cid);
        },
      );
      return;
    }

    onEndpointFound?.call(id, name);
  }

  // ---------- 内部処理 ----------

  /// 接続結果を内部トラッキングする
  void _onConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      _connectedEndpointIds.add(endpointId);
      final name = _endpointNames[endpointId] ?? '不明な端末';
      // 接続成功 → この相手をVIPとして記憶し、ストレージに永続化
      if (name != '不明な端末') {
        _knownDeviceNames.add(name);
        _saveVipNames(); // ← SharedPreferences に保存
      }
      _addSystemMessage('$name が入室しました');
    }
  }

  /// 切断を処理し、自動リカバリを試行する。
  ///
  /// 1. 内部リストから該当エンドポイントの情報を削除
  /// 2. システムメッセージを追加
  /// 3. 接続中の端末が0台になった場合、自分のロール（Host/Guest）に応じて
  ///    Advertise または Discover を自動再開し、新たな接続を待機する状態に復帰する。
  void _handleDisconnect(String endpointId) {
    _connectedEndpointIds.remove(endpointId);
    final name = _endpointNames.remove(endpointId) ?? '不明な端末';
    _addSystemMessage('$name が退出しました');

    if (_connectedEndpointIds.isNotEmpty) return;

    final displayName = _lastDisplayName;
    if (displayName == null) return;

    if (isHost) {
      Nearby().startAdvertising(
        displayName,
        Strategy.P2P_CLUSTER,
        onConnectionInitiated: _onAdvertConnectionInitiated,
        onConnectionResult: (id, status) {
          _onConnectionResult(id, status);
          onConnectionResult?.call(id, status);
        },
        onDisconnected: (id) {
          _handleDisconnect(id);
          onDisconnected?.call(id);
        },
        serviceId: serviceId,
      );
    } else {
      Nearby().startDiscovery(
        displayName,
        Strategy.P2P_CLUSTER,
        onEndpointFound: _onDiscoverEndpointFound,
        onEndpointLost: (id) => onEndpointLost?.call(id),
        serviceId: serviceId,
      );
    }
  }

  /// ペイロード受信を処理する
  void _handlePayloadReceived(String endpointId, Payload payload) {
    if (payload.type == PayloadType.FILE) {
      // ファイルペイロード：URIを記録するが、まだ転送完了前なのでチャットには追加しない
      final uri = payload.uri;
      if (uri != null) {
        _incomingFiles[payload.id] = uri;
        isTransferring.value = true;
      }
    }

    if (payload.type == PayloadType.BYTES && payload.bytes != null) {
      try {
        final jsonStr = utf8.decode(payload.bytes!);
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        final sender = data['sender'] as String? ?? '不明';
        final text = data['text'] as String? ?? '';
        final time = data['time'] as String? ?? _formatTime(DateTime.now());

        chatMessages.add({
          'sender': sender,
          'text': text,
          'time': time,
        });
        onChatMessagesUpdated?.call();

        // ★★★ ホスト中継ロジズム ★★★
        // 自分がホスト (isHost == true) の場合のみ、
        // 受信したメッセージを自分以外の全ゲストに転送する。
        //
        // 送信元を除外する理由 (エコーバック防止):
        // ゲスト1→ホスト→ゲスト2 の経路は正しいが、
        // ゲスト1→ホスト→ゲスト1 のように送信元に戻すと
        // ゲスト1側でメッセージが二重表示される。
        // そこで _connectedEndpointIds から endpointId を除外してから
        // ブロードキャストすることで、エコーバックを防止する。
        if (isHost && payload.bytes != null) {
          for (final eid in _connectedEndpointIds) {
            if (eid != endpointId) {
              Nearby().sendBytesPayload(eid, payload.bytes!);
            }
          }
        }
      } catch (e) {
        debugPrint("メッセージデコードエラー: $e");
      }
    }

    onPayloadReceived?.call(endpointId, payload);
  }

  /// ペイロード転送の進捗更新を処理する
  ///
  /// ファイル転送が SUCCESS になった時点で、一時記録していた URI から
  /// 画像ファイルをアプリ専用のキャッシュディレクトリにコピーし、
  /// chatMessages に追加する。
  void _handlePayloadTransferUpdate(
      String endpointId, PayloadTransferUpdate update) {
    if (update.status == PayloadStatus.SUCCESS &&
        _incomingFiles.containsKey(update.id)) {
      final uriStr = _incomingFiles.remove(update.id)!;
      _processReceivedFile(uriStr);
    }

    if (update.status == PayloadStatus.SUCCESS ||
        update.status == PayloadStatus.FAILURE ||
        update.status == PayloadStatus.CANCELED) {
      Future.delayed(const Duration(milliseconds: 500), () {
        isTransferring.value = false;
      });
    }

    onPayloadTransferUpdate?.call(endpointId, update);
  }

  /// 受信したファイルURIをアプリ内の永続的なパスにコピーし、
  /// chatMessages に画像メッセージとして追加する。
  ///
  /// Android では content:// URI が渡されるため、`File(uri).copy()` は使えない。
  /// nearby_connections パッケージが提供する `copyFileAndDeleteOriginal` を利用し、
  /// ネイティブ（Android の ContentResolver）経由で正しくコピーする。
  Future<void> _processReceivedFile(String uriStr) async {
    try {
      final dir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final destPath = '${dir.path}/roomvibe_img_$timestamp.jpg';

      // Nearby().copyFileAndDeleteOriginal は Platform Channel を経由して
      // Android ネイティブの ContentResolver で content:// URI を解決する。
      // これにより file:// 以外のスキーマでも正しくファイルをコピーできる。
      final ok = await Nearby().copyFileAndDeleteOriginal(uriStr, destPath);

      if (ok != true) {
        return;
      }

      final destFile = File(destPath);
      if (!destFile.existsSync()) {
        return;
      }

      final now = _formatTime(DateTime.now());

      chatMessages.add({
        'type': 'image',
        'sender': _myDisplayName ?? '不明',
        'filePath': destFile.path,
        'time': now,
      });
      onChatMessagesUpdated?.call();
    } catch (_) {
      // ファイルコピー失敗時は何もせずスルー
    }
  }

  // ---------- ヘルパー ----------

  void _addSystemMessage(String text) {
    chatMessages.add({
      'type': 'system',
      'text': text,
      'time': _formatTime(DateTime.now()),
    });
    onChatMessagesUpdated?.call();
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}