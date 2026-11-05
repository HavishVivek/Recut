import 'package:aie_app/engine.dart';
import 'package:aie_app/main.dart';
import 'package:aie_app/pages/finds.dart';
import 'package:aie_app/project.dart';
import 'package:aie_app/ui.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

/// Answers the native folder picker, which a test has no window for.
class FakePicker extends FileSelectorPlatform {
  final List<String> folders = [];

  @override
  Future<String?> getDirectoryPath({String? initialDirectory, String? confirmButtonText}) async =>
      folders.isEmpty ? null : folders.removeAt(0);
}

Future<void> launch(WidgetTester tester, FakeApi api) async {
  // Tall enough that the lists build every row.
  tester.view.physicalSize = const Size(1500, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AieApp(enablePreview: false, api: api));
  await tester.pumpAndSettle();
}

Future<void> go(WidgetTester tester, String page) async {
  await tester.tap(find.text(page).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the open page\'s background slides to the next page', (tester) async {
    await launch(tester, FakeApi());
    double top() => tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned).first).top!;
    final before = top();
    await tester.tap(find.text('Style').first);
    await tester.pump();
    final after = top();
    expect(after, isNot(before));
    expect(after % 34, 0);
    await tester.pumpAndSettle();
  });

  testWidgets('with no project, each page says what to do first', (tester) async {
    await launch(tester, FakeApi());
    expect(find.text('Ready. Open or make a project to start.'), findsOneWidget);
    expect(find.text('older'), findsOneWidget);
    for (final page in ['Footage', 'Style', 'Review', 'Resolve', 'Activity']) {
      await go(tester, page);
      expect(find.text('Open a project first'), findsWidgets);
    }
    await go(tester, 'Setup');
    expect(find.text('Everything the editor needs is here.'), findsOneWidget);
  });

  testWidgets('a Mac missing something opens on Setup, and each button sends its step', (tester) async {
    final api = FakeApi()
      ..setupState = setupView(rows: [
        setupRow('tools', 'Video tools'),
        setupRow('ollama', 'AI model', ready: false, actions: [{'id': 'pull_model', 'label': 'Download qwen3:8b'}]),
        setupRow('speech', 'Speech to text', ready: false, actions: [{'id': 'install_speech', 'label': 'Set up speech to text'}]),
        setupRow('effectcraft', 'EffectCraft', ready: false, required: false),
      ]);
    await launch(tester, api);
    expect(find.textContaining('A few things are missing'), findsOneWidget);
    expect(find.text('optional'), findsOneWidget);
    expect(find.text('Needs action'), findsNWidgets(2));
    await tester.tap(find.text('Download qwen3:8b'));
    await tester.pumpAndSettle();
    expect(api.setupActions.last.$1, 'pull_model');
    api.setupState = {
      ...api.setupState,
      'job': {'name': 'Speech to text', 'stage': 'Installing WhisperX and PyTorch, about 2 GB', 'running': true, 'done': false, 'error': null, 'completed': 0, 'total': 0},
    };
    await tester.tap(find.text('Set up speech to text'));
    await tester.pump();
    await tester.pump();
    expect(api.setupActions.last.$1, 'install_speech');
    expect(find.text('Installing WhisperX and PyTorch, about 2 GB'), findsOneWidget);
    expect(find.text('Working'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(api.setupActions.last.$1, 'cancel');
    api.setupState = {...api.setupState, 'job': null};
    await tester.pumpAndSettle(const Duration(seconds: 2));
  });

  testWidgets('a new project needs no footage, and opens on the Assistant', (tester) async {
    final api = FakeApi();
    await launch(tester, api);
    await tester.tap(find.text('New project'));
    await tester.pumpAndSettle();
    expect(find.text('Footage'), findsOneWidget, reason: 'only the side bar names footage; the dialog asks for a name and a place');
    await tester.enterText(find.widgetWithText(TextField, 'Project name'), 'Demo');
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(api.created?['footage'], isNull);
    expect(find.text('demo'), findsWidgets);
    expect(find.widgetWithText(TextField, 'Ask a question, or say what to change').hitTestable(), findsOneWidget);
  });

  group('a new project', () {
    late FakePicker picker;

    setUp(() => FileSelectorPlatform.instance = picker = FakePicker());

    Future<void> startDialog(WidgetTester tester, FakeApi api) async {
      await launch(tester, api);
      await tester.tap(find.text('New project'));
      await tester.pumpAndSettle();
    }

    FilledButton createButton(WidgetTester tester) => tester.widget(find.widgetWithText(FilledButton, 'Create'));

    testWidgets('can\'t be made without a name', (tester) async {
      await startDialog(tester, FakeApi());
      expect(createButton(tester).onPressed, isNull);
      await tester.enterText(find.widgetWithText(TextField, 'Project name'), '   ');
      await tester.pump();
      expect(createButton(tester).onPressed, isNull);
      await tester.enterText(find.widgetWithText(TextField, 'Project name'), 'Demo');
      await tester.pump();
      expect(createButton(tester).onPressed, isNotNull);
    });

    testWidgets('the name box has the keyboard straight away', (tester) async {
      await startDialog(tester, FakeApi());
      final field = tester.widget<EditableText>(find.byType(EditableText).last);
      expect(field.focusNode.hasPrimaryFocus, isTrue);
    });

    testWidgets('pressing return makes it', (tester) async {
      final api = FakeApi();
      await startDialog(tester, api);
      await tester.enterText(find.widgetWithText(TextField, 'Project name'), 'Demo');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(api.created?['name'], 'Demo');
    });

    testWidgets('can be saved somewhere else', (tester) async {
      final api = FakeApi();
      await startDialog(tester, api);
      picker.folders.add('/other/drive');
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(find.text('/other/drive'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Project name'), 'Demo');
      await tester.pump();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(api.created, {'name': 'Demo', 'location': '/other/drive', 'footage': null});
    });

    testWidgets('a footage folder with one clip adds it', (tester) async {
      final api = FakeApi()..folders = {'/picked/shoot': folderView('shoot', videos: ['take.mp4'])};
      await launch(tester, api);
      picker.folders.add('/picked/shoot');
      await tester.tap(find.text('Open folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(api.created?['footage'], '/picked/shoot');
      expect(api.actions.single.$1, 'add_clip');
      expect(api.actions.single.$2['path'], '/picked/shoot/take.mp4');
    });

    testWidgets('a footage folder with several clips asks which', (tester) async {
      final api = FakeApi()..folders = {'/picked/shoot': folderView('shoot', videos: ['one.mov', 'two.mp4'])};
      await launch(tester, api);
      picker.folders.add('/picked/shoot');
      await tester.tap(find.text('Open folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a clip from shoot'), findsOneWidget);
      expect(api.actions, isEmpty);
      await tester.tap(find.text('two.mp4'));
      await tester.pumpAndSettle();
      expect(api.actions.single.$2['path'], '/picked/shoot/two.mp4');
    });

    testWidgets('a folder of clips can be left out, and the project starts empty', (tester) async {
      final api = FakeApi()..folders = {'/picked/shoot': folderView('shoot', videos: ['take.mp4'])};
      await launch(tester, api);
      picker.folders.add('/picked/shoot');
      await tester.tap(find.text('Open folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Don't import"));
      await tester.pumpAndSettle();
      expect(find.text('/picked/shoot'), findsNothing);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(api.created?['footage'], isNull);
      expect(api.actions, isEmpty);
    });

    testWidgets('a project can\'t be saved inside its footage folder, and says so before closing', (tester) async {
      final api = FakeApi()..folders = {'/projects': folderView('projects', videos: ['take.mp4'])};
      await launch(tester, api);
      picker.folders.add('/projects');
      await tester.tap(find.text('Open folder'));
      await tester.pumpAndSettle();
      picker.folders.add('/projects');
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(find.textContaining('outside the footage folder'), findsOneWidget);
      expect(createButton(tester).onPressed, isNull);
      picker.folders.add('/other/drive');
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(find.textContaining('outside the footage folder'), findsNothing);
      expect(createButton(tester).onPressed, isNotNull);
    });

    testWidgets('a refused project stays on the projects page', (tester) async {
      final api = FakeApi()..refuseWith = 'Save the project outside the footage folder.';
      await startDialog(tester, api);
      await tester.enterText(find.widgetWithText(TextField, 'Project name'), 'Demo');
      await tester.pump();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(find.text('Save the project outside the footage folder.'), findsOneWidget);
      expect(find.text('New project').hitTestable(), findsOneWidget);
    });

    testWidgets('open folder opens a project, wherever it is', (tester) async {
      final api = FakeApi()..folders = {'/picked/away': folderView('away', project: true)};
      await launch(tester, api);
      picker.folders.add('/picked/away');
      await tester.tap(find.text('Open folder'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Ask a question, or say what to change').hitTestable(), findsOneWidget, reason: 'it has no footage yet');
    });

    testWidgets('open folder on a folder of clips starts a project from it', (tester) async {
      final api = FakeApi()..folders = {'/picked/shoot': folderView('shoot', videos: ['take.mp4'])};
      await launch(tester, api);
      picker.folders.add('/picked/shoot');
      await tester.tap(find.text('Open folder'));
      await tester.pumpAndSettle();
      expect(find.text('New project').last, findsOneWidget);
      expect(find.text('/picked/shoot'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Project name'), findsOneWidget);
      expect(tester.widget<EditableText>(find.byType(EditableText).last).controller.text, 'shoot');
    });

    testWidgets('open folder on an empty folder says so', (tester) async {
      final api = FakeApi()..folders = {'/picked/empty': folderView('empty')};
      await launch(tester, api);
      picker.folders.add('/picked/empty');
      await tester.tap(find.text('Open folder'));
      await tester.pumpAndSettle();
      expect(find.text('That folder has no project and no videos in it.'), findsOneWidget);
    });

    testWidgets('footage can come from a folder after the project exists', (tester) async {
      final api = FakeApi()..folders = {'/picked/shoot': folderView('shoot', videos: ['take.mp4'])};
      await launch(tester, api);
      await tester.tap(find.text('New project'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Project name'), 'Demo');
      await tester.pump();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      await go(tester, 'Footage');
      picker.folders.add('/picked/shoot');
      await tester.tap(find.text('Import from a folder'));
      await tester.pumpAndSettle();
      expect(api.actions.single.$2['path'], '/picked/shoot/take.mp4');
    });
  });

  testWidgets('a refused project shows why', (tester) async {
    final api = FakeApi()..refuseWith = 'That name is taken.';
    await launch(tester, api);
    await tester.tap(find.text('New project'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Project name'), 'Demo');
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('That name is taken.'), findsOneWidget);
  });

  testWidgets('the project page reports missing media', (tester) async {
    final api = FakeApi()
      ..current = state_(
        withFootage: true,
        missing: [
          {'kind': 'source', 'id': 'ast_main', 'reason': 'its file is missing'},
        ],
      );
    await launch(tester, api);
    await tester.tap(find.text('Open').first);
    await tester.pumpAndSettle();
    api.current = state_(
      withFootage: true,
      missing: [
        {'kind': 'source', 'id': 'ast_main', 'reason': 'its file is missing'},
      ],
    );
    await go(tester, 'Footage');
    await go(tester, 'Projects');
    expect(find.textContaining('Missing media'), findsOneWidget);
  });

  Future<FakeApi> opened(
    WidgetTester tester, {
    Json? shownPlan,
    List<Json>? plans,
    Json? style,
    Json? chat,
  }) async {
    final api = FakeApi()
      ..shownPlan = shownPlan
      ..chatState = chat ?? chatView()
      ..current = state_(withFootage: true, plans: plans ?? [planEntry('pln_r001')], latest: 'pln_r001', style: style);
    final saved = api.current;
    await launch(tester, api);
    api.current = saved;
    await tester.tap(find.text('Open').first);
    await tester.pumpAndSettle();
    return api;
  }

  testWidgets('Footage marks the clip being edited, and another can be chosen', (tester) async {
    final api = FakeApi()
      ..chatState = chatView()
      ..current = state_(withFootage: true, plans: [planEntry('pln_r001')], latest: 'pln_r001');
    api.current!['footage'] = footage(clips: [
      {'number': 1, 'id': 'ast_main', 'name': 'callmebot.mp4', 'matched': false, 'editing': true, 'path': '/m/a.mp4', 'width': 1920, 'height': 1080, 'fps': 60.0, 'seconds': 18.5, 'has_audio': true},
      {'number': 2, 'id': 'ast_clip2', 'name': 'firebase.mp4', 'matched': false, 'editing': false, 'path': '/m/b.mp4', 'width': 1920, 'height': 1080, 'fps': 60.0, 'seconds': 21.9, 'has_audio': true},
    ]);
    final saved = api.current;
    await launch(tester, api);
    api.current = saved;
    await tester.tap(find.text('Open').first);
    await tester.pumpAndSettle();
    await go(tester, 'Footage');
    expect(find.text('Editing'), findsOneWidget);
    expect(find.text('Edit this clip'), findsOneWidget);
    expect(find.text('Add to cut'), findsOneWidget);
    await tester.tap(find.text('Edit this clip'));
    await tester.pumpAndSettle();
    expect(api.actions.any((item) => item.$1 == 'edit_clip' && item.$2['clip'] == 'ast_clip2'), isTrue);
  });

  testWidgets('footage shows what analysis found', (tester) async {
    await opened(tester);
    await go(tester, 'Footage');
    expect(find.text('1920x1080, 60.000 fps'), findsOneWidget);
    expect(find.text('Transcript 1'), findsOneWidget);
    expect(find.text('Pauses 1'), findsOneWidget);
    expect(find.text('Now we build the board.'), findsWidgets);
    expect(find.text('noisy'), findsOneWidget);
    await tester.tap(find.text('Pauses 1'));
    await tester.pumpAndSettle();
    expect(find.text('quiet'), findsOneWidget);
  });

  testWidgets('a clip with an unsteady rate offers a copy, and only on a press', (tester) async {
    final api = await opened(tester);
    await go(tester, 'Footage');
    final state = state_(withFootage: true);
    state['footage'] = footage(offer: "It doesn't keep a steady rate.", analysed: false);
    api.current = state;
    await tester.tap(find.text('Check again').first, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(api.actions.where((item) => item.$1 == 'accept_copy'), isEmpty);
    await tester.tap(find.text('Make a constant-rate copy'));
    await tester.pumpAndSettle();
    expect(api.actions.last.$1, 'accept_copy');
  });

  testWidgets('the plan view shows cuts, flags, frames and the gate', (tester) async {
    await opened(tester);
    await go(tester, 'Review');
    expect(find.text('Revision r001'), findsOneWidget);
    expect(find.text('Passed all 7 gate stages'), findsOneWidget);
    expect(find.textContaining('Looks like instructions'), findsOneWidget);
    expect(find.text('Project overview'), findsOneWidget);
    expect(find.text('unfinished'), findsOneWidget);
    expect(find.text('Make preview'), findsOneWidget);
    await tester.tap(find.textContaining('Exact cuts'));
    await tester.pumpAndSettle();
    expect(find.text('1500'), findsOneWidget);
  });

  testWidgets('an export says what it made and where', (tester) async {
    final api = await opened(tester, shownPlan: planView('pln_r001'));
    api.outcome = (action, body) => action == 'export'
        ? {'name': action, 'state': 'done', 'result': {'path': '/p/exports/demo_r001.mp4', 'loudness': -19.2, 'width': 1080, 'height': 1920, 'seconds': 31.6}}
        : {'name': action, 'state': 'done'};
    await go(tester, 'Review');
    await tester.tap(find.text('Export MP4'));
    await tester.pumpAndSettle();
    expect(api.actions.last.$1, 'export');
    expect(api.actions.last.$2, {'plan': 'pln_r001'});
    expect(find.text('1080x1920, 32 s, loudness -19.2 to -14 LUFS'), findsOneWidget);
    expect(find.text('Show in Finder'), findsOneWidget);
  });

  testWidgets('a flagged sentence can be cut by a person', (tester) async {
    final api = await opened(tester);
    await go(tester, 'Review');
    await tester.tap(find.text('Cut it'));
    await tester.pumpAndSettle();
    expect(api.actions.last.$1, 'sentence');
    expect(api.actions.last.$2, {'plan': 'pln_r001', 'sentence': 's001', 'keep': false});
  });

  testWidgets('a note is sent with its frame, and can become a change', (tester) async {
    final api = await opened(tester);
    await go(tester, 'Review');
    await tester.enterText(find.widgetWithText(TextField, 'Note at this moment, such as: make this title faster'), 'too slow');
    await tester.tap(find.byTooltip('Add note'));
    await tester.pumpAndSettle();
    expect(api.actions.last.$2, {'plan': 'pln_r001', 'rec': 0, 'text': 'too slow'});
    await tester.tap(find.text('Make this change'));
    await tester.pumpAndSettle();
    expect(api.actions.last.$1, 'revise');
    expect(api.actions.last.$2['note'], 7);
  });

  testWidgets('nothing is approved until a person has seen what it means', (tester) async {
    final api = await opened(tester, shownPlan: planView('pln_r001', pending: ['apply_plan', 'confirm_removal']));
    await go(tester, 'Review');
    await tester.tap(find.text('Approve and build').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('more than 40%'), findsOneWidget);
    expect(find.textContaining('1 flagged sentence'), findsOneWidget);
    expect(api.actions, isEmpty);
    await tester.tap(find.text('Not yet'));
    await tester.pumpAndSettle();
    expect(api.actions, isEmpty);
    await tester.tap(find.text('Approve and build').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve and build').last);
    await tester.pumpAndSettle();
    expect(api.actions.last.$1, 'approve');
    expect(api.actions.last.$2['confirmed'], ['apply_plan', 'confirm_removal']);
  });

  testWidgets('what the real gate finds later goes back to the person', (tester) async {
    final api = await opened(tester);
    api.outcome = (action, body) {
      if (action == 'approve' && (body['confirmed'] as List).length == 1) {
        return {'name': action, 'state': 'failed', 'error': 'also needs', 'needs': ['overwrite_timeline']};
      }
      return {'name': action, 'state': 'done'};
    };
    await go(tester, 'Review');
    await tester.tap(find.text('Approve and build').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve and build').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('already in Resolve'), findsOneWidget);
    await tester.tap(find.text('Approve and build').last);
    await tester.pumpAndSettle();
    expect(api.actions.last.$2['confirmed'], ['apply_plan', 'overwrite_timeline']);
  });

  testWidgets('the Resolve page offers what fits the run', (tester) async {
    final cases = <String, (Json, String)>{
      'applied': (runView('APPLIED'), 'Render final'),
      'cancelled': (runView('CANCELLED'), 'Run again'),
      'stopped': (runView('NEEDS_USER', reason: 'Close the dialog in Resolve.'), 'Resume'),
      'interrupted': (runView('APPLYING'), 'Resume'),
      'unknown': (runView('UNKNOWN_OUTCOME', reason: "Can't tell."), 'Look again'),
      'hand edit': (runView('NEEDS_USER', reason: 'It changed by hand.', handEdited: true), 'Continue without those edits'),
    };
    for (final item in cases.entries) {
      await tester.pumpWidget(const SizedBox());
      await opened(tester, shownPlan: planView('pln_r001', state: item.value.$1['state'] as String, run: item.value.$1));
      await go(tester, 'Resolve');
      await tester.pumpAndSettle();
      expect(find.text(item.value.$2), findsOneWidget, reason: item.key);
    }
  });

  testWidgets('settling an unknown outcome records what the person said', (tester) async {
    final api = await opened(tester, shownPlan: planView('pln_r001', state: 'UNKNOWN_OUTCOME', run: runView('UNKNOWN_OUTCOME', reason: "Can't tell.")));
    await go(tester, 'Resolve');
    await tester.pumpAndSettle();
    await tester.tap(find.text("It didn't happen"));
    await tester.pumpAndSettle();
    expect(api.actions.last.$1, 'settle');
    expect(api.actions.last.$2['happened'], false);
  });

  testWidgets('the capability check runs when Resolve is opened, and reads only', (tester) async {
    final api = await opened(tester);
    api.outcome = (action, body) => {
      'name': action,
      'state': 'done',
      'result': {
        'product': 'DaVinci Resolve (free)', 'version': '20.3.0.10', 'page': 'edit', 'project': 'Untitled Project', 'wanted_project': 'AIE_demo',
        'capabilities': [
          {'id': 'timeline.overlay_track', 'status': 'verified', 'evidence': 'measured'},
          {'id': 'subtitle.auto', 'status': 'absent', 'evidence': 'Studio only'},
        ],
      },
    };
    await go(tester, 'Resolve');
    await tester.pumpAndSettle();
    expect(api.actions.single.$1, 'resolve_check');
    expect(find.text('timeline.overlay_track'), findsOneWidget);
    expect(find.text('absent'), findsOneWidget);
  });

  testWidgets('read-back says when a timeline no longer matches', (tester) async {
    final api = await opened(tester, shownPlan: planView('pln_r001', state: 'APPLIED', run: runView('APPLIED')));
    await go(tester, 'Resolve');
    await tester.pumpAndSettle();
    api.outcome = (action, body) => {
      'name': action,
      'state': 'done',
      if (action == 'read_back')
        'result': {
          'timeline': 'demo__r001', 'found': true, 'problems': ['missing video item on track 1 at 0'], 'hand_edited': true,
          'items': [
            {'kind': 'video', 'track': 1, 'rec_in': 0, 'rec_out': 10, 'source': 'ast_main', 'src_in': 0},
          ],
          'names': ['demo__r001'],
        },
    };
    await tester.tap(find.text('Read it now'));
    await tester.pumpAndSettle();
    expect(find.text('missing video item on track 1 at 0'), findsOneWidget);
    expect(find.textContaining('changed this timeline by hand'), findsOneWidget);
    expect(find.text('video 1: 1'), findsOneWidget);
  });

  testWidgets('the style page keeps measured apart from interpreted, and saves choices', (tester) async {
    final style = {
      'reference': 'look.png',
      'path': '/media/look.png',
      'measured': {
        'palette': [
          {'hex': '#101418', 'share': 0.62},
        ],
        'title_bbox_norm': [0.1, 0.7, 0.5, 0.2],
        'title_on_screen_s': null,
      },
      'interpreted': [
        {'claim': 'Dark overall look', 'confidence': 0.6, 'evidence': '#101418 covers 62%'},
      ],
      'chosen': {'palette': ['#101418', '#F2F4F7', '#FF6A3D'], 'zone': 'lower_left', 'font': 'Helvetica Neue', 'title_seconds': 2.5},
      'applied_to': {'palette': 'measured', 'zone': 'measured', 'font': 'user_choice', 'title_seconds': 'user_choice'},
      'not_copied': ['footage', 'music'],
    };
    final api = await opened(tester, style: style);
    await go(tester, 'Style');
    expect(find.text('Measured from look.png'), findsOneWidget);
    expect(find.text('Interpreted'), findsOneWidget);
    expect(find.textContaining('60% sure'), findsOneWidget);
    expect(find.text('Never copied: footage, music.'), findsOneWidget);
    await tester.tap(find.text('Save style'));
    await tester.pumpAndSettle();
    expect(api.actions, isEmpty, reason: 'nothing changed, so nothing becomes a person\'s choice');
    await tester.enterText(find.widgetWithText(TextField, '#FF6A3D').last, '#00FF00');
    await tester.tap(find.text('Save style'));
    await tester.pumpAndSettle();
    expect(api.actions.last.$1, 'style');
    expect(api.actions.last.$2, {'palette': ['#101418', '#F2F4F7', '#00FF00']});
  });

  testWidgets('a bad colour is caught before it is sent', (tester) async {
    final style = {
      'reference': 'look.png',
      'path': '/media/look.png',
      'measured': {'palette': <Json>[], 'title_bbox_norm': [0, 0, 1, 1], 'title_on_screen_s': null},
      'interpreted': <Json>[],
      'chosen': {'palette': ['#101418', '#F2F4F7', '#FF6A3D'], 'zone': 'lower_left', 'font': 'Helvetica Neue', 'title_seconds': 2.5},
      'applied_to': <String, String>{},
      'not_copied': <String>[],
    };
    final api = await opened(tester, style: style);
    await go(tester, 'Style');
    await tester.enterText(find.widgetWithText(TextField, '#101418'), 'red');
    await tester.tap(find.text('Save style'));
    await tester.pumpAndSettle();
    expect(find.text('Colours look like #FF6A3D.'), findsOneWidget);
    expect(api.actions, isEmpty);
  });

  testWidgets('reference words are suggested, and only a press of Search sends them', (tester) async {
    final api = await opened(tester);
    api.outcome = (action, body) => switch (action) {
      'reference_words' => {'name': action, 'state': 'done', 'result': {'words': 'robotic arm build', 'why': 'From what\'s said in the clip.'}},
      'find_references' => {
        'name': action,
        'state': 'done',
        'result': {
          'results': [
            {'id': 'abcdefghijk', 'title': 'Candy-grabbing robot arm', 'channel': 'Maker', 'seconds': 52, 'views': 9889528, 'short': true, 'link': 'x'},
          ],
        },
      },
      _ => {'name': action, 'state': 'done'},
    };
    await go(tester, 'Style');
    await tester.tap(find.text('Suggest words'));
    await tester.pumpAndSettle();
    expect(api.actions.map((item) => item.$1), ['reference_words'], reason: 'suggesting sends nothing anywhere');
    expect(find.widgetWithText(TextField, 'robotic arm build'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'robotic arm build'), 'robot arm');
    await tester.tap(find.descendant(of: find.byType(FindReferences), matching: find.widgetWithText(FilledButton, 'Search')));
    await tester.pumpAndSettle();
    expect(api.actions.last.$1, 'find_references');
    expect(api.actions.last.$2, {'words': 'robot arm'});
    expect(find.text('Candy-grabbing robot arm'), findsOneWidget);
    expect(find.textContaining('9.9M views'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(FindReferences), matching: find.widgetWithText(TextButton, 'Use')));
    await tester.pumpAndSettle();
    expect(api.actions.last.$1, 'use_reference');
    expect(api.actions.last.$2, {'id': 'abcdefghijk', 'short': true});
  });

  testWidgets('free music is offered with its licence, and the chosen track shows its credit', (tester) async {
    final api = await opened(tester);
    api.outcome = (action, body) => switch (action) {
      'find_music' => {
        'name': action,
        'state': 'done',
        'result': {
          'results': [
            {'id': 'b8d2f3dc-d124-434c-998f-64c6f4ac7991', 'title': 'Upbeat Funky Loop', 'creator': 'ispeakwaves', 'licence': 'by', 'seconds': 32, 'credit': 'c', 'url': 'u'},
          ],
        },
      },
      _ => {'name': action, 'state': 'done'},
    };
    await go(tester, 'Style');
    expect(find.text('No music chosen.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Free music from Openverse, such as upbeat electronic').hitTestable(), 'upbeat');
    await tester.tap(find.descendant(of: find.byType(MusicSection), matching: find.widgetWithText(OutlinedButton, 'Search')));
    await tester.pumpAndSettle();
    expect(api.actions.last.$1, 'find_music');
    expect(api.actions.last.$2, {'words': 'upbeat'});
    expect(find.text('CC BY'), findsOneWidget);
    api.current!['music'] = {'id': 'music_1', 'title': 'Upbeat Funky Loop', 'credit': '"Upbeat Funky Loop" by ispeakwaves is licensed under CC BY 4.0.',
                             'licence': 'by', 'seconds': 32.0, 'bpm': 120.0, 'beats': 64};
    await tester.tap(find.descendant(of: find.byType(MusicSection), matching: find.widgetWithText(TextButton, 'Use')));
    await tester.pumpAndSettle();
    expect(api.actions.last.$1, 'use_music');
    expect(api.actions.last.$2, {'id': 'b8d2f3dc-d124-434c-998f-64c6f4ac7991'});
    expect(find.textContaining('120.0 BPM'), findsOneWidget);
    expect(find.textContaining('Credit: "Upbeat Funky Loop" by ispeakwaves'), findsOneWidget);
  });

  testWidgets('activity shows revisions, assets, metrics and the log', (tester) async {
    final api = await opened(tester);
    final state = api.current!;
    (state['activity'] as Json).addAll({
      'events': [
        {'at': '2026-11-02T17:00:00.000+00:00', 'kind': 'plan_proposed', 'message': 'Proposed pln_r001'},
      ],
      'model_calls': [
        {'purpose': 'labels', 'attempts': 1, 'prompt_tokens': 1300, 'output_tokens': 200, 'seconds': 12.5, 'outcome': 'ok', 'created_at': 'x'},
      ],
      'assets': [
        {'id': 'ast_main', 'kind': 'source', 'name': 'pcb.mp4', 'hash': 'abcdef0123456789', 'frames': 5657},
      ],
      'versions': [
        {'asset': 'ast_title1', 'rev': 2, 'path': '/p', 'hash': 'aa', 'frames': 150, 'stale': true, 'details': {'tool': '0.20.0'}},
      ],
    });
    await go(tester, 'Activity');
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Proposed pln_r001'), findsOneWidget);
    expect(find.textContaining('1300 tokens in'), findsWidgets);
    expect(find.text('ast_main'), findsOneWidget);
    expect(find.text('ast_title1 r2'), findsOneWidget);
    expect(find.text('out of date'), findsOneWidget);
  });

  testWidgets('a failed job shows its reason and can be dismissed', (tester) async {
    final api = await opened(tester);
    api.outcome = (action, body) => {'name': action, 'state': 'failed', 'error': "Ollama isn't running. Start it, then try again."};
    await go(tester, 'Review');
    await tester.tap(find.text('Make plan'));
    await tester.pumpAndSettle();
    expect(find.text("Ollama isn't running. Start it, then try again."), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text("Ollama isn't running. Start it, then try again."), findsNothing);
  });

  group('the assistant', () {
    testWidgets('needs a project, and each project starts with its own', (tester) async {
      await launch(tester, FakeApi());
      await go(tester, 'Assistant');
      expect(find.text('Open a project first'), findsWidgets);
    });

    testWidgets('offers ideas in an empty conversation and sends one', (tester) async {
      final api = await opened(tester);
      await go(tester, 'Assistant');
      expect(find.text('Ask about this project, or tell it what to change'), findsOneWidget);
      await tester.tap(find.text('Summarise this video'));
      await tester.pumpAndSettle();
      expect(api.actions.last.$1, 'ask');
      expect(api.actions.last.$2, {'text': 'Summarise this video', 'plan': 'pln_r001'});
    });

    testWidgets('shows the words of a reply as they arrive, and can stop it', (tester) async {
      final api = await opened(tester);
      var polls = 0;
      api.outcome = (action, body) {
        polls++;
        if (polls < 3) return {'name': action, 'state': 'running', 'step': 'Asking qwen3:8b', 'partial': 'Part of the answer'};
        return {'name': action, 'state': 'done', 'result': {'answer': 'done'}};
      };
      await go(tester, 'Assistant');
      await tester.enterText(find.widgetWithText(TextField, 'Ask a question, or say what to change'), 'What is this?');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('What is this?'), findsOneWidget);
      expect(find.text('Part of the answer'), findsOneWidget);
      await tester.tap(find.byTooltip('Stop'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(api.stopped, 1);
    });

    testWidgets('shows the conversation and which model answered', (tester) async {
      await opened(tester, chat: chatView(messages: [
        {'id': 1, 'role': 'user', 'text': 'Who is the sponsor?', 'model': null, 'created_at': 'x'},
        {'id': 2, 'role': 'assistant', 'text': 'It is Acme.', 'model': 'llama3.2:3b', 'created_at': 'x'},
      ]));
      await go(tester, 'Assistant');
      expect(find.text('Who is the sponsor?'), findsOneWidget);
      expect(find.text('It is Acme.'), findsOneWidget);
      expect(find.text('llama3.2:3b'), findsWidgets);
    });

    testWidgets('a reply updates the project\'s record, so usage stays true', (tester) async {
      final api = await opened(tester);
      await go(tester, 'Assistant');
      api.current = state_(withFootage: true, plans: [planEntry('pln_r001')], latest: 'pln_r001');
      (api.current!['activity'] as Json)['model_calls'] = [
        {'purpose': 'chat', 'attempts': 1, 'prompt_tokens': 900, 'output_tokens': 40, 'seconds': 2.0, 'outcome': 'ok', 'created_at': 'x'},
      ];
      await tester.tap(find.text('Summarise this video'));
      await tester.pumpAndSettle();
      await go(tester, 'Settings');
      expect(find.text('1 model calls, 900 tokens in, 40 out'), findsOneWidget);
    });

    testWidgets('a person chooses a model for one project, or goes back to the default', (tester) async {
      final api = await opened(tester);
      await go(tester, 'Settings');
      await go(tester, 'Assistant');
      await tester.tap(find.text('Same as default (qwen3:8b)').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('llama3.2:3b').last);
      await tester.pumpAndSettle();
      expect(api.actions.last.$1, 'choose_model');
      expect(api.actions.last.$2, {'model': 'llama3.2:3b'});
    });

    testWidgets('a request that made a revision opens it on Review', (tester) async {
      final api = await opened(tester, chat: chatView(messages: [
        {'id': 2, 'role': 'assistant', 'text': 'Done as r002: I cut 1 sentence.', 'model': 'qwen3:8b', 'plan_id': 'pln_r001', 'created_at': 'x'},
      ]));
      await go(tester, 'Assistant');
      await tester.tap(find.text('See it on Review'));
      await tester.pumpAndSettle();
      expect(find.text('Revision r001').hitTestable(), findsOneWidget);
      expect(api.actions, isEmpty);
    });

    testWidgets('a reply that made a revision moves the app to that revision', (tester) async {
      final api = await opened(tester);
      api.outcome = (action, body) => {
        'name': action,
        'state': 'done',
        'result': {'answer': 'Done', 'plan': 'pln_r002'},
      };
      api.shownPlan = null;
      await go(tester, 'Assistant');
      await tester.enterText(find.widgetWithText(TextField, 'Ask a question, or say what to change'), 'cut the intro');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      await go(tester, 'Review');
      expect(find.text('Revision r002').hitTestable(), findsOneWidget);
    });

    testWidgets('it asks about style one question at a time, and each can be skipped', (tester) async {
      final api = await opened(tester, chat: chatView(brief: briefView(asking: question())));
      await go(tester, 'Assistant');
      expect(find.text('How tight should the cut feel?'), findsOneWidget);
      expect(find.text('1 of 5'), findsOneWidget);
      await tester.tap(find.text('Tight: every quiet pause goes'));
      await tester.pumpAndSettle();
      expect(api.actions.last.$1, 'answer_style');
      expect(api.actions.last.$2, {'key': 'pacing', 'value': 'tight'});
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(api.actions.last.$2, {'key': 'pacing', 'value': null});
    });

    testWidgets('it doesn\'t ask about style before there is a clip to edit', (tester) async {
      await opened(tester, chat: chatView(brief: briefView(asking: question()), canEdit: false));
      await go(tester, 'Assistant');
      expect(find.text('How tight should the cut feel?'), findsNothing);
    });

    testWidgets('a made video can be opened in EffectCraft from its reply', (tester) async {
      await opened(tester, chat: chatView(messages: [
        {'id': 1, 'role': 'assistant', 'text': 'I made a video', 'model': null, 'plan_id': 'pln_r001', 'created_at': 'x', 'video': {'project': '/p/video-1.ecproj', 'start': 90, 'clip': 'ast_clip2'}},
      ]));
      await go(tester, 'Assistant');
      expect(find.text('Open in EffectCraft').hitTestable(), findsOneWidget);
      expect(find.text('See it on Review').hitTestable(), findsOneWidget);
    });

    testWidgets('Review lists where each clip starts', (tester) async {
      final view = planView('pln_r001');
      view['clip_starts'] = [
        {'number': 1, 'name': 'phone.mp4', 'rec_in': 0},
        {'number': 2, 'name': 'video-1.mp4', 'rec_in': 999},
      ];
      await opened(tester, shownPlan: view);
      await go(tester, 'Review');
      expect(find.text('Clips in this cut'), findsOneWidget);
      expect(find.text('video-1.mp4'), findsOneWidget);
    });

    testWidgets('a tool waits for Allow, and Allow is what runs it', (tester) async {
      final api = await opened(tester, chat: chatView(messages: [
        {'id': 1, 'role': 'user', 'text': 'take a screenshot in fusion', 'model': null, 'plan_id': null, 'created_at': 'x'},
        {'id': 2, 'role': 'assistant', 'text': 'I would like to use fusion_screenshot. Nothing runs unless you allow it.', 'model': 'qwen3:8b', 'plan_id': null, 'created_at': 'x', 'waiting_tool': true},
      ]));
      await go(tester, 'Assistant');
      expect(find.text('Allow').hitTestable(), findsOneWidget);
      expect(api.actions.where((item) => item.$1 == 'resolve_tool'), isEmpty);
      await tester.tap(find.text('Allow').hitTestable());
      await tester.pumpAndSettle();
      expect(api.actions.last.$1, 'resolve_tool');
      expect(api.actions.last.$2, {'allow': true});
    });

    testWidgets('Settings lists skills and servers, and adds one from Claude Code', (tester) async {
      final api = await opened(tester);
      await go(tester, 'Settings');
      await tester.pumpAndSettle();
      expect(find.text('motion-graphics'), findsOneWidget);
      expect(find.text('fusion360'), findsWidgets);
      await tester.tap(find.widgetWithText(TextButton, 'Add').hitTestable().first);
      await tester.pumpAndSettle();
      expect(api.extensionChanges.last, {'op': 'add_skill', 'folder': '/claude/cut-the-curve'});
    });

    testWidgets('a learned style is listed under Styles, not with the skills', (tester) async {
      final api = await opened(tester);
      await go(tester, 'Settings');
      await tester.pumpAndSettle();
      expect(find.text('Styles'), findsOneWidget);
      expect(find.text('Robo Arm style'), findsOneWidget);
      expect(find.text('Learn from my videos'), findsOneWidget);
      final remove = find.descendant(of: find.widgetWithText(Row, 'Robo Arm style'), matching: find.widgetWithText(TextButton, 'Remove'));
      await tester.tap(remove.first);
      await tester.pumpAndSettle();
      expect(api.extensionChanges.last, {'op': 'remove_skill', 'folder': '/skills/robo-arm-style'});
    });

    testWidgets('the side bar folds to its icons and back', (tester) async {
      await opened(tester);
      expect(find.text('Footage'), findsOneWidget);
      await tester.tap(find.text('Collapse'));
      await tester.pumpAndSettle();
      expect(find.text('Footage'), findsNothing);
      await tester.tap(find.byTooltip('Expand the side bar'));
      await tester.pumpAndSettle();
      expect(find.text('Footage'), findsOneWidget);
    });

    testWidgets('resting on Settings offers its sections, and one opens there', (tester) async {
      await opened(tester);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(find.text('Settings').first));
      await tester.pumpAndSettle();
      final choice = find.widgetWithText(MenuItemButton, 'MCP servers');
      expect(choice, findsOneWidget);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(find.text('Add a server').hitTestable(), findsOneWidget);
      await gesture.removePointer();
    });

    testWidgets('a reference can come from a link', (tester) async {
      final api = await opened(tester);
      await go(tester, 'Style');
      await tester.tap(find.text('From a link').hitTestable());
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'https://'), '  https://example.com/look.mp4 ');
      await tester.tap(find.text('Use this link'));
      await tester.pumpAndSettle();
      expect(api.actions.last.$1, 'reference_link');
      expect(api.actions.last.$2, {'link': 'https://example.com/look.mp4'});
    });

    testWidgets('an empty link does nothing, and cancelling sends nothing', (tester) async {
      final api = await opened(tester);
      final before = api.actions.length;
      await go(tester, 'Style');
      await tester.tap(find.text('From a link').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this link'));
      await tester.pumpAndSettle();
      expect(find.text('Use this link'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.actions.length, before);
    });

    testWidgets('both ways in for a reference are on the Assistant too', (tester) async {
      await opened(tester);
      await go(tester, 'Assistant');
      expect(find.text('From computer').hitTestable(), findsOneWidget);
      expect(find.text('From a link').hitTestable(), findsOneWidget);
    });

    testWidgets('a reference that suggests an answer says so', (tester) async {
      await opened(tester, chat: chatView(brief: briefView(asking: question(suggested: 'relaxed'))));
      await go(tester, 'Assistant');
      expect(find.text('Relaxed: only long pauses go (matches your reference)'), findsOneWidget);
    });

    testWidgets('answers show, and can be applied to the current cut', (tester) async {
      final api = await opened(tester, chat: chatView(brief: briefView(answers: [
        {'key': 'pacing', 'text': 'How tight should the cut feel?', 'label': 'Relaxed: only long pauses go'},
      ])));
      await go(tester, 'Assistant');
      expect(find.text('Relaxed: only long pauses go'), findsOneWidget);
      await tester.tap(find.text('Apply to r001'));
      await tester.pumpAndSettle();
      expect(api.actions.last.$1, 'apply_brief');
      await tester.tap(find.text('Start over'));
      await tester.pumpAndSettle();
      expect(api.actions.last.$1, 'reset_brief');
    });

    testWidgets('a person adds to memory, and can forget it', (tester) async {
      final api = await opened(tester, chat: chatView(memory: [
        {'id': 3, 'text': 'The sponsor is Acme.'},
      ]));
      await go(tester, 'Assistant');
      expect(find.text('The sponsor is Acme.'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Something to remember'), 'Keep it short.');
      await tester.tap(find.byTooltip('Remember'));
      await tester.pumpAndSettle();
      expect(api.actions.last.$1, 'remember');
      expect(api.actions.last.$2, {'text': 'Keep it short.'});
      await tester.tap(find.byTooltip('Forget this'));
      await tester.pumpAndSettle();
      expect(api.actions.last.$1, 'forget');
      expect(api.actions.last.$2, {'id': 3});
    });

    testWidgets('saving a long reply to memory keeps it within the limit', (tester) async {
      final api = await opened(tester, chat: chatView(messages: [
        {'id': 2, 'role': 'assistant', 'text': 'x' * 900, 'model': 'qwen3:8b', 'created_at': 'x'},
      ]));
      await go(tester, 'Assistant');
      await tester.tap(find.byTooltip('Remember this'));
      await tester.pumpAndSettle();
      expect((api.actions.last.$2['text'] as String).length, lessThanOrEqualTo(400));
    });

    testWidgets('clearing a conversation asks first', (tester) async {
      final api = await opened(tester, chat: chatView(messages: [
        {'id': 1, 'role': 'user', 'text': 'Hello', 'model': null, 'created_at': 'x'},
      ]));
      await go(tester, 'Assistant');
      await tester.tap(find.text('Clear conversation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(api.actions, isEmpty);
      await tester.tap(find.text('Clear conversation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(api.actions.last.$1, 'clear_chat');
    });

    testWidgets('opening another project replaces the conversation', (tester) async {
      final api = await opened(tester, chat: chatView(messages: [
        {'id': 1, 'role': 'user', 'text': 'From the first project', 'model': null, 'created_at': 'x'},
      ]));
      await go(tester, 'Assistant');
      expect(find.text('From the first project'), findsOneWidget);
      api.chatState = chatView();
      await go(tester, 'Projects');
      await tester.tap(find.text('Open').first);
      await tester.pumpAndSettle();
      await go(tester, 'Assistant');
      expect(find.text('From the first project'), findsNothing);
    });

    testWidgets('a model removed from this Mac is shown, not lost', (tester) async {
      await opened(tester, chat: chatView(choice: 'gone:1b'));
      await go(tester, 'Settings');
      await go(tester, 'Assistant');
      expect(find.text('gone:1b (not installed)'), findsWidgets);
    });
  });

  group('clips moving between apps', () {
    testWidgets('a clip comes in from Resolve', (tester) async {
      final api = FakeApi();
      await launch(tester, api);
      await tester.tap(find.text('New project'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Project name'), 'Demo');
      await tester.pump();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      await go(tester, 'Footage');
      api.outcome = (action, body) => {
        'name': action,
        'state': 'done',
        if (action == 'resolve_clips')
          'result': {
            'project': 'My Film',
            'clips': [
              {'name': 'A001.mov', 'path': '/media/a/A001.mov'},
            ],
          },
      };
      await tester.tap(find.text('From Resolve'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a clip from My Film'), findsOneWidget);
      await tester.tap(find.text('A001.mov'));
      await tester.pumpAndSettle();
      expect(api.actions.last.$1, 'add_clip');
      expect(api.actions.last.$2, {'path': '/media/a/A001.mov'});
    });

    testWidgets('an empty media pool says so', (tester) async {
      final api = FakeApi();
      await launch(tester, api);
      await tester.tap(find.text('New project'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Project name'), 'Demo');
      await tester.pump();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      await go(tester, 'Footage');
      api.outcome = (action, body) => {
        'name': action,
        'state': 'done',
        'result': {'project': 'My Film', 'clips': <Json>[]},
      };
      await tester.tap(find.text('From Resolve'));
      await tester.pumpAndSettle();
      expect(find.text('My Film has no video in its media pool.'), findsOneWidget);
    });

    Json sendables(String action, Json body) => {
      'name': action,
      'state': 'done',
      if (action == 'sendable')
        'result': {
          'items': [
            {'key': 'original', 'label': 'The original clip', 'path': '/media/pcb.mp4'},
            {'key': 'render:pln_r001', 'label': 'Final render of r001', 'path': '/p/renders/pln_r001.mov'},
          ],
        },
      if (action == 'send_to_resolve') 'result': {'name': 'pln_r001.mov', 'project': 'My Film'},
      if (action == 'send_to_effectcraft') 'result': {'project': '/p/exports/demo-original.ecproj'},
    };

    testWidgets('a clip goes to Resolve by its key, never by a path', (tester) async {
      final api = await opened(tester);
      api.outcome = sendables;
      await go(tester, 'Footage');
      await tester.tap(find.text('Send to Resolve').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Final render of r001'));
      await tester.pumpAndSettle();
      expect(api.actions.last.$2, {'key': 'render:pln_r001'});
      expect(find.textContaining('is now in My Film'), findsOneWidget);
    });

    testWidgets('a clip goes to EffectCraft and offers to open there', (tester) async {
      final api = await opened(tester);
      api.outcome = sendables;
      await go(tester, 'Footage');
      await tester.tap(find.text('Send to EffectCraft').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('The original clip'));
      await tester.pumpAndSettle();
      expect(api.actions.last.$1, 'send_to_effectcraft');
      expect(find.text('Open in EffectCraft'), findsOneWidget);
    });

    testWidgets('while the AI works it shows dots, not words', (tester) async {
      final api = await opened(tester);
      var polls = 0;
      api.outcome = (action, body) {
        polls++;
        if (polls < 3) return {'name': action, 'state': 'running', 'step': 'Making the new revision', 'partial': ''};
        return {'name': action, 'state': 'done', 'result': {'answer': 'Done'}};
      };
      await go(tester, 'Assistant');
      await tester.enterText(find.widgetWithText(TextField, 'Ask a question, or say what to change'), 'cut the first 3 seconds');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('ai-typing')), findsOneWidget);
      // The bubble says what's happening. The status bar says it too, on its own line.
      expect(find.descendant(of: find.byKey(const ValueKey('ai-typing')), matching: find.text('Making the new revision')), findsOneWidget);
      expect(find.text('Thinking'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-typing')), findsNothing);
    });

    testWidgets('a cut can be sent from Review too', (tester) async {
      final api = await opened(tester);
      api.outcome = sendables;
      await go(tester, 'Review');
      await tester.tap(find.text('Send to EffectCraft').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('The original clip'), findsOneWidget);
      expect(api.actions.last.$1, 'sendable');
    });

    testWidgets('b-roll is listed on Review and can be removed', (tester) async {
      final view = planView('pln_r001');
      view['broll'] = [
        {'thing': 'ESP32 board', 'rec_in': 300, 'frames': 150, 'picture': '/p/esp32.png'},
        {'thing': 'rotary encoder', 'rec_in': 900, 'frames': 150, 'picture': null},
      ];
      final api = await opened(tester, shownPlan: view);
      await go(tester, 'Review');
      expect(find.text('B-roll'), findsOneWidget);
      expect(find.text('ESP32 board'), findsOneWidget);
      expect(find.text('no photo'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove this b-roll').first);
      await tester.pumpAndSettle();
      expect(api.actions.last.$1, 'remove_broll');
      expect(api.actions.last.$2, {'plan': 'pln_r001', 'thing': 'ESP32 board'});
    });

    testWidgets('a short says it is 9:16 on Review', (tester) async {
      final view = planView('pln_r002')
        ..['width'] = 1080
        ..['height'] = 1920;
      await opened(tester, shownPlan: view);
      await go(tester, 'Review');
      expect(find.text('9:16 short, 1080 × 1920, cropped from the middle'), findsOneWidget);
    });

    testWidgets('a wide cut has no shape line', (tester) async {
      final view = planView('pln_r001')
        ..['width'] = 1920
        ..['height'] = 1080;
      await opened(tester, shownPlan: view);
      await go(tester, 'Review');
      expect(find.textContaining('9:16'), findsNothing);
    });

    testWidgets('text on screen is listed on Review', (tester) async {
      final view = planView('pln_r001');
      view['texts'] = [
        {'text': 'Fusion 360', 'zone': 'left', 'rec_in': 0, 'frames': 240},
      ];
      await opened(tester, shownPlan: view);
      await go(tester, 'Review');
      expect(find.text('Text on screen'), findsOneWidget);
      expect(find.text('Fusion 360'), findsOneWidget);
      expect(find.text('left'), findsOneWidget);
    });

    testWidgets('a plan with an EffectCraft graphic shows it', (tester) async {
      final view = planView('pln_r001');
      view['title'] = null;
      view['graphic'] = {'asset': 'ast_graphic', 'rev': 1, 'rec_in': 3, 'frames': 90};
      final api = await opened(tester, shownPlan: view);
      await go(tester, 'Review');
      expect(find.text('Graphic from EffectCraft'), findsOneWidget);
      expect(find.text('90 frames'), findsOneWidget);
      await tester.tap(find.text('Use a generated title next time'));
      await tester.pumpAndSettle();
      expect(api.actions.last.$1, 'clear_graphic');
    });
  });

  group('settings', () {
    testWidgets('a Hugging Face model is found, downloaded and then listed', (tester) async {
      final api = FakeApi();
      await launch(tester, api);
      await go(tester, 'Settings');
      await tester.enterText(find.widgetWithText(TextField, 'Search, such as llama 3b, or paste a repository'), 'llama 3b');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Search'));
      await tester.pumpAndSettle();
      expect(api.modelSearches, ['llama 3b']);
      expect(find.text('120k downloads'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Choose'));
      await tester.pumpAndSettle();
      // The size Ollama picks by default is chosen first.
      expect(find.widgetWithText(FilledButton, 'Download Q4_K_M'), findsOneWidget);
      await tester.tap(find.textContaining('Q3_K_L'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Download Q3_K_L'));
      await tester.pump();
      expect(api.downloads, [('bartowski/Llama-3.2-3B-Instruct-GGUF', 'Q3_K_L')]);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Downloading'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.textContaining('On this Mac'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsNothing);
      // Now it's one of this Mac's models, so it can be the default.
      expect(find.text('hf.co/bartowski/Llama-3.2-3B-Instruct-GGUF:Q3_K_L'), findsNWidgets(2));
    });

    testWidgets('a pasted repository goes straight to its files', (tester) async {
      final api = FakeApi();
      await launch(tester, api);
      await go(tester, 'Settings');
      await tester.enterText(find.widgetWithText(TextField, 'Search, such as llama 3b, or paste a repository'), 'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(api.modelSearches, isEmpty);
      expect(find.widgetWithText(FilledButton, 'Download Q4_K_M'), findsOneWidget);
    });

    testWidgets('work with no project open', (tester) async {
      await launch(tester, FakeApi());
      await go(tester, 'Settings');
      expect(find.text('qwen3:8b'), findsOneWidget);
      expect(find.text('llama3.2:3b'), findsOneWidget);
      expect(find.text('Test Person'), findsOneWidget);
      expect(find.text('tester'), findsOneWidget);
      expect(find.textContaining('No sign-in, subscription or API key'), findsOneWidget);
      expect(find.textContaining('Not signed in'), findsOneWidget);
      expect(find.textContaining('the only model tested'), findsOneWidget);
    });

    testWidgets('a license key is checked, says who it is for, and can be removed', (tester) async {
      final api = FakeApi()..appSettings = {...settingsView(), 'license': {'tier': 'free', 'pro': false, 'license': null}};
      await launch(tester, api);
      await go(tester, 'Settings');
      expect(find.textContaining('Pro adds shorts, music'), findsOneWidget);
      final field = find.widgetWithText(TextField, 'Paste your key, starting with AIE1-');
      await tester.enterText(field, 'nonsense');
      await tester.tap(find.text('Add key'));
      await tester.pumpAndSettle();
      expect(find.textContaining("isn't valid"), findsOneWidget);
      await tester.enterText(field, 'AIE1-abc.def');
      await tester.tap(find.text('Add key'));
      await tester.pumpAndSettle();
      expect(api.licenseKeys.last, 'AIE1-abc.def');
      expect(find.text('Pro, for Ada. Updates until 2027-11-05.'), findsOneWidget);
      await tester.tap(find.text('Remove key'));
      await tester.pumpAndSettle();
      expect(find.text('Add key'), findsOneWidget);
    });

    testWidgets('change the default model', (tester) async {
      final api = FakeApi();
      await launch(tester, api);
      await go(tester, 'Settings');
      await tester.tap(find.text('Make default'));
      await tester.pumpAndSettle();
      expect(api.appSettings['default_model'], 'llama3.2:3b');
      expect(find.text('Make default'), findsOneWidget);
    });

    testWidgets('say so when Ollama is away', (tester) async {
      final api = FakeApi()
        ..appSettings = {
          ...settingsView(ollama: {'running': false, 'version': null, 'signed_in': false, 'account': null}),
          'models': <Json>[],
        };
      await launch(tester, api);
      await go(tester, 'Settings');
      expect(find.text('Not running'), findsOneWidget);
      expect(find.textContaining('No models found'), findsOneWidget);
    });

    testWidgets('show a signed-in Ollama account', (tester) async {
      final api = FakeApi()
        ..appSettings = settingsView(ollama: {
          'running': true,
          'version': '0.33.0',
          'signed_in': true,
          'account': {'name': 'Pat', 'plan': 'free'},
        });
      await launch(tester, api);
      await go(tester, 'Settings');
      expect(find.text('Signed in as Pat, free'), findsOneWidget);
    });

    testWidgets('show the open project with its own choice and usage', (tester) async {
      await opened(tester);
      await go(tester, 'Settings');
      expect(find.text('This project: demo'), findsOneWidget);
      expect(find.text('Same as default (qwen3:8b)'), findsWidgets);
      expect(find.text('0 model calls, 0 tokens in, 0 out'), findsOneWidget);
    });
  });

  test('learning a style sends the videos and says when it is done', () async {
    final api = FakeApi()..current = state_(withFootage: true);
    final model = ProjectModel(api, pollEvery: Duration.zero);
    await model.learnStyle('Robo Arm style', ['/Movies/Robo Arm.mp4']);
    expect(api.extensionChanges.last, {'op': 'learn_style', 'name': 'Robo Arm style', 'paths': ['/Movies/Robo Arm.mp4']});
    expect(model.busy, isFalse);
    expect(model.notice, 'Learned Robo Arm style');
  });

  test('a running build can be cancelled, and only that kind of job', () async {
    final api = FakeApi()..current = state_(withFootage: true);
    final model = ProjectModel(api, pollEvery: Duration.zero);
    await model.open('/projects/demo');
    var calls = 0;
    api.outcome = (action, body) {
      calls++;
      if (calls == 1) {
        model.cancel();
        return {'name': action, 'state': 'running', 'step': 'Building'};
      }
      return {'name': action, 'state': 'done'};
    };
    await model.run('approve', {'plan': 'pln_r001'}, 'Building', cancellable: true);
    expect(api.cancelled, ['pln_r001']);
    expect(model.busy, isFalse);
    await model.run('preview', {'plan': 'pln_r001'}, 'Previewing');
    expect(api.cancelled, ['pln_r001']);
  });

  test('a long path keeps its end, and a sentence is left alone', () {
    expect(endOfPath('/Volumes/1TB/Projects/app/shoot'), '…/Projects/app/shoot');
    expect(endOfPath('/Volumes/1TB/shoot'), '/Volumes/1TB/shoot');
    expect(endOfPath('Optional. Pick a folder from anywhere. Your files stay where they are.'), 'Optional. Pick a folder from anywhere. Your files stay where they are.');
  });

  test('times read the way a person says them', () {
    expect(formatTime(const Duration(minutes: 1, seconds: 5)), '01:05');
    expect(fineClock(65.25), '1:05.3');
    expect(frameAndTime(90, 60), '90  (0:01.5)');
  });
}
