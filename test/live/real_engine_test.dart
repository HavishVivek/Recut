// The real pages against the real engine, with every real tool. It needs Resolve open and
// the bridge started, so it only runs when asked:
//
//   AIE_LIVE=1 AIE_CLIP=/path/clip.mp4 AIE_REFERENCE=/path/look.png AIE_PROJECTS=/tmp/p AIE_SHOTS=/tmp/s flutter test test/live
//
// Pumped by hand with real time in between, because a page's polling and the engine's
// sockets have to both move. Picture and sound can't play here, so the native player is off.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:aie_app/engine.dart';
import 'package:aie_app/main.dart';
import 'package:aie_app/pages/style.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _env = Platform.environment;
final _live = _env['AIE_LIVE'] != null;
final _boundary = GlobalKey();
const _idle = 'Ready. Nothing reaches Resolve until you approve it.';

class _Picker extends FileSelectorPlatform {
  String? next;

  @override
  Future<XFile?> openFile({List<XTypeGroup>? acceptedTypeGroups, String? initialDirectory, String? confirmButtonText}) async =>
      next == null ? null : XFile(next!);
}

/// A test only draws fonts it's handed, so the pictures need the real ones.
Future<void> _loadFonts() async {
  Future<ByteData> asset(String name) => rootBundle.load(name);
  await (FontLoader('Geist')
        ..addFont(asset('assets/fonts/Geist-Regular.ttf'))
        ..addFont(asset('assets/fonts/Geist-Medium.ttf'))
        ..addFont(asset('assets/fonts/Geist-SemiBold.ttf')))
      .load();
  await (FontLoader('GeistMono')
        ..addFont(asset('assets/fonts/GeistMono-Regular.ttf'))
        ..addFont(asset('assets/fonts/GeistMono-Medium.ttf')))
      .load();
  for (final (family, file) in const [('PhosphorRegular', 'Phosphor'), ('PhosphorFill', 'Phosphor-Fill'), ('PhosphorDuotone', 'Phosphor-Duotone')]) {
    await (FontLoader('packages/phosphor_flutter/$family')..addFont(asset('packages/phosphor_flutter/lib/fonts/$file.ttf'))).load();
  }
  final folder = '${_env['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  await (FontLoader('MaterialIcons')..addFont(File('$folder/MaterialIcons-Regular.otf').readAsBytes().then(ByteData.sublistView))).load();
}

/// Drives the real pages. They're pumped by hand with real time in between.
class _App {
  _App(this.tester, this.picker);

  final WidgetTester tester;
  final _Picker picker;

  static Future<_App> start(WidgetTester tester) async {
    HttpOverrides.global = null;
    final picker = _Picker();
    FileSelectorPlatform.instance = picker;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 760);
    addTearDown(tester.view.reset);
    await tester.runAsync(_loadFonts);
    final engine = (await tester.runAsync(Engine.launch))!;
    addTearDown(engine.stop);
    await tester.pumpWidget(RepaintBoundary(key: _boundary, child: AieApp(enablePreview: false, api: engine)));
    return _App(tester, picker);
  }

  Future<void> breathe() async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
    await tester.pump(const Duration(milliseconds: 60));
    if (find.byTooltip('Dismiss').evaluate().isNotEmpty) {
      fail('The app reported: ${tester.widgetList<SelectableText>(find.byType(SelectableText)).first.data}');
    }
  }

  Future<void> waitFor(Finder finder, {int seconds = 100}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(end)) {
      await breathe();
      if (finder.evaluate().isNotEmpty) return;
    }
    final shown = tester.widgetList<Text>(find.byType(Text)).map((item) => item.data).whereType<String>().take(30).join(' | ');
    fail('Never saw $finder. On screen: $shown');
  }

  /// Waits for a job to finish, and fails on anything it reports.
  Future<void> finished() async {
    await waitFor(find.text(_idle), seconds: 240);
    await breathe();
  }

  /// Scrolls a page's list until the text is on screen, as a person would.
  Future<void> reach(Finder target) async {
    for (var i = 0; i < 40 && target.evaluate().isEmpty; i++) {
      final lists = find.byType(Scrollable).hitTestable();
      if (lists.evaluate().isEmpty) break;
      await tester.drag(lists.last, const Offset(0, -220));
      await tester.pump(const Duration(milliseconds: 200));
      await breathe();
    }
  }

  Future<void> tap(String text) async {
    final target = find.text(text).hitTestable();
    await reach(target);
    await waitFor(target, seconds: 20);
    await tester.ensureVisible(target.first);
    await breathe();
    await tester.tap(target.first);
    await breathe();
  }

  Future<void> go(String page) async {
    await tester.tap(find.text(page).first);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    await breathe();
  }

  Future<void> shot(String name) async {
    final folder = _env['AIE_SHOTS'];
    if (folder == null) return;
    await tester.pump(const Duration(seconds: 1));
    final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$folder/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Future<void> newProject(String name) async {
    await go('Projects');
    await tap('New project');
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Project name').hitTestable(), name);
    await tester.pump();
    await tap('Create');
    await waitFor(find.text('Add clip').hitTestable(), seconds: 30);
  }

  /// Asks this project's AI and waits for the answer to be saved.
  Future<void> ask(String question) async {
    await tester.enterText(find.widgetWithText(TextField, 'Ask a question, or say what to change').hitTestable(), question);
    await tester.tap(find.byTooltip('Send').hitTestable());
    await breathe();
    await waitFor(find.byTooltip('Send').hitTestable(), seconds: 150);
    await finished();
  }
}

