import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../engine.dart';
import '../motion.dart';
import '../project.dart';
import '../theme.dart';
import '../ui.dart';
import 'exchange.dart';
import 'extensions.dart';
import 'style_questions.dart';

const _sameAsDefault = 'default';
const _maxMemory = 400;
const _ideas = ['Edit this for me', 'Add text on the left that says Hello', 'Summarise this video'];

/// Chooses which model this project's AI uses. Shown here and in Settings.
class ModelPicker extends StatelessWidget {
  const ModelPicker({super.key, required this.model});

  final ProjectModel model;

  @override
  Widget build(BuildContext context) {
    final chat = model.chat;
    final installed = ((model.settings?['models'] as List?) ?? const []).cast<Json>().map((item) => item['name'] as String).toList();
    if (chat == null) return const SizedBox.shrink();
    final choice = chat['choice'] as String?;
    final names = [...installed, if (choice != null && !installed.contains(choice)) choice];
    return DropdownButton<String>(
      value: choice ?? _sameAsDefault,
      isExpanded: true,
      underline: const SizedBox.shrink(),
      icon: const PhosphorIcon(PhosphorIconsRegular.caretDown, size: 14),
      items: [
        DropdownMenuItem(
          value: _sameAsDefault,
          child: Text('Same as default (${chat['default']})', style: small, overflow: TextOverflow.ellipsis),
        ),
        for (final name in names)
          DropdownMenuItem(
            value: name,
            child: Text(installed.contains(name) ? name : '$name (not installed)', style: small, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: model.busy
          ? null
          : (value) => model.changeAssistant('choose_model', {'model': value == _sameAsDefault ? null : value}, 'Changing this project\'s model'),
    );
  }
}

class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key, required this.model, required this.onShowSettings, required this.onShowReview});

  final ProjectModel model;
  final VoidCallback onShowSettings;
  final VoidCallback onShowReview;

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final _question = TextEditingController();
  final _fact = TextEditingController();
  final _list = ScrollController();
  int _shown = 0;

  /// Messages already on screen, for this project. Only ones that arrive later move in.
  Set<Object?>? _known;
  Object? _knownFor;

