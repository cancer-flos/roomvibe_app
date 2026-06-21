import 'package:flutter/material.dart';
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
                      final sender = msg['sender'] ?? '不明';
                      final text = msg['text'] ?? '';
                      final time = msg['time'] ?? '';
                      final isMe = sender == widget.nearby.myDisplayName;

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
                    const SizedBox(width: 8),
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
