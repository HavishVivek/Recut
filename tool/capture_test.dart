// Renders the real app's pages with a project's real data, for the product film. Not part of the test suite.
//
//   CAPTURE_DATA=<folder of JSON> CAPTURE_OUT=<folder> flutter test tool/capture_test.dart
//
// Every pixel is the app's own widgets, drawn at twice the window's size. The data is the engine's own JSON, dumped
// from copies of real projects, so nothing is redrawn and nothing is invented.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aie_app/engine.dart';
import 'package:aie_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/fake_api.dart';

final data = Platform.environment['CAPTURE_DATA'] ?? '';
final out = Platform.environment['CAPTURE_OUT'] ?? '';
Json load(String name) => jsonDecode(File('$data/$name.json').readAsStringSync()) as Json;

class RealApi extends FakeApi {
  RealApi(this.listing);
  final Json listing;

  @override
  Future<Json> projects() async => listing;

  @override
  Future<List<Json>> connections() async => [
        {'name': 'DaVinci Resolve', 'ready': true, 'detail': '20.3, on the edit page'},
        {'name': 'AI model', 'ready': true, 'detail': 'qwen3:8b, local'},
      ];
}

Future<void> _fonts() async {
  Future<void> family(String name, List<String> assets) async {
    final loader = FontLoader(name);
    for (final asset in assets) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }

  await family('Geist', ['assets/fonts/Geist-Regular.ttf', 'assets/fonts/Geist-Medium.ttf', 'assets/fonts/Geist-SemiBold.ttf']);
  await family('GeistMono', ['assets/fonts/GeistMono-Regular.ttf', 'assets/fonts/GeistMono-Medium.ttf']);
  for (final (style, file) in [('Regular', 'Phosphor'), ('Fill', 'Phosphor-Fill'), ('Duotone', 'Phosphor-Duotone'), ('Bold', 'Phosphor-Bold')]) {
    await family('packages/phosphor_flutter/Phosphor$style', ['packages/phosphor_flutter/lib/fonts/$file.ttf']);
  }
}

final _key = GlobalKey();

/// Time passing in steps. A page with a looping job indicator never settles, so this never waits for it to.
Future<void> settle(WidgetTester tester, [int steps = 12]) async {
  for (var index = 0; index < steps; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> launch(WidgetTester tester, RealApi api) async {
  tester.view.physicalSize = const Size(2880, 1840);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RepaintBoundary(key: _key, child: AieApp(enablePreview: false, api: api)));
  await settle(tester);
}

/// Decode pictures for real, before any page asks for them. A page that asked first started its loads on the test's
/// fake clock, where a file read never finishes, and a later load reused the stuck one.
Future<void> warm(WidgetTester tester, List<String> pictures) async {
  final context = _key.currentContext!;
  await tester.runAsync(() async {
    for (final path in pictures.toSet()) {
      if (File(path).existsSync()) {
        await precacheImage(FileImage(File(path)), context).timeout(const Duration(seconds: 20), onTimeout: () => stderr.writeln('slow $path'));
      }
    }
  });
}

/// Draw the window and save it.
Future<void> snap(WidgetTester tester, String name) async {
  await settle(tester);
  await tester.runAsync(() async {
    final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  stderr.writeln('saved $name');
}

Future<void> go(WidgetTester tester, String page) async {
  await tester.tap(find.text(page).first);
  await settle(tester);
}

List<String> _paths(Object? value) {
  final found = <String>[];
  void walk(Object? item) {
    if (item is Map) {
      item.forEach((key, child) {
        if (child is String && child.startsWith('/') && RegExp(r'\.(png|jpg|jpeg)$', caseSensitive: false).hasMatch(child)) found.add(child);
        walk(child);
      });
    } else if (item is List) {
      item.forEach(walk);
    }
  }

  walk(value);
  return found;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The window's own channels have no Mac behind them here: Reduce Motion is off, and drops and notifications go nowhere.
    for (final name in ['aie/motion', 'aie/drop', 'aie/notify']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => false);
    }
    await _fonts();
  });

  testWidgets('projects, the assistant and its draft', (tester) async {
    final api = RealApi(load('projects'))
      ..current = load('assistant_state')
      ..chatState = load('assistant_chat');
    await launch(tester, api);
    await warm(tester, _paths(api.chatState));
    await snap(tester, 'projects');
    stderr.writeln('snapped projects');
    await tester.tap(find.text('Open').at(1));
    stderr.writeln('tapped open');
    await settle(tester);
    stderr.writeln('opened');
    await go(tester, 'Assistant');
    stderr.writeln('on assistant');
    await snap(tester, 'assistant');
  });

  testWidgets('a footage edit, reviewed and sent to Resolve', (tester) async {
    final state = load('footage_state');
    final api = RealApi(load('projects'))
      ..current = state
      ..shownPlan = load('footage_plan');
    await launch(tester, api);
    await warm(tester, [..._paths(state), ..._paths(api.shownPlan)]);
    await tester.tap(find.text('Open').at(9));
    await settle(tester);
    await go(tester, 'Footage');
    await snap(tester, 'footage');
    await go(tester, 'Review');
    await snap(tester, 'review');
    await go(tester, 'Resolve');
    await snap(tester, 'resolve');
  });

  testWidgets('the gallery and a callout made from a form', (tester) async {
    final gallery = load('gallery');
    final preview = load('callout_preview');
    final api = RealApi(load('projects'))..current = load('gallery_state');
    api.outcome = (action, body) => switch (action) {
          'gallery' => {'state': 'done', 'result': gallery},
          'template_preview' => {'state': 'done', 'result': preview},
          _ => {'name': action, 'state': 'done'},
        };
    await launch(tester, api);
    await warm(tester, [preview['path'] as String, ..._paths(api.current)]);
    await tester.tap(find.text('Open').first);
    await settle(tester);
    await go(tester, 'Make');
    await snap(tester, 'make');
    await tester.tap(find.text('Callout'));
    await settle(tester);
    await tester.tap(find.text('Choose one').first);
    await settle(tester);
    await tester.tap(find.text('hc-sr04.png').last);
    await settle(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await settle(tester);
    await snap(tester, 'callout_empty');
  });
}
