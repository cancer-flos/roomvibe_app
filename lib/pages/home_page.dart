import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:roomvibe_app/pages/chat_page.dart';
import 'package:roomvibe_app/services/nearby_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// メイン画面。
///
/// NearbyService を通して BLE の Advertise / Discover /
/// 接続処理を行い、UI に反映する。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final NearbyService _nearby = NearbyService();

  /// 自身の表示名（SharedPreferences から読み込む）
  String _displayName = "";

  // 発見した端末一覧  key: endpointId, value: endpointName
  final Map<String, String> _foundDevices = {};

  // 接続済み端末一覧  key: endpointId, value: endpointName
  final Map<String, String> _connectedDevices = {};

  bool _isAdvertising = false;
  bool _isDiscovering = false;

  @override
  void initState() {
    super.initState();
    _setupCallbacks();
    _requestPermissions();
    // SharedPreferences から名前を読み込み、未設定ならダイアログを表示
    _loadDisplayName();
  }

  /// SharedPreferences から表示名を読み込む。
  /// 未設定（null または空文字）の場合は名前入力ダイアログを表示する。
  Future<void> _loadDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('displayName') ?? '';

    if (savedName.isNotEmpty) {
      _displayName = savedName;
      _nearby.setDisplayName(_displayName);
      return;
    }

    // 名前が未設定 → ダイアログを表示
    if (!mounted) return;
    _showNameInputDialog();
  }

  /// 初回起動時に表示する名前入力ダイアログ。
  /// 入力された名前は SharedPreferences に保存され、次回起動時に自動復元される。
  Future<void> _showNameInputDialog() async {
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false, // ダイアログ外タップでは閉じない
      builder: (ctx) => AlertDialog(
        title: const Text("ニックネームを設定"),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 16,
          decoration: const InputDecoration(
            hintText: "あなたの名前を入力してください",
            counterText: "",
          ),
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(ctx).pop(name);
              }
            },
            child: const Text("決定"),
          ),
        ],
      ),
    );

    controller.dispose();

    if (result != null && result.isNotEmpty) {
      _displayName = result;
      _nearby.setDisplayName(_displayName);

      // SharedPreferences に保存（次回起動時に自動復元）
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('displayName', _displayName);
    }
  }

  // ---- 権限 ----

  Future<void> _requestPermissions() async {
    await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
    ].request();
  }

  // ---- NearbyService のコールバックを設定 ----

  void _setupCallbacks() {
    _nearby.onEndpointFound = (id, name) {
      setState(() => _foundDevices[id] = name);
      _showSnackBar("お部屋を発見: $name");
    };

    _nearby.onEndpointLost = (id) {
      if (id == null) return;
      setState(() => _foundDevices.remove(id));
    };

    _nearby.onConnectionInitiated = (id, info) {
      // Advertise 側にも Discover 側にも飛んでくる。
      // Discoverer は自分からリクエストしたので自動 accept、
      // Advertiser はダイアログで accept / reject を選ばせる。
      if (info.isIncomingConnection) {
        // 相手から来たリクエスト → ダイアログ
        _showConnectionRequestDialog(id, info);
      } else {
        // 自分から送ったリクエストの応答 → 自動 accept
        _autoAccept(id, info.endpointName);
      }
    };

    _nearby.onConnectionResult = (id, status) {
      if (status == Status.CONNECTED) {
        final name = _foundDevices[id] ?? "不明な端末";
        setState(() {
          _connectedDevices[id] = name;
          _foundDevices.remove(id);
        });
        _showSnackBar("$name と接続しました");
      } else {
        _showSnackBar("接続結果: $status");
      }
    };

    _nearby.onDisconnected = (id) {
      final name = _connectedDevices[id];
      setState(() => _connectedDevices.remove(id));
      if (name != null) {
        _showSnackBar("$name との接続が切れました");
      }
    };

    // フェーズ4以降で本格的に使う
    _nearby.onPayloadReceived = (id, payload) {
      print("Payload受信: $id type=${payload.type} bytes=${payload.bytes}");
    };

    _nearby.onPayloadTransferUpdate = (id, update) {
      print("転送更新: $id ${update.bytesTransferred}/${update.totalBytes}");
    };
  }

  // ---- Advertise ----

  Future<void> _startAdvertising() async {
    try {
      final ok = await _nearby.startAdvertising(_displayName);
      setState(() => _isAdvertising = ok);
      if (ok) _showSnackBar("お部屋をオープンしました");
      return;
    } catch (e) {
      _showSnackBar("エラー: $e");
    }
  }

  // ---- Discover ----

  Future<void> _startDiscovering() async {
    try {
      final ok = await _nearby.startDiscovery(_displayName);
      setState(() => _isDiscovering = ok);
      if (ok) _showSnackBar("周りのお部屋をスキャン中...");
    } catch (e) {
      _showSnackBar("エラー: $e");
    }
  }

  // ---- 接続リクエスト送信（Discoverer が呼ぶ） ----

  Future<void> _requestConnection(String id, String name) async {
    _showSnackBar("$name に接続リクエストを送信します...");
    try {
      final ok = await _nearby.requestConnection(_displayName, id);
      if (!ok) _showSnackBar("接続リクエストの送信に失敗しました");
    } catch (e) {
      _showSnackBar("エラー: $e");
    }
  }

  // ---- 接続承認ダイアログ（Advertiser が accept / reject を選ぶ） ----

  void _showConnectionRequestDialog(String id, ConnectionInfo info) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("接続リクエスト"),
        content: Text(
          "${info.endpointName} からの接続要求\n"
          "認証トークン: ${info.authenticationToken}\n"
          "※ 両端末で同じトークンが表示されていることを確認してください",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _nearby.rejectConnection(id);
              _showSnackBar("接続を拒否しました");
            },
            child: const Text("拒否", style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _accept(id, info);
            },
            child: const Text("承認"),
          ),
        ],
      ),
    );
  }

  Future<void> _accept(String id, ConnectionInfo info) async {
    try {
      await _nearby.acceptConnection(id);
      _showSnackBar(
          "${info.endpointName} を承認しました（相手の承認を待っています...）");
    } catch (e) {
      _showSnackBar("承認エラー: $e");
    }
  }

  Future<void> _autoAccept(String id, String name) async {
    try {
      await _nearby.acceptConnection(id);
    } catch (e) {
      _showSnackBar("自動承認エラー: $e");
    }
  }

  // ---- SnackBar 便利関数 ----

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---- 後片付け ----

  @override
  void dispose() {
    _nearby.stopAllEndpoints();
    super.dispose();
  }

  // ---- Widget ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("RoomVibe")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // --- 操作ボタン ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _isAdvertising ? null : _startAdvertising,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[100]),
                  child: Text(_isAdvertising ? "部屋オープン中" : "部屋を作る"),
                ),
                ElevatedButton(
                  onPressed: _isDiscovering ? null : _startDiscovering,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[100]),
                  child: Text(_isDiscovering ? "スキャン中..." : "部屋を探す"),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // --- 接続済み端末 ---
            if (_connectedDevices.isNotEmpty) ...[
              const Text(
                "接続中の端末",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.green),
              ),
              const SizedBox(height: 8),
              ..._connectedDevices.entries.map((e) => Card(
                    color: Colors.green[50],
                    child: ListTile(
                      leading: const Icon(Icons.link, color: Colors.green),
                      title: Text(e.value),
                      subtitle: Text("ID: ${e.key}"),
                    ),
                  )),
              const SizedBox(height: 12),
              Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatPage(nearby: _nearby),
                      ),
                    );
                  },
                  icon: const Icon(Icons.chat),
                  label: const Text("チャットルームを開く"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo[100],
                    foregroundColor: Colors.indigo[900],
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
            ],

            // --- 発見した端末 ---
            const Text(
              "発見した近くのお部屋リスト",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),

            Expanded(
              child: _foundDevices.isEmpty
                  ? const Center(child: Text("まだ近くにお部屋はありません"))
                  : ListView.builder(
                      itemCount: _foundDevices.length,
                      itemBuilder: (_, i) {
                        final id = _foundDevices.keys.elementAt(i);
                        final name = _foundDevices[id]!;
                        final isConnected = _connectedDevices.containsKey(id);

                        return Card(
                          elevation: 3,
                          child: ListTile(
                            leading: const Icon(Icons.phone_android,
                                color: Colors.indigo),
                            title: Text(name),
                            subtitle: Text("ID: $id"),
                            trailing: ElevatedButton(
                              onPressed: isConnected
                                  ? null
                                  : () => _requestConnection(id, name),
                              style: isConnected
                                  ? null
                                  : ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange[100]),
                              child: Text(isConnected ? "接続済み" : "入室する"),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}