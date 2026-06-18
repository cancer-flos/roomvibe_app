import 'package:nearby_connections/nearby_connections.dart';

/// Nearby Connections API をラップするサービスクラス。
///
/// 発見・広告・接続・ペイロードのコールバックを一元管理し、
/// UI 側はこのクラスのメソッドを呼ぶだけで操作できる。
class NearbyService {
  static const String serviceId = "com.example.roomvibe.p2p";

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

  // ---------- 公開メソッド ----------

  /// Advertise（部屋を作る）を開始する
  Future<bool> startAdvertising(String displayName) async {
    return await Nearby().startAdvertising(
      displayName,
      Strategy.P2P_CLUSTER,
      onConnectionInitiated: (id, info) =>
          onConnectionInitiated?.call(id, info),
      onConnectionResult: (id, status) =>
          onConnectionResult?.call(id, status),
      onDisconnected: (id) => onDisconnected?.call(id),
      serviceId: serviceId,
    );
  }

  /// Advertise を停止する
  Future<void> stopAdvertising() async {
    await Nearby().stopAdvertising();
  }

  /// Discover（部屋を探す）を開始する
  Future<bool> startDiscovery(String displayName) async {
    return await Nearby().startDiscovery(
      displayName,
      Strategy.P2P_CLUSTER,
      onEndpointFound: (id, name, sid) =>
          onEndpointFound?.call(id, name),
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
      onConnectionInitiated: (id, info) =>
          onConnectionInitiated?.call(id, info),
      onConnectionResult: (id, status) =>
          onConnectionResult?.call(id, status),
      onDisconnected: (id) => onDisconnected?.call(id),
    );
  }

  /// 接続を承認する
  Future<bool> acceptConnection(String endpointId) async {
    return await Nearby().acceptConnection(
      endpointId,
      onPayLoadRecieved: (id, payload) =>
          onPayloadReceived?.call(id, payload),
      onPayloadTransferUpdate: (id, update) =>
          onPayloadTransferUpdate?.call(id, update),
    );
  }

  /// 接続を拒否する
  Future<bool> rejectConnection(String endpointId) async {
    return await Nearby().rejectConnection(endpointId);
  }

  /// 特定のエンドポイントから切断する
  Future<void> disconnectFromEndpoint(String endpointId) async {
    await Nearby().disconnectFromEndpoint(endpointId);
  }

  /// すべてのエンドポイントを切断する
  Future<void> stopAllEndpoints() async {
    await Nearby().stopAllEndpoints();
  }
}