import 'package:cao_im/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const CaoApp());

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
