import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'engine.dart';

/// Who approvals are recorded against.
String get reviewer => Platform.environment['USER'] ?? 'reviewer';

/// A job the engine is working on, as the status bar shows it.
class RunningJob {
  RunningJob(this.label, {this.plan, this.step}) : started = DateTime.now();

  final String label;

  /// Set when the job can be cancelled, which only applying a plan can.
  final String? plan;
  String? step;
  // While EffectCraft renders: {'done', 'total', 'left'} for a progress bar.
  Json? progress;
  final DateTime started;
}

/// Tells a person a long job has ended when they're in another app. Only news is said, and
/// only when they can't see the window, because the status bar says it otherwise.
class Notify {
  static const _channel = MethodChannel('aie/notify');
  static const after = Duration(seconds: 30);

  static Future<void> show(String title, String body) async {
    try {
      await _channel.invokeMethod('show', {'title': title, 'body': body});
    } catch (_) {
      // A notification is a courtesy. Without one, the status bar still says it.
    }
  }

  static bool get away => WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed;
}

/// The open project, as the pages see it. The engine stays the source of truth:
/// every page reads from here, and every action goes through [run].
class ProjectModel extends ChangeNotifier {
  ProjectModel(this.api, {this.pollEvery = const Duration(milliseconds: 600)});

  final Api api;
  final Duration pollEvery;

  Json? state;
  Json? plan;
  RunningJob? job;
  String? problem;
  bool _disposed = false;

  /// This Mac's settings, which need no project.
  Json? settings;

  /// This project's conversation and memory. Loaded fresh, so another project's never lingers.
  Json? chat;

  /// The question being answered, and what's come back so far.
  String? asking;
  String reply = '';

  /// A frame for Review to go to next, set when a reply points at a moment in the cut.
  int? seekTo;

  /// Opens an EffectCraft project. Stood in for in tests.
  Future<void> Function(String path) openProject = openInEffectCraft;

  /// A piece of good news for the status bar. The next job clears it.
  String? notice;

  bool get isOpen => state != null;
  bool get busy => job != null;
  Json? get report => state?['report'] as Json?;
  Json? get footage => state?['footage'] as Json?;
  Json? get style => state?['style'] as Json?;
  Json? get music => state?['music'] as Json?;
  List<String> get pictures => ((state?['pictures'] as List?) ?? const []).cast<String>();
  List<Json> get photos => ((state?['photos'] as List?) ?? const []).cast<Json>();
  Json? get activity => state?['activity'] as Json?;
  String? get planId => plan?['id'] as String?;
  List<Json> get plans =>
      ((report?['plans'] as List?) ?? const []).cast<Json>();

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void dismissProblem() {
    problem = null;
    _changed();
  }

  void _show(Object error) {
    problem = '$error';
    _changed();
  }

  /// For a page that caught something before it reached the engine.
  void complain(String text) => _show(text);

  void say(String text) {
    notice = text;
    _changed();
  }

  void notifyAfterChange() => _changed();

  /// Returns whether the project opened, because a failure leaves the last one open.
  Future<bool> _took(Future<Json> Function() opening) async {
    var succeeded = false;
    try {
      final opened = await opening();
      state = opened;
      plan = null;
      chat = null;
      problem = null;
      await _loadPlan(opened['latest_plan'] as String?);
      chat = await api.chat();
      succeeded = true;
    } catch (error) {
      _show(error);
    }
    _changed();
    return succeeded;
  }

  Future<bool> create(String name, {String? location, String? footage}) =>
      _took(() => api.createProject(name, location: location, footage: footage));

  Future<bool> open(String path) => _took(() => api.openProject(path));

  /// Says what's in a folder someone picked, or shows why it can't be read.
  Future<Json?> inspect(String path) async {
    try {
      return await api.inspectFolder(path);
    } catch (error) {
      _show(error);
      return null;
    }
  }

  Future<void> close() async {
    try {
      await api.closeProject();
      state = null;
      plan = null;
      chat = null;
      problem = null;
    } catch (error) {
      _show(error);
    }
    _changed();
  }

  Future<void> _loadPlan(String? id) async {
    plan = id == null ? null : await api.plan(id);
  }

  /// Reads the project again. With no choice made it stays on the same plan.
  Future<void> refresh({String? showPlan}) async {
    try {
      state = await api.state();
      final known = plans.map((item) => item['id']).toSet();
      final current = known.contains(planId) ? planId : null;
      await _loadPlan(showPlan ?? current ?? state?['latest_plan'] as String?);
    } catch (error) {
      _show(error);
    }
    _changed();
  }

  Future<void> selectPlan(String id) async {
    try {
      await _loadPlan(id);
    } catch (error) {
      _show(error);
    }
    _changed();
  }

  /// Starts a job and follows it. The page gets back how it ended, or null if
  /// it couldn't start. A failure is shown here, so pages needn't say it again.
  Future<Json?> run(
    String action,
    Json body,
    String label, {
    bool cancellable = false,
    bool quiet = false,
    Duration? poll,
    void Function(Json latest)? onUpdate,
  }) async {
    if (busy) return null;
    final following = RunningJob(
      label,
      plan: cancellable ? body['plan'] as String? : null,
    );
    job = following;
    problem = null;
    notice = null;
    _changed();
    Json? outcome;
    try {
      final id = await api.start(action, body);
      while (true) {
        final latest = await api.job(id);
        if (latest['state'] != 'running') {
          outcome = latest;
          break;
        }
        following.step = latest['step'] as String?;
        following.progress = latest['progress'] as Json?;
        onUpdate?.call(latest);
        _changed();
        await Future<void>.delayed(poll ?? pollEvery);
        if (_disposed) return null;
      }
      if (outcome['state'] == 'failed' && outcome['needs'] == null) {
        problem = outcome['error'] as String?;
      }
    } catch (error) {
      problem = '$error';
    }
    job = null;
    if (outcome != null && DateTime.now().difference(following.started) >= Notify.after && Notify.away) {
      final done = outcome['state'] == 'done';
      unawaited(Notify.show(done ? '$label: done' : '$label: stopped', done ? 'Open AI Editor to see it.' : (outcome['error'] as String? ?? 'Open AI Editor to see why.')));
    }
    if (quiet) {
      _changed();
    } else {
      await refresh();
    }
    return outcome;
  }

  /// Makes a plan or revision, then shows the one it made.
  Future<void> runAndShowNewest(String action, Json body, String label) async {
    final before = plans.length;
    final outcome = await run(action, body, label);
    if (outcome?['state'] != 'done') return;
    final newest = state?['latest_plan'] as String?;
    if (plans.length > before && newest != null) await selectPlan(newest);
  }

  /// Stops a run between steps, so nothing is left half done.
  Future<void> cancel() async {
    final id = job?.plan;
    if (id == null) return;
    try {
      await api.cancel(id);
      job?.step = 'Stopping after this step';
    } catch (error) {
      _show(error);
    }
    _changed();
  }

  /// Gives up on a run that has stopped and is waiting for a person.
  Future<void> cancelPlan(String id) async {
    try {
      await api.cancel(id);
    } catch (error) {
      _show(error);
    }
    await refresh();
  }
}

/// Everything to do with this project's assistant and this Mac's settings.
extension Assistant on ProjectModel {
  Future<void> loadSettings() async {
    try {
      settings = await api.settings();
    } catch (error) {
      complain('$error');
    }
    notifyAfterChange();
  }

  /// Adds or removes a skill or MCP server on this Mac, then shows the new list.
  Future<void> changeExtensions(Json body) async {
    try {
      final extensions = await api.changeExtensions(body);
      settings = {...?settings, 'extensions': extensions};
      if (isOpen) await _showChanges();
    } catch (error) {
      complain('$error');
    }
    notifyAfterChange();
  }

