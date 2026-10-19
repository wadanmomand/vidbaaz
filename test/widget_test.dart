// Smoke test: app boots on the finalized full-bleed home art, and its
// "Save Status" tap zone navigates to the Status tab (which shows the
// Flutter bottom nav with all four labels).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vid_baaz/main.dart';

void main() {
  testWidgets('App boots on finalized home art; tap zone goes to Status',
      (WidgetTester tester) async {
    await tester.pumpWidget(const VidBaazApp());
    await tester.pump();

    // Full-bleed finalized home concept, no app bar / nav on top of it.
    expect(find.byKey(const Key('homeArt')), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);

    // Tapping the baked "Save Status" button opens the Status tab.
    await tester.tap(find.byKey(const Key('zoneSaveStatus')));
    await tester.pump();

    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
  });
}
