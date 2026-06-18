import 'package:flutter/material.dart';
import 'package:roomvibe_app/pages/home_page.dart';

void main() {
  runApp(const RoomVibeApp());
}

class RoomVibeApp extends StatelessWidget {
  const RoomVibeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoomVibe',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const HomePage(),
    );
  }
}