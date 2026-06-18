import 'package:flutter_test/flutter_test.dart';
import 'package:roomvibe_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RoomVibeApp());
    expect(find.text('RoomVibe'), findsOneWidget);
  });
}