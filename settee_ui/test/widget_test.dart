import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:settee_ui/main.dart';

void main() {
  testWidgets('Settee ロゴが表示されることを確認', (WidgetTester tester) async {
    // アプリをビルドして表示
    await tester.pumpWidget(SetteeApp());

    // 最初のスプラッシュ画面でロゴ画像が表示されることを確認
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('ようこそ画面に登録ボタンがあることを確認', (WidgetTester tester) async {
    await tester.pumpWidget(const SetteeApp());

    // スプラッシュ画面の2秒待ち（Timer遷移）
    await tester.pump(const Duration(seconds: 2));

    // 遷移先 WelcomeScreen の描画完了を待つ
    await tester.pumpAndSettle();

    // テキスト '登録' を持つ ElevatedButton を探す
    expect(find.widgetWithText(ElevatedButton, '登録'), findsOneWidget);
  });
}
