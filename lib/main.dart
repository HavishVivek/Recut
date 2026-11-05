import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'engine.dart';
import 'motion.dart';
import 'pages/activity.dart';
import 'pages/assistant.dart';
import 'pages/setup.dart';
import 'pages/footage.dart';
import 'pages/projects.dart';
import 'pages/resolve.dart';
import 'pages/review.dart';
import 'pages/settings.dart';
import 'pages/style.dart';
import 'project.dart';
import 'theme.dart';
import 'ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Geist', 'Geist Mono'], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  runApp(const AieApp());
}

class AieApp extends StatelessWidget {
  const AieApp({super.key, this.enablePreview = true, this.api});

  /// Widget tests turn this off, because the native player isn't available.
  final bool enablePreview;

  /// Tests pass a stand-in. Otherwise the real engine starts.
  final Api? api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Editor',
      debugShowCheckedModeBanner: false,
      theme: graphiteTheme(),
      // Reduce Motion reaches every widget as disableAnimations, which Flutter's own widgets read too.
      builder: (context, child) => ValueListenableBuilder<bool>(
        valueListenable: ReduceMotion.instance,
        builder: (context, reduce, _) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(disableAnimations: media.disableAnimations || reduce),
            child: child!,
          );
        },
      ),
      home: Shell(enablePreview: enablePreview, api: api),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key, required this.enablePreview, this.api});

  final bool enablePreview;
  final Api? api;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  static const _sections = [
    ('Projects', PhosphorIconsRegular.folders, PhosphorIconsFill.folders),
    ('Footage', PhosphorIconsRegular.filmStrip, PhosphorIconsFill.filmStrip),
    ('Style', PhosphorIconsRegular.palette, PhosphorIconsFill.palette),
    ('Review', PhosphorIconsRegular.playCircle, PhosphorIconsFill.playCircle),
    ('Resolve', PhosphorIconsRegular.stack, PhosphorIconsFill.stack),
    ('Assistant', PhosphorIconsRegular.sparkle, PhosphorIconsFill.sparkle),
    ('Activity', PhosphorIconsRegular.clockCounterClockwise, PhosphorIconsFill.clockCounterClockwise),
    ('Setup', PhosphorIconsRegular.plugsConnected, PhosphorIconsFill.plugsConnected),
    ('Settings', PhosphorIconsRegular.gearSix, PhosphorIconsFill.gearSix),
  ];
  static const _footage = 1;
  static const _review = 3;
  static const _resolve = 4;
  static const _assistant = 5;
  static const _setup = 7;
  static const _settings = 8;

  int _index = 0;
  Engine? _engine;
  ProjectModel? _model;
  String? _engineError;

  @override
  void initState() {
    super.initState();
    if (widget.api != null) {
      _model = ProjectModel(widget.api!, pollEvery: Duration.zero);
      _openSetupIfNeeded(widget.api!);
    } else if (widget.enablePreview) {
      _connect();
    }
  }

  Future<void> _connect() async {
    try {
      final engine = await Engine.launch();
      if (mounted) {
        setState(() {
          _engine = engine;
          _model = ProjectModel(engine);
        });
        await _openSetupIfNeeded(engine);
      }
    } catch (error) {
      if (mounted) setState(() => _engineError = '$error');
    }
  }

  @override
  void dispose() {
    _engine?.stop();
    _model?.dispose();
    super.dispose();
  }

  // How many times each page has opened, and when it last did, so its sections arrive in line.
  final List<int> _arrivals = List.filled(_sections.length, 0)..[0] = 1;
  final List<DateTime> _openedAt = List.filled(_sections.length, DateTime.now());

  void _go(int index) => setState(() {
    if (index != _index) {
      _arrivals[index]++;
      _openedAt[index] = DateTime.now();
    }
    _index = index;
  });

  /// On a Mac still missing something the editor needs, start on Setup rather than an empty project list.
  Future<void> _openSetupIfNeeded(Api api) async {
    try {
      final view = await api.setup();
      if (mounted && view['ready'] != true) _go(_setup);
    } catch (_) {
      // Setup says why on its own page. A first look failing isn't a reason to stop the app opening.
    }
  }

  /// The side bar can fold to its icons, for more room to work.
  bool _collapsed = false;

  /// A Settings section to show, chosen from the menu on the side bar.
  final _settingsSection = ValueNotifier<String?>(null);

  void _openSettings(String section) {
    _go(_settings);
    _settingsSection.value = null;
    _settingsSection.value = section;
  }

  // Pages stay alive, so switching away keeps the video and notes. The new page settles up
  // into place as the old one fades, unless motion is reduced, when it only fades.
  Widget _page(int index, Widget child) {
    final active = index == _index;
    final reduced = Motion.reduced(context);
    return IgnorePointer(
      ignoring: !active,
      child: PageEntrance(
        arrival: _arrivals[index],
        openedAt: _openedAt[index],
        child: AnimatedSlide(
        offset: active || reduced ? Offset.zero : const Offset(0, .012),
        duration: Motion.settle,
        curve: Motion.curve,
        // The page leaving goes quickly, before the new one's sections start, so the two never overlap.
        child: AnimatedOpacity(opacity: active ? 1 : 0, duration: active ? Motion.settle : EnterOnPage.lead, curve: Motion.curve, child: child),
      ),
      ),
    );
  }

  List<Widget> _pages(ProjectModel model) => [
    _page(0, ProjectsPage(model: model, visible: _index == 0, onOpened: (withFootage) => _go(withFootage ? _footage : _assistant))),
    _page(1, FootagePage(model: model, enablePreview: widget.enablePreview)),
    _page(2, StylePage(model: model)),
    _page(3, ReviewPage(model: model, enablePreview: widget.enablePreview, onShowResolve: () => _go(_resolve))),
    _page(4, ResolvePage(model: model, visible: _index == _resolve)),
    _page(5, AssistantPage(model: model, onShowSettings: () => _go(_settings), onShowReview: () => _go(_review))),
    _page(
      6,
      ActivityPage(
        model: model,
        onShowPlan: (id) async {
          await model.selectPlan(id);
          _go(_review);
        },
      ),
    ),
    _page(7, SetupPage(api: model.api)),
    _page(8, SettingsPage(model: model, visible: _index == _settings, section: _settingsSection)),
  ];

  @override
  Widget build(BuildContext context) {
    final model = _model;
    return Scaffold(
      body: model == null
          ? _layout(context, null, _EngineNotice(error: _engineError), const SizedBox.shrink())
          : AnimatedBuilder(
              animation: model,
              builder: (context, _) => _layout(context, model, _StatusBar(model: model), Stack(fit: StackFit.expand, children: _pages(model))),
            ),
    );
  }

  Widget _layout(BuildContext context, ProjectModel? model, Widget status, Widget pages) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          width: _collapsed ? 60 : 200,
          child: _sidebar(context, model),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                status,
                const SizedBox(height: 12),
                Expanded(child: pages),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sidebar(BuildContext context, ProjectModel? model) {
    final stem = model?.report?['stem'] as String?;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        color: Graphite.surface,
        border: Border(right: BorderSide(color: Graphite.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 16),
            child: _collapsed
                ? const SizedBox(height: 20)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('AI Editor', style: Theme.of(context).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.clip),
                      if (stem != null) ...[const SizedBox(height: 2), Text(stem, style: mono, maxLines: 1, overflow: TextOverflow.ellipsis)],
                    ],
                  ),
          ),
          // One background for the page that's open. It slides to a new page rather than jumping,
          // so the eye follows where it went.
          Stack(
            children: [
              AnimatedPositioned(
                duration: Motion.reduced(context) ? Duration.zero : Motion.settle,
                curve: Motion.curve,
                top: _index * _NavItem.stride,
                left: 0,
                right: 0,
                height: _NavItem.height,
                child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(smallCorner), color: Graphite.raised)),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, section) in _sections.indexed)
                    if (i == _settings)
                      _SettingsNavItem(
                        item: _NavItem(
                          label: section.$1,
                          icon: i == _index ? section.$3 : section.$2,
                          selected: i == _index,
                          collapsed: _collapsed,
                          onTap: () => _go(i),
                        ),
                        sections: [
                          ('models', 'AI model'),
                          ('huggingface', 'Hugging Face'),
                          if (model?.isOpen == true) ('project', 'This project'),
                          ('styles', 'Styles'),
                          ('skills', 'Skills'),
                          ('servers', 'MCP servers'),
                          ('license', 'License'),
                          ('account', 'Account'),
                          ('ollama', 'Ollama'),
                          ('about', 'About'),
                        ],
                        onPick: _openSettings,
                      )
                    else
                      _NavItem(label: section.$1, icon: i == _index ? section.$3 : section.$2, selected: i == _index, collapsed: _collapsed, onTap: () => _go(i)),
                ],
              ),
            ],
          ),
          const Spacer(),
          _NavItem(
            label: 'Collapse',
            icon: _collapsed ? PhosphorIconsRegular.caretDoubleRight : PhosphorIconsRegular.caretDoubleLeft,
            selected: false,
            collapsed: _collapsed,
            tooltip: _collapsed ? 'Expand the side bar' : 'Collapse the side bar',
            onTap: () => setState(() => _collapsed = !_collapsed),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({required this.label, required this.icon, required this.selected, required this.onTap, this.collapsed = false, this.tooltip});

  final String label;
  final PhosphorIconData icon;
  final bool selected;
  final VoidCallback onTap;

  /// Folded to its icon, with the name in a tooltip.
  final bool collapsed;
  final String? tooltip;

  static const _labelRoom = 120.0;
  static const height = 32.0;
  static const stride = height + 2;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _over = false;

  String get label => widget.label;
  PhosphorIconData get icon => widget.icon;
  bool get selected => widget.selected;
  VoidCallback get onTap => widget.onTap;
  String? get tooltip => widget.tooltip;

  @override
  Widget build(BuildContext context) {
    // While the bar opens, a label waits until there's room for it.
    return LayoutBuilder(builder: (context, room) => _build(widget.collapsed || room.maxWidth < _NavItem._labelRoom));
  }

  Widget _build(bool collapsed) {
    final item = Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _over = true),
          onExit: (_) => setState(() => _over = false),
          child: AnimatedContainer(
            duration: Motion.quick,
            curve: Motion.curve,
            height: _NavItem.height,
            margin: const EdgeInsets.only(bottom: _NavItem.stride - _NavItem.height),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            // The open page's background is drawn once behind the list, so it can slide. Hover only lights the others.
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(smallCorner), color: _over && !selected ? Graphite.hover : Colors.transparent),
            child: Row(
              mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                AnimatedScale(
                  scale: _over && !selected && !Motion.reduced(context) ? 1.08 : 1,
                  duration: Motion.quick,
                  curve: Motion.curve,
                  child: PhosphorIcon(icon, size: 17, color: selected ? Graphite.mint : _over ? Graphite.text : Graphite.muted),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: selected || _over ? Graphite.text : Graphite.muted),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    final hint = tooltip ?? (collapsed ? label : null);
    return hint == null ? item : Tooltip(message: hint, waitDuration: const Duration(milliseconds: 400), child: item);
  }
}

/// Settings, with a menu of its sections that opens while the pointer rests on it.
class _SettingsNavItem extends StatefulWidget {
  const _SettingsNavItem({required this.item, required this.sections, required this.onPick});

  final _NavItem item;
  final List<(String, String)> sections;
  final void Function(String section) onPick;

  @override
  State<_SettingsNavItem> createState() => _SettingsNavItemState();
}

class _SettingsNavItemState extends State<_SettingsNavItem> {
  final _menu = MenuController();
  Timer? _closing;
  bool _overItem = false;
  bool _overMenu = false;

  @override
  void dispose() {
    _closing?.cancel();
    super.dispose();
  }

  // Moving from the item to the menu crosses a gap, so closing waits a moment.
  void _settle() {
    _closing?.cancel();
    if (_overItem || _overMenu) {
      if (!_menu.isOpen) _menu.open();
      return;
    }
    _closing = Timer(const Duration(milliseconds: 250), () {
      if (!_overItem && !_overMenu && _menu.isOpen) _menu.close();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(0, -34),
      style: const MenuStyle(alignment: AlignmentDirectional.topEnd),
      menuChildren: [
        for (final (id, label) in widget.sections)
          MenuItemButton(
            onHover: (inside) {
              _overMenu = inside;
              _settle();
            },
            onPressed: () {
              _overMenu = false;
              widget.onPick(id);
            },
            child: Text(label, style: small),
          ),
      ],
      child: MouseRegion(
        onEnter: (_) {
          _overItem = true;
          _settle();
        },
        onExit: (_) {
          _overItem = false;
          _settle();
        },
        child: widget.item,
      ),
    );
  }
}

class _EngineNotice extends StatelessWidget {
  const _EngineNotice({required this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    final text = error != null ? "The engine didn't start: $error" : 'Starting the engine.';
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(text, style: tiny),
    );
  }
}

/// Says what's happening right now, on every page, and offers the way out of it.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.model});