  /// Set while a reply streams in. Its saved copy then replaces words already on screen, so it doesn't move again.
  bool _replyShown = false;

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_follow);
    if (widget.model.settings == null) WidgetsBinding.instance.addPostFrameCallback((_) => widget.model.loadSettings());
  }

  @override
  void dispose() {
    widget.model.removeListener(_follow);
    _question.dispose();
    _fact.dispose();
    _list.dispose();
    super.dispose();
  }

  /// Stays at the newest words as they arrive.
  void _follow() {
    final model = widget.model;
    final length = ((model.chat?['messages'] as List?)?.length ?? 0) + model.reply.length + (model.asking == null ? 0 : 1);
    if (length == _shown) return;
    _shown = length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_list.hasClients) _list.jumpTo(_list.position.maxScrollExtent);
    });
  }

  void _send([String? idea]) {
    final text = (idea ?? _question.text).trim();
    if (text.isEmpty || widget.model.busy) return;
    _question.clear();
    widget.model.ask(text);
  }

  void _remember(String text) {
    final clipped = text.length > _maxMemory ? '${text.substring(0, _maxMemory - 1)}…' : text;
    widget.model.changeAssistant('remember', {'text': clipped}, 'Remembering that');
  }

  void _addFact() {
    final text = _fact.text.trim();
    if (text.isEmpty) return;
    _fact.clear();
    _remember(text);
  }

  Future<void> _clear() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear this conversation?'),
        content: const Text('Its memory stays. This can\'t be undone.', style: small),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (yes == true) await widget.model.changeAssistant('clear_chat', {}, 'Clearing the conversation');
  }

  Widget _welcome() {
    final model = widget.model;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PhosphorIcon(PhosphorIconsDuotone.sparkle, size: 36, color: Graphite.mint),
          const SizedBox(height: 12),
          const Text('Ask about this project, or tell it what to change', style: quiet),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final idea in _ideas)
                ActionChip(
                  label: Text(idea, style: small),
                  onPressed: model.busy ? null : () => _send(idea),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _conversation() {
    final model = widget.model;
    final messages = ((model.chat?['messages'] as List?) ?? const []).cast<Json>();
    final asking = model.asking;
    final replies = ((model.chat?['replies'] as List?) ?? const []).cast<Json>();
    if (messages.isEmpty && asking == null) return _welcome();
    final saved = messages.where((item) => asking == null || item['text'] != asking || item != messages.last);
    final root = model.report?['root'];
    if (_known == null || _knownFor != root) {
      _knownFor = root;
      _known = {for (final item in messages) item['id']};
    }
    if (model.reply.isNotEmpty) _replyShown = true;
    final known = _known!;
    final replyShown = _replyShown;
    if (asking == null) _replyShown = false;
    return ListView(
      controller: _list,
      children: [
        for (final item in saved)
          Arrive(
            key: ValueKey(('message', item['id'])),
            // Your own words were already shown while it answered, so only the AI's news moves.
            play: known.add(item['id']) && item['role'] != 'user' && !replyShown,
            child: _Bubble(
              text: item['text'] as String,
              mine: item['role'] == 'user',
              byline: item['model'] as String?,
              onRemember: model.busy ? null : () => _remember(item['text'] as String),
              onSee: item['plan_id'] == null
                  ? null
                  : () async {
                      await model.selectPlan(item['plan_id'] as String);
                      model.seekTo = (item['video'] as Json?)?['start'] as int?;
                      widget.onShowReview();
                    },
              onOpen: item['video'] == null ? null : () => model.openProject((item['video'] as Json)['project'] as String),
              onAllow: item['waiting_tool'] == true && !model.busy ? (allow) => model.resolveTool(allow) : null,
            ),
          ),
        if (asking != null) ...[
          Arrive(
            key: ValueKey(('asking', asking)),
            child: _Bubble(text: asking, mine: true),
          ),
          // The typing dots give way to the reply as its first words arrive.
          Swap(
            child: model.reply.isNotEmpty
                ? _Bubble(key: const ValueKey('ai-reply'), text: model.reply, mine: false)
                : _Typing(key: const ValueKey('ai-typing'), status: model.job?.step),
          ),
        ],
        // A reply the AI is waiting on, such as making a draft, is one press. Each sends words you could type.
        if (asking == null && replies.isNotEmpty)
          Arrive(
            key: ValueKey(('replies', replies.map((item) => item['text']).join('|'), messages.length)),
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in replies)
                    ActionChip(
                      label: Text(item['label'] as String, style: small),
                      onPressed: model.busy ? null : () => _send(item['text'] as String),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _inputBar() {
    final model = widget.model;
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: CallbackShortcuts(
              bindings: {const SingleActivator(LogicalKeyboardKey.enter): _send},
              child: TextField(
                controller: _question,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                decoration: const InputDecoration(counterText: '', hintText: 'Ask a question, or say what to change'),
              ),
            ),
          ),
          if (model.asking != null)
            IconButton(tooltip: 'Stop', onPressed: model.stopReply, icon: const PhosphorIcon(PhosphorIconsRegular.stopCircle, size: 20))
          else
            IconButton(tooltip: 'Send', onPressed: model.busy ? null : _send, icon: const PhosphorIcon(PhosphorIconsFill.paperPlaneRight, size: 18)),
        ],
      ),
    );
  }

  Widget _modelPanel() {
    final model = widget.model;
    final chat = model.chat;
    return Section(
      'This project\'s AI',
      children: [
        ModelPicker(model: model),
        if (chat != null) Text('Answering with ${chat['model']}', style: tiny),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: widget.onShowSettings, child: const Text('Models and default')),
        ),
      ],
    );
  }

  Widget _memoryPanel() {
    final model = widget.model;
    final memory = ((model.chat?['memory'] as List?) ?? const []).cast<Json>();
    return Section(
      'Memory',
      children: [
        const Text('Only this project\'s AI reads these, and only you can add them.', style: tiny),
        const SizedBox(height: 8),
        for (final item in memory)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(item['text'] as String, style: small),
                ),
              ),
              IconButton(
                iconSize: 15,
                visualDensity: VisualDensity.compact,
                tooltip: 'Forget this',
                onPressed: model.busy ? null : () => model.changeAssistant('forget', {'id': item['id']}, 'Forgetting that'),
                icon: const PhosphorIcon(PhosphorIconsRegular.x, size: 14),
              ),
            ],
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _fact,
                style: small,
                maxLength: _maxMemory,
                onSubmitted: (_) => _addFact(),
                decoration: const InputDecoration(isDense: true, counterText: '', hintText: 'Something to remember'),
              ),
            ),
            IconButton(
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              tooltip: 'Remember',
              onPressed: model.busy ? null : _addFact,
              icon: const PhosphorIcon(PhosphorIconsRegular.plus, size: 16),
            ),
          ],
        ),
      ],
    );
  }

  Widget _limits() {
    final model = widget.model;
    final hasMessages = ((model.chat?['messages'] as List?) ?? const []).isNotEmpty;
    return Section(
      'What it can do',
      children: [
        const Text(
          'Ask it to add text, cut or restore lines, change the title or turn captions on or off. Each change is a new revision, so nothing is lost, and nothing reaches Resolve until you approve it. It knows nothing about your other projects and never sees file paths.',
          style: tiny,
        ),
        if (hasMessages) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: model.busy ? null : _clear, child: const Text('Clear conversation')),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    if (!model.isOpen) return const Empty('Open a project first');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: Panel(child: _conversation())),
              const SizedBox(height: 10),
              StyleQuestionCard(model: model),
              _inputBar(),
            ],
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 300,
          child: ListView(
            children: [
              _modelPanel(),
              EditBriefPanel(model: model),
              ProjectExtensions(model: model),
              PartPhotos(model),
              _memoryPanel(),
              _limits(),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({super.key, required this.text, required this.mine, this.byline, this.onRemember, this.onSee, this.onOpen, this.onAllow});

  final String text;
  final bool mine;
  final String? byline;
  final VoidCallback? onRemember;

  /// Set when this reply made a revision.
  final VoidCallback? onSee;

  /// Set when this reply made a video that has an EffectCraft project.
  final VoidCallback? onOpen;

  /// Set while this reply's tool waits for a person. Nothing runs until they choose.
  final void Function(bool allow)? onAllow;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(corner),
            color: mine ? Graphite.raised : Graphite.canvas,
            border: Border.all(color: Graphite.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(text, style: const TextStyle(fontSize: 13, height: 1.5)),
              if (byline != null || onRemember != null || onAllow != null)
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (byline != null) Text(byline!, style: tiny),
                    if (onRemember != null)
                      IconButton(
                        iconSize: 14,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Remember this',
                        onPressed: onRemember,
                        icon: const PhosphorIcon(PhosphorIconsRegular.bookmarkSimple, size: 14),
                      ),
                    if (onSee != null) TextButton(onPressed: onSee, child: const Text('See it on Review')),
                    if (onOpen != null) TextButton(onPressed: onOpen, child: const Text('Open in EffectCraft')),
                    if (onAllow != null) ...[
                      FilledButton(onPressed: () => onAllow!(true), child: const Text('Allow')),
                      const SizedBox(width: 6),
                      TextButton(onPressed: () => onAllow!(false), child: const Text('Don\'t run it')),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three dots rising in turn in a tailed bubble, the way iMessage shows someone typing.
class _Typing extends StatefulWidget {
  const _Typing({super.key, this.status});

  /// What the engine is doing, once it's doing more than thinking.
  final String? status;

  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  static const _dot = 8.0;
  static const _height = 36.0;

  late final AnimationController _beat = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  /// How high one dot is right now, from 0 to 1. Each dot starts a little after the last.
  double _lift(int index) {
    final phase = (_beat.value - index * 0.16) % 1;
    return phase < 0.5 ? math.sin(phase * 2 * math.pi) : 0;
  }

  Widget _dots() {
    return AnimatedBuilder(
      animation: _beat,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < 3; index++)
            Transform.translate(
              offset: Offset(0, -3 * _lift(index)),
              child: Container(
                width: _dot,
                height: _dot,
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                decoration: BoxDecoration(shape: BoxShape.circle, color: Color.lerp(Graphite.faint, Graphite.text, _lift(index))),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tail(double size, double left, double bottom) {
    return Positioned(
      left: left,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Graphite.raised),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              label: 'The AI is thinking',
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _tail(12, -2, -1),
                  _tail(6, -7, -5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: (_height - _dot) / 2),
                    decoration: BoxDecoration(color: Graphite.raised, borderRadius: BorderRadius.circular(_height / 2)),
                    child: _dots(),
                  ),
                ],
              ),
            ),
            if (status != null && status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 6),
                child: Text(status, style: tiny),
              ),
          ],
        ),
      ),
    );
  }
}
