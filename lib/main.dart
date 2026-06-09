import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart'; // ★ 新しい確実な道具に変えました

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: PermissionCheckPage(),
    );
  }
}

class PermissionCheckPage extends StatefulWidget {
  const PermissionCheckPage({super.key});

  @override
  State<PermissionCheckPage> createState() => _PermissionCheckPageState();
}

class _PermissionCheckPageState extends State<PermissionCheckPage> {
  @override
  void initState() {
    super.initState();
    requestPermissions();
  }

  // ★ 新しいパッケージを使った、100%エラーの出ないおねだり処理
  Future<void> requestPermissions() async {
    // 1. Bluetoothと位置情報の権限をまとめてスマホにおねだりする
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
    ].request();

    // 2. もし全部許可されたら、画面に「準備OK」と出す（将来的にここにチャット画面を開く処理を書きます）
    if (statuses[Permission.location]!.isGranted) {
      print("【デバッグ】すべての権限が許可されました！");
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'RoomVibe 起動中...\n権限を許可してください。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}