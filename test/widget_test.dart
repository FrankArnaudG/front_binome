import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:binome_app2/main.dart';

void main() {
  testWidgets('App boots on the splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const BinomeApp());

    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
  });
}