  final ProjectModel model;

  /// Each state has its own key, so changing between them cross-fades.
  Widget _content(RunningJob? job, String? problem) {
    if (job != null) {
      final step = job.step == null || job.step!.isEmpty ? job.label : job.step!;
      return Row(
        key: const ValueKey('job'),
        children: [
          const SizedBox.square(dimension: 13, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          // The step cross-fades as it changes. The seconds count on their own, so they don't.
          Flexible(
            child: Swap(
              child: Text(step, key: ValueKey(step), style: tiny, overflow: TextOverflow.ellipsis),
            ),
          ),
          Text(', ${DateTime.now().difference(job.started).inSeconds} s', style: tiny),
          const Spacer(),
          if (job.plan != null) TextButton(onPressed: model.cancel, child: const Text('Cancel')),
        ],
      );
    }
    if (problem != null) {
      return Row(
        key: ValueKey('problem:$problem'),
        children: [
          Expanded(
            child: SelectableText(problem, style: const TextStyle(fontSize: 12, color: bad), maxLines: 2),
          ),
          IconButton(iconSize: 15, tooltip: 'Dismiss', onPressed: model.dismissProblem, icon: const PhosphorIcon(PhosphorIconsRegular.x, size: 14)),
        ],
      );
    }
    if (model.notice != null) {
      return Row(
        key: ValueKey('notice:${model.notice}'),
        children: [
          const SizedBox.square(dimension: 14, child: DrawnCheck(size: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(model.notice!, style: small, overflow: TextOverflow.ellipsis),
          ),
        ],
      );
    }
    return Row(
      key: const ValueKey('ready'),
      children: [
        Expanded(child: Text(model.isOpen ? 'Ready. Nothing reaches Resolve until you approve it.' : 'Ready. Open or make a project to start.', style: tiny)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final job = model.job;
    final problem = model.problem;
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: SizedBox(height: 30, child: Swap(child: _content(job, problem))),
    );
  }
}