void main() {
  testWidgets('a project goes from a clip to a final render', (tester) async {
    final app = await _App.start(tester);
    final picker = app.picker;
    Future<void> breathe() => app.breathe();
    Future<void> waitFor(Finder finder, {int seconds = 100}) => app.waitFor(finder, seconds: seconds);
    Future<void> finished() => app.finished();
    Future<void> reach(Finder target) => app.reach(target);
    Future<void> tap(String text) => app.tap(text);
    Future<void> go(String page) => app.go(page);
    Future<void> shot(String name) => app.shot(name);

    await go('Setup');
    await waitFor(find.text('Ready'));
    await waitFor(find.text('EffectCraft'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
    await tester.pump();
    await shot('01-connections');

    await go('Projects');
    await tap('New project');
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Project name').hitTestable(), 'UI check ${DateTime.now().millisecondsSinceEpoch ~/ 1000}');
    await tester.pump();
    await tap('Create');
    await waitFor(find.text('Add clip').hitTestable(), seconds: 30);
    await shot('02-footage-empty');

    picker.next = _env['AIE_CLIP'];
    await tap('Add clip');
    await waitFor(find.textContaining('Transcript').hitTestable());
    await finished();
    expect(find.textContaining('fps').hitTestable(), findsWidgets);
    await shot('03-footage');
    await tap('Pauses 14');
    await tester.pump(const Duration(seconds: 1));
    await shot('04-footage-pauses');

    await go('Style');
    picker.next = _env['AIE_REFERENCE'];
    await tap('Add reference');
    await waitFor(find.text('Title style').hitTestable());
    await finished();
    await shot('05-style');
    await tap('Choose');
    await finished();
    await reach(find.text('Save style').hitTestable());
    await tester.enterText(find.descendant(of: find.byType(StylePage), matching: find.byType(TextField)).last, '#FF6A3D');
    await tap('Save style');
    await finished();
    await shot('06-style-saved');

    await go('Review');
    await shot('07-review-empty');
    await tester.enterText(find.widgetWithText(TextField, 'Make a tight rough cut of this how-to video, with one title near the start.').hitTestable(), 'Make a tight rough cut, with one title near the start.');
    await tap('Make plan');
    await waitFor(find.text('Revision r001').hitTestable());
    await finished();
    await shot('08-review-plan');
    await tap('Preview frames');
    await finished();
    await reach(find.byType(Image).hitTestable());
    await waitFor(find.byType(Image).hitTestable(), seconds: 30);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await shot('08b-review-stills');
    await tap('Make preview');
    await waitFor(find.text('Preview at your clip\'s full size. Colour isn\'t final.'), seconds: 60);
    await finished();
    await shot('09-review-preview');

    await tap('Approve and build');
    await waitFor(find.text('Not yet'));
    await tester.pump(const Duration(milliseconds: 400));
    await shot('10-approve-dialog');
    await tester.tap(find.text('Approve and build').last);
    await breathe();
    await waitFor(find.text('Applied. See Resolve').hitTestable(), seconds: 120);
    await finished();
    await shot('11-review-applied');

    await tester.enterText(find.widgetWithText(TextField, 'Note at this moment, such as: make this title faster').hitTestable(), 'make this title faster');
    await tester.tap(find.byTooltip('Add note').hitTestable());
    await finished();
    await tap('Make this change');
    await waitFor(find.text('Revision r002').hitTestable(), seconds: 90);
    await finished();
    await shot('12-review-revision');

    await go('Resolve');
    await waitFor(find.text('timeline.overlay_track'), seconds: 60);
    await finished();
    await shot('13-resolve-check');
    await tap('Approve and build');
    await waitFor(find.text('Not yet'));
    await tester.tap(find.text('Approve and build').last);
    await breathe();
    await waitFor(find.text('APPLIED'), seconds: 120);
    await finished();
    await tap('Read it now');
    await waitFor(find.text('Matches the plan exactly'), seconds: 30);
    await finished();
    await shot('14-resolve-applied');
    await tap('Render final');
    await waitFor(find.text('Final render checked, frame count matches'), seconds: 300);
    await finished();
    await shot('15-resolve-rendered');

    await go('Activity');
    await shot('16-activity');
    await go('Projects');
    await waitFor(find.text('All media is where it was registered'));
    await shot('17-project');

    tester.view.physicalSize = const Size(1440, 920);
    await go('Review');
    await tester.pump(const Duration(seconds: 1));
    await shot('18-review-large');
  }, skip: !_live, timeout: const Timeout(Duration(minutes: 15)));

  testWidgets('each project has its own AI, memory and model', (tester) async {
    final app = await _App.start(tester);
    final stamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await app.newProject('First $stamp');
    app.picker.next = _env['AIE_CLIP'];
    await app.tap('Add clip');
    await app.waitFor(find.textContaining('Transcript').hitTestable());
    await app.finished();

    await app.go('Assistant');
    await app.shot('20-assistant-empty');
    await tester.enterText(find.widgetWithText(TextField, 'Something to remember').hitTestable(), 'The sponsor of this video is called Zephyrine.');
    await tester.tap(find.byTooltip('Remember').hitTestable());
    await app.waitFor(find.text('The sponsor of this video is called Zephyrine.').hitTestable());
    await app.finished();
    await app.ask('In one sentence, what is being built in this video?');
    await app.ask('Who is the sponsor? Answer in a few words.');
    expect(find.textContaining('Zephyrine').hitTestable(), findsWidgets);
    await app.shot('21-assistant-first');

    await app.go('Footage');
    await app.shot('21b-footage');
    await app.go('Review');
    await tester.enterText(find.widgetWithText(TextField, 'Make a tight rough cut of this how-to video, with one title near the start.').hitTestable(), 'Make a tight rough cut.');
    await app.tap('Make plan');
    await app.waitFor(find.text('Revision r001').hitTestable());
    await app.finished();
    await app.shot('21c-review');

    await app.go('Assistant');
    await app.waitFor(find.text('How tight should the cut feel?').hitTestable(), seconds: 10);
    await app.shot('21c1-style-question');
    await app.tap('Balanced: short breaths stay');
    await app.waitFor(find.text('What is this video for?').hitTestable(), seconds: 10);
    await app.finished();
    for (var left = 0; left < 4; left++) {
      await app.tap('Skip');
      await app.finished();
    }
    await app.ask('cut the sentence about the OLED screen on the bottom');
    await app.waitFor(find.text('See it on Review').hitTestable(), seconds: 90);
    expect(find.textContaining('I cut 1 sentence'), findsWidgets);
    await app.shot('21c2-edit-done');
    await app.tap('See it on Review');
    await app.waitFor(find.text('Revision r002').hitTestable(), seconds: 20);
    await app.shot('21c3-review-edited');
    await app.go('Setup');
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
    await tester.pump();
    await app.shot('21d-connections');

    await app.go('Style');
    app.picker.next = _env['AIE_REFERENCE'];
    await app.tap('Add reference');
    await app.waitFor(find.text('Title style').hitTestable());
    await app.finished();
    await app.shot('21e-style');
    await app.go('Settings');
    await app.waitFor(find.text('llama3.2:3b').hitTestable(), seconds: 20);
    await app.shot('22-settings');

    await app.newProject('Second $stamp');
    await app.go('Assistant');
    expect(find.text('Ask about this project, or tell it what to change').hitTestable(), findsOneWidget);
    expect(find.textContaining('Zephyrine'), findsNothing);
    await tester.tap(find.textContaining('Same as default').hitTestable().first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('llama3.2:3b').last);
    await app.breathe();
    await app.waitFor(find.text('Answering with llama3.2:3b').hitTestable(), seconds: 20);
    await app.finished();
    await app.ask('Who is the sponsor of this video? Say unknown if you cannot tell.');
    expect(find.textContaining('Zephyrine'), findsNothing);
    await app.shot('23-assistant-second');

    await app.go('Projects');
    await app.waitFor(find.text('first-$stamp').hitTestable(), seconds: 20);
    await app.tap('Open');
    await app.waitFor(find.text('Close project').hitTestable(), seconds: 20);
    await app.go('Assistant');
    await app.waitFor(find.text('The sponsor of this video is called Zephyrine.').hitTestable(), seconds: 20);
    expect(find.text('Answering with qwen3:8b').hitTestable(), findsOneWidget);
    expect(find.textContaining('Zephyrine').hitTestable(), findsWidgets);
    await app.shot('24-assistant-back-to-first');
  }, skip: !_live, timeout: const Timeout(Duration(minutes: 10)));
}