  /// Learns a style from a person's videos. Measuring takes a while, so the status bar says so.
  Future<void> learnStyle(String name, List<String> paths) async {
    if (busy) return;
    job = RunningJob('Learning your style');
    problem = null;
    _changed();
    await changeExtensions({'op': 'learn_style', 'name': name, 'paths': paths});
    job = null;
    notice = problem == null ? 'Learned $name' : null;
    _changed();
  }

  /// Allows or refuses the tool the Assistant asked to use. Only this runs one.
  Future<void> resolveTool(bool allow) async {
    asking = allow ? 'Allowed the tool' : 'Didn\'t allow the tool';
    reply = '';
    await run('resolve_tool', {'allow': allow}, allow ? 'Running the tool' : 'Telling the Assistant', quiet: true, poll: const Duration(milliseconds: 150));
    await _showChanges();
    asking = null;
    notifyAfterChange();
  }

  Future<void> setDefaultModel(String name) async {
    try {
      settings = await api.setDefaultModel(name);
      if (isOpen) chat = await api.chat();
    } catch (error) {
      complain('$error');
    }
    notifyAfterChange();
  }

  Future<void> loadChat() async {
    try {
      chat = await api.chat();
    } catch (error) {
      complain('$error');
    }
    notifyAfterChange();
  }

  /// Asks this project's AI. Words appear as they arrive, because a reply can take a while.
  Future<void> ask(String text) async {
    asking = text;
    reply = '';
    final outcome = await run(
      'ask',
      {'text': text, 'plan': planId},
      'Asking this project\'s AI',
      quiet: true,
      poll: const Duration(milliseconds: 150),
      onUpdate: (latest) => reply = latest['partial'] as String? ?? '',
    );
    await _showChanges();
    final made = (outcome?['result'] as Json?)?['plan'] as String?;
    if (made != null) await selectPlan(made);
    final project = (outcome?['result'] as Json?)?['open'] as String?;
    if (project != null) await openProject(project);
    asking = null;
    reply = '';
    notifyAfterChange();
  }

  /// Draws the waiting draft as one still per scene. Nothing is made, and the stills show on the draft.
  Future<void> drawStoryboard() async {
    await run('storyboard', {}, 'Drawing the storyboard', quiet: true);
    await loadChat();
  }

  /// Rebuilds the current cut with what a person said they want.
  Future<void> applyBrief() async {
    final outcome = await run('apply_brief', {'plan': planId}, 'Applying your answers to the cut', quiet: true);
    await _showChanges();
    final made = (outcome?['result'] as Json?)?['plan'] as String?;
    if (made != null) await selectPlan(made);
  }

  /// The conversation, and the log and usage that record it.
  Future<void> _showChanges() async {
    await loadChat();
    await refresh();
  }

  /// Puts a clip in the cut or takes one out, which makes a new revision.
  Future<void> changeCut(String action, String clip) async {
    final outcome = await run(action, {'clip': clip, 'plan': planId}, action == 'add_to_cut' ? 'Adding the clip to the cut' : 'Taking the clip out of the cut');
    final made = (outcome?['result'] as Json?)?['plan'] as String?;
    if (made != null) await selectPlan(made);
  }

  Future<void> stopReply() async {
    try {
      await api.stopReply();
    } catch (error) {
      complain('$error');
    }
  }

  /// Changes something about the assistant, then shows what's true now.
  Future<void> changeAssistant(String action, Json body, String label) async {
    await run(action, body, label, quiet: true);
    await _showChanges();
  }
}

/// Shows a file in Finder. Only paths the engine gave us come here.
Future<void> reveal(String path) => Process.run('open', ['-R', path]);

/// Opens a project in EffectCraft. Only paths the engine gave us come here.
Future<void> openInEffectCraft(String path) => Process.run('open', ['-a', 'EffectCraft', path]);

/// Opens a web address in the default browser.
Future<void> openInBrowser(String url) => Process.run('open', [url]);
