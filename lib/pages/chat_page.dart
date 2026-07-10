import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:roomvibe_app/services/nearby_service.dart';

/// チャットルーム画面。
///
/// NearbyService の chatMessages を ListView.builder で表示し、
/// 下部の TextField からメッセージを送信する。
class ChatPage extends StatefulWidget {
  final NearbyService nearby;

  const ChatPage({super.key, required this.nearby});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// 送信ボタンの有効/無効を管理する
  bool _canSend = false;

  /// ImagePicker のインスタンス（使い回し）
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // メッセージが追加されたら再描画 → 描画後に最下部へスクロール
    widget.nearby.onChatMessagesUpdated = () {
      if (mounted) setState(() {});
      // addPostFrameCallback: 現在のフレームの描画が完了した後に実行される
      // これにより、ListView が新しいメッセージをレイアウトした状態で
      // 確実に最下部までスクロールできる
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    };

    // テキスト変更を監視して送信ボタンの有効/無効を切り替える
    _textController.addListener(() {
      final hasText = _textController.text.trim().isNotEmpty;
      if (hasText != _canSend) {
        setState(() => _canSend = hasText);
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// ギャラリーから画像を選択する
  ///
  /// 選択された画像のパスをデバッグコンソールに出力する。
  /// ユーザーがキャンセルした場合は何もしない。
  /// 画像の送信処理は次のステップで実装する。
  Future<void> _pickAndSendImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920, // 大きすぎる画像を抑制
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile == null) {
        // ユーザーがキャンセルした → 何もしない
        return;
      }

      // 画像ファイルを接続中の全端末に送信する
      await widget.nearby.sendImagePayload(pickedFile.path);
    } catch (e) {
      debugPrint("画像選択エラー: $e");
    }
  }

  /// メッセージを送信する
  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    widget.nearby.sendMessage(text);
    _textController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("チャット")),
      body: Column(
        children: [
          // --- メッセージ一覧 ---
          Expanded(
            child: widget.nearby.chatMessages.isEmpty
                ? const Center(
                    child: Text(
                      "まだメッセージはありません\n\n"
                      "下部のテキストフィールドから\n"
                      "メッセージを送信してみましょう",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    reverse: false,
                    padding: const EdgeInsets.all(12),
                    itemCount: widget.nearby.chatMessages.length,
                    itemBuilder: (_, i) {
                      final msg = widget.nearby.chatMessages[i];
                      final type = msg['type'] ?? 'message';
                      final text = msg['text'] ?? '';
                      final time = msg['time'] ?? '';

                      // type フィールドで分岐：
                      // 'system' → システム通知（中央揃えグレーテキスト）
                      // 'image'  → 画像メッセージ（吹き出し内に画像表示）
                      // それ以外 → 通常のチャット吹き出し
                      if (type == 'system') {
                        return _SystemMessage(text: text, time: time);
                      }

                      final isMe = msg['isMe'] == 'true';

                      if (type == 'image') {
                        final filePath = msg['filePath'] ?? '';
                        return _ImageBubble(
                          filePath: filePath,
                          time: time,
                          isMe: isMe,
                        );
                      }

                      final sender = msg['sender'] ?? '不明';

                      return _MessageBubble(
                        sender: sender,
                        text: text,
                        time: time,
                        isMe: isMe,
                      );
                    },
                  ),
          ),

          // --- テキスト入力エリア ---
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  offset: const Offset(0, -2),
                  blurRadius: 4,
                  color: Colors.black.withOpacity(0.1),
                ),
              ],
            ),
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        decoration: const InputDecoration(
                          hintText: "メッセージを入力...",
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    // --- 画像選択ボタン ---
                    IconButton(
                      onPressed: _pickAndSendImage,
                      icon: Icon(
                        Icons.photo,
                        color: Colors.indigo[300],
                      ),
                      tooltip: "画像を選択",
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: _canSend ? _sendMessage : null,
                      icon: Icon(
                        Icons.send,
                        color: _canSend ? Colors.indigo : Colors.grey[400],
                      ),
                      tooltip: "送信",
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// システムメッセージ（入退室等）のウィジェット
///
/// 中央寄せの控えめなグレーテキストで表示する。
/// LINE の「〇〇さんが参加しました」のような演出。
class _SystemMessage extends StatelessWidget {
  final String text;
  final String time;

  const _SystemMessage({
    required this.text,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                time,
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 画像メッセージの吹き出しウィジェット
///
/// isMe == true  → 右寄せ（自分のメッセージ）
/// isMe == false → 左寄せ（相手のメッセージ）
/// Image.file で画像を表示し、最大幅 240px の制限と角丸を適用する。
class _ImageBubble extends StatelessWidget {
  final String filePath;
  final String time;
  final bool isMe;

  const _ImageBubble({
    required this.filePath,
    required this.time,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // 吹き出し本体
          Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!isMe) const SizedBox(width: 8),
              Flexible(
                child: Container(
                  decoration: BoxDecoration(
                    color: isMe ? Colors.indigo[100] : Colors.grey[200],
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: isMe
                          ? const Radius.circular(16)
                          : const Radius.circular(4),
                      bottomRight: isMe
                          ? const Radius.circular(4)
                          : const Radius.circular(16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                        child: Image.file(
                          File(filePath),
                          width: 240,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 240,
                            height: 120,
                            color: Colors.grey[300],
                            child: const Center(
                              child: Icon(Icons.broken_image,
                                  color: Colors.grey),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(
                            left: 10, right: 10, top: 4, bottom: 6),
                        child: Text(
                          time,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (isMe) const SizedBox(width: 8),
            ],
          ),
        ],
      ),
    );
  }
}

/// メッセージの吹き出しウィジェット
///
/// isMe == true  → 右寄せ（自分のメッセージ、青色）
/// isMe == false → 左寄せ（相手のメッセージ、グレー）
class _MessageBubble extends StatelessWidget {
  final String sender;
  final String text;
  final String time;
  final bool isMe;

  const _MessageBubble({
    required this.sender,
    required this.text,
    required this.time,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // 送信者名（相手のときだけ表示）
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                sender,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo),
              ),
            ),
          // 吹き出し本体
          Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!isMe) const SizedBox(width: 8),
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.7,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? Colors.indigo[100] : Colors.grey[200],
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: isMe
                          ? const Radius.circular(16)
                          : const Radius.circular(4),
                      bottomRight: isMe
                          ? const Radius.circular(4)
                          : const Radius.circular(16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Text(
                        text,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (isMe) const SizedBox(width: 8),
            ],
          ),
        ],
      ),
    );
  }
}
