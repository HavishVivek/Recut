// Renders the welcome, a tour step and the sign-in dialog with the app's own widgets, to look at. Not part of the suite.
//   CAPTURE_OUT=<folder> flutter test tool/onboarding_capture_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aie_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/fake_api.dart';

final out = Platform.environment['CAPTURE_OUT'] ?? '';
final _key = GlobalKey();

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> snap(WidgetTester tester, String name) async {
  await settle(tester);
  await tester.runAsync(() async {
    final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final name in ['aie/motion', 'aie/drop', 'aie/notify']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => false);
    }
    Future<void> family(String name, List<String> assets) async {
      final loader = FontLoader(name);
      for (final asset in assets) {
        loader.addFont(rootBundle.load(asset));
      }
      await loader.load();
    }

    await family('Geist', ['assets/fonts/Geist-Regular.ttf', 'assets/fonts/Geist-Medium.ttf', 'assets/fonts/Geist-SemiBold.ttf']);
    await family('GeistMono', ['assets/fonts/GeistMono-Regular.ttf', 'assets/fonts/GeistMono-Medium.ttf']);
    for (final (style, file) in [('Regular', 'Phosphor'), ('Fill', 'Phosphor-Fill'), ('Duotone', 'Phosphor-Duotone')]) {
      await family('packages/phosphor_flutter/Phosphor$style', ['packages/phosphor_flutter/lib/fonts/$file.ttf']);
    }
  });

  testWidgets('welcome, a tour step and sign in', (tester) async {
    tester.view.physicalSize = const Size(2880, 1840);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final api = FakeApi()..appSettings = {...settingsView(), 'onboarded': false};
    await tester.pumpWidget(RepaintBoundary(key: _key, child: AieApp(enablePreview: false, api: api)));
    // Images decode outside the test's fake clock, so the app's own are loaded before the first snap.
    await tester.runAsync(() async {
      for (final asset in ['assets/brand/logo.png', 'assets/brand/mark.png']) {
        await precacheImage(AssetImage(asset), _key.currentContext!);
      }
    });
    await settle(tester);
    await snap(tester, 'welcome');
    await tester.tap(find.text('Take the tour'));
    await settle(tester);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Next'));
      await settle(tester);
    }
    await snap(tester, 'tour');
    await tester.tap(find.text('Skip tour'));
    await settle(tester);
    await tester.tap(find.text('Settings').first);
    await settle(tester);
    await tester.scrollUntilVisible(find.widgetWithText(TextButton, 'Sign in'), 300, scrollable: find.byType(Scrollable).last);
    await settle(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Sign in'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'sam@example.com');
    await snap(tester, 'signin');
  });
}
