import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../engine.dart';
import '../motion.dart';
import '../project.dart';
import '../theme.dart';
import '../ui.dart';
import 'approve.dart';
import 'exchange.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, required this.model, required this.enablePreview, required this.onShowResolve});

  final ProjectModel model;
  final bool enablePreview;
  final VoidCallback onShowResolve;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late final Screen _screen = Screen(widget.enablePreview);
  final _note = TextEditingController();
  final _instruction = TextEditingController();
  final _panel = ScrollController();
  String? _showing;
  // The last export of each revision, from this visit.
  final Map<String, Json> _exports = {};

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    widget.model.removeListener(_sync);
    _screen.dispose();
    _note.dispose();
    _instruction.dispose();
    _panel.dispose();
    super.dispose();
  }

  void _sync() {
    final model = widget.model;
    final frame = model.plan == null ? null : model.seekTo;
    model.seekTo = model.plan == null ? model.seekTo : null;
    _screen.show(model.plan?['preview_path'] as String?, at: frame == null ? null : Duration(milliseconds: (frame * 1000 / _fps).round()));
    if (model.planId != _showing) {
      _showing = model.planId;
      // A new revision starts at its summary, wherever the last one was scrolled to.
      if (_panel.hasClients) _panel.jumpTo(0);
    }
  }

  Json get _plan => widget.model.plan!;
  num get _fps => _plan['fps'] as num;
  String get _id => _plan['id'] as String;

  void _seekTo(int? rec) {
    if (rec != null) _screen.seek(Duration(milliseconds: (rec * 1000 / _fps).round()));
  }

  int get _rec {
    final frame = (_screen.position.value.inMilliseconds * _fps / 1000).floor();
    return math.min(frame, (_plan['frames'] as int) - 1);
  }

  Future<void> _addNote() async {
    final text = _note.text.trim();
    if (text.isEmpty) return;
    final outcome = await widget.model.run('note', {'plan': _id, 'rec': _rec, 'text': text}, 'Saving the note');
    if (outcome?['state'] == 'done') _note.clear();
  }

  Future<void> _reject() async {
    await widget.model.run('reject', {'plan': _id, 'by': reviewer}, 'Rejecting this plan');
  }

  void _setSentence(String sentence, bool keep) {
    widget.model.runAndShowNewest('sentence', {'plan': _id, 'sentence': sentence, 'keep': keep}, keep ? 'Bringing the sentence back' : 'Cutting the sentence');
  }

  Widget _newPlan() {
    final model = widget.model;
    final hasPlans = model.plans.isNotEmpty;
    return Section(
      hasPlans ? 'Start again from an instruction' : 'Make a plan',
      children: [
        TextField(
          controller: _instruction,
          minLines: 2,
          maxLines: 3,
          maxLength: 300,
          buildCounter: nearLimitCounter,
          style: small,
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'Make a tight rough cut of this how-to video, with one title near the start.',
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonal(
            style: tonal,
            onPressed: model.busy ? null : () => model.runAndShowNewest('plan', {'instruction': _instruction.text}, 'Making a plan'),
            child: const Text('Make plan'),
          ),
        ),
      ],
    );
  }

  Widget _revisions() {
    final model = widget.model;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final item in model.plans)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text((item['id'] as String).replaceFirst('pln_', ''), style: small),
                selected: item['id'] == model.planId,
                onSelected: model.busy ? null : (_) => model.selectPlan(item['id'] as String),
              ),
            ),
        ],
      ),
    );
  }

  /// A short is taller than it's wide, so its stills and facts say so.
  bool get _vertical => ((_plan['height'] as int?) ?? 0) > ((_plan['width'] as int?) ?? 0);

  Widget _summary() {
    final model = widget.model;
    final sentences = (_plan['sentences'] as List).cast<Json>();
    final removed = sentences.where((item) => item['kept'] != true).length;
    final seconds = (_plan['frames'] as int) / _fps;
    final gate = _plan['gate'] as Json?;
    final state = _plan['state'] as String?;
    final review = _plan['review'] as String?;
    return Section(
      _id.replaceFirst('pln_', 'Revision '),
      children: [
        Fact('Timeline', _plan['timeline'] as String, exact: true),
        if (_vertical) Fact('Shape', '9:16 short, ${_plan['width']} × ${_plan['height']}, cropped from the middle'),
        Fact('Length', '${clock(seconds)}, ${_plan['frames']} frames at ${_fps.toStringAsFixed(3)} fps'),
        Fact('Cuts', '${_plan['segments']} segments, $removed of ${sentences.length} sentences out'),
        Fact('Captions', _plan['captions_file'] == null ? 'None' : 'On a subtitle track'),
        if (_plan['base'] != null) Fact('Revised from', (_plan['base'] as String).replaceFirst('pln_', '')),
        Fact('State', state ?? review ?? 'Waiting for review'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: gate == null
                  ? const Text('Not checked yet', style: quiet)
                  : gate['passed'] == true
                  ? const Status('Passed all 7 gate stages', good)
                  : Status('Refused at ${gate['stage']}: ${gate['problem']}', bad),
            ),
            TextButton(onPressed: model.busy ? null : () => model.run('validate', {'plan': _id}, 'Checking the plan'), child: const Text('Check again')),
          ],
        ),
      ],
    );
  }

  Widget _checks() {
    final flagged = flaggedIn(_plan);
    final notes = (_plan['plan_notes'] as List).cast<Json>().where((item) => item['severity'] != 'uncertain').toList();
    if (flagged.isEmpty && notes.isEmpty) return const SizedBox.shrink();
    return Section(
      'Check these',
      children: [
        for (final item in flagged)
          Alert(
            '${item['note']}: ${item['text']}',
            action: TextButton(
              onPressed: widget.model.busy || item['kept'] != true ? null : () => _setSentence(item['id'] as String, false),
              child: const Text('Cut it'),
            ),
          ),
        for (final note in notes)
          InkWell(
            onTap: () => _seekTo(note['rec'] as int),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Text(fineClock((note['rec'] as int) / _fps), style: mono),
                  const SizedBox(width: 10),
                  Expanded(child: Text(note['text'] as String, style: small)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _texts() {
    final texts = ((_plan['texts'] as List?) ?? const []).cast<Json>();
    if (texts.isEmpty) return const SizedBox.shrink();
    return Section(
      'Text on screen',
      children: [
        for (final item in texts)
          InkWell(
            onTap: () => _seekTo(item['rec_in'] as int),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Text(fineClock((item['rec_in'] as int) / _fps), style: mono),
                  const SizedBox(width: 10),
                  Expanded(child: Text(item['text'] as String, style: small)),
                  Tag((item['zone'] as String).replaceAll('_', ' ')),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _broll() {
    final model = widget.model;
    final items = ((_plan['broll'] as List?) ?? const []).cast<Json>();
    if (items.isEmpty) return const SizedBox.shrink();
    return Section(
      'B-roll',
      children: [
        const Text('Cutaways to what you mention, each on the word you say it.', style: tiny),
        const SizedBox(height: 4),
        for (final item in items)
          InkWell(
            onTap: () => _seekTo(item['rec_in'] as int),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Text(fineClock((item['rec_in'] as int) / _fps), style: mono),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(item['thing'] as String, style: small, overflow: TextOverflow.ellipsis),
                  ),
                  if (item['picture'] == null) const Tag('no photo'),
                  IconButton(
                    tooltip: 'Remove this b-roll',
                    visualDensity: VisualDensity.compact,
                    onPressed: model.busy ? null : () => model.changeAssistant('remove_broll', {'plan': _id, 'thing': item['thing']}, 'Removing the b-roll'),
                    icon: const PhosphorIcon(PhosphorIconsRegular.x, size: 14),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _send() {
    final model = widget.model;
    return Section(
      'Send this to another app',
      children: [
        const Text('Send a clip, preview or final render. Your original stays where it is.', style: tiny),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(onPressed: model.busy ? null : () => sendClip(context, model, toResolve: true), child: const Text('Send to Resolve')),
            OutlinedButton(onPressed: model.busy ? null : () => sendClip(context, model, toResolve: false), child: const Text('Send to EffectCraft')),
          ],
        ),
      ],
    );
  }

  Widget _graphic(Json graphic) {
    final model = widget.model;
    return Section(
      'Graphic from EffectCraft',
      children: [
        Fact('Starts at', frameAndTime(graphic['rec_in'] as int, _fps), exact: true),
        Fact('Length', '${graphic['frames']} frames', exact: true),
        Fact('Asset', '${graphic['asset']} r${graphic['rev']}', exact: true),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: model.busy ? null : () => model.run('clear_graphic', {}, 'Going back to a title'),
            child: const Text('Use a generated title next time'),
          ),
        ),
      ],
    );
  }

  Widget _clipStarts() {
    final clips = ((_plan['clip_starts'] as List?) ?? const []).cast<Json>();
    if (clips.length < 2) return const SizedBox.shrink();
    return Section(
      'Clips in this cut',
      children: [
        for (final clip in clips)
          InkWell(
            onTap: () => _seekTo(clip['rec_in'] as int),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Text(fineClock((clip['rec_in'] as int) / _fps), style: mono),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(clip['name'] as String, style: small, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _title() {
    final model = widget.model;
    final title = _plan['title'] as Json?;
    final graphic = _plan['graphic'] as Json?;
    if (graphic != null) return _graphic(graphic);
    if (title == null) return const SizedBox.shrink();
    final stills = (_plan['stills'] as List).cast<String>();
    return Section(
      'Title',
      trailing: stills.isEmpty
          ? TextButton(onPressed: model.busy ? null : () => model.run('stills', {'plan': _id}, 'Rendering stills'), child: const Text('Preview frames'))
          : null,
      children: [
        Text(title['text'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Fact('Starts at', frameAndTime(title['rec_in'] as int, _fps), exact: true),
        Fact('Fades', '${title['in_frames']} frames in, ${title['out_frames']} out'),
        Fact('Look', '${title['font']}, ${(title['zone'] as String).replaceAll('_', ' ')}'),
        Fact('Asset', 'ast_title1 r${title['rev']}', exact: true),
        if (_plan['editable'] != null)
          Align(
            alignment: Alignment.centerLeft,
            child: RevealButton(() => reveal(_plan['editable'] as String), label: 'Show the EffectCraft project'),
          ),
        if (stills.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              for (final still in stills)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: AspectRatio(
                      aspectRatio: _vertical ? 9 / 16 : 16 / 9,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: ColoredBox(
                          color: Graphite.raised,
                          child: Image.file(File(still), fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _transcript() {
    final model = widget.model;
    final sentences = (_plan['sentences'] as List).cast<Json>();
    return Section(
      'Transcript',
      children: [
        const Text('Struck through is out of the cut. Click a line to jump to it.', style: quiet),
        const SizedBox(height: 6),
        for (final item in sentences)
          _SentenceRow(
            // Keyed by sentence, so moving to another revision compares each line with itself.
            key: ValueKey(item['id']),
            sentence: item,
            onSeek: () => _seekTo(item['rec'] as int?),
            onChange: model.busy ? null : () => _setSentence(item['id'] as String, item['kept'] != true),
          ),
      ],
    );
  }

  Widget _cuts() {
    final cuts = (_plan['cuts'] as List).cast<Json>();
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Panel(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: ExpansionTile(
            trailing: const PhosphorIcon(PhosphorIconsRegular.caretDown, size: 14),
            title: Text('Exact cuts, in frames (${cuts.length})', style: Theme.of(context).textTheme.titleSmall),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              const Row(
                children: [
                  Expanded(child: Text('segment', style: tiny)),
                  Expanded(child: Text('source in', style: tiny)),
                  Expanded(child: Text('source out', style: tiny)),
                  Expanded(child: Text('timeline in', style: tiny)),
                ],
              ),
              for (final cut in cuts)
                InkWell(
                  onTap: () => _seekTo(cut['rec_in'] as int),
                  child: Row(
                    children: [
                      Expanded(child: Text(cut['id'] as String, style: mono)),
                      Expanded(child: Text('${cut['src_in']}', style: mono)),
                      Expanded(child: Text('${cut['src_out']}', style: mono)),
                      Expanded(child: Text('${cut['rec_in']}', style: mono)),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Out points are exclusive.', style: tiny),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _notes() {
    final model = widget.model;
    final notes = (_plan['notes'] as List).cast<Json>();
    if (notes.isEmpty) return const SizedBox.shrink();
    return Section(
      'Notes',
      children: [
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => _seekTo(note['rec'] as int),
                  child: Text(fineClock((note['rec'] as int) / _fps), style: mono),
                ),
                const SizedBox(width: 4),
                Expanded(child: Text(note['text'] as String, style: small)),
                if (note['result'] != null)
                  Text('Made ${(note['result'] as String).replaceFirst('pln_', '')}', style: tiny)
                else
                  TextButton(
                    onPressed: model.busy ? null : () => model.runAndShowNewest('revise', {'plan': _id, 'note': note['id']}, 'Making this change'),
                    child: const Text('Make this change'),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _decision() {
    final model = widget.model;
    final state = _plan['state'] as String?;
    final applied = state == 'APPLIED';
    final started = state != null && state != 'AWAITING_APPROVAL';
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (_plan['review'] == 'rejected') const Expanded(child: Status('Rejected', waiting)),
        TextButton(onPressed: model.busy || started ? null : _reject, child: const Text('Reject')),
        const SizedBox(width: 8),
        if (started)
          FilledButton.tonal(style: tonal, onPressed: widget.onShowResolve, child: Text(applied ? 'Applied. See Resolve' : 'See progress in Resolve'))
        else
          FilledButton(onPressed: model.busy ? null : () => approvePlan(context, model), child: const Text('Approve and build')),
      ],
    );
  }

  Widget _player() {
    final model = widget.model;
    final hasPlan = model.plan != null;
    final hasPreview = hasPlan && _plan['preview_path'] != null;
    return ScreenView(
      _screen,
      placeholder: hasPreview
          ? null
          : hasPlan
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('No preview of this revision yet', style: quiet),
                const SizedBox(height: 10),
                FilledButton.tonal(
                  style: tonal,
                  onPressed: model.busy ? null : () => model.run('preview', {'plan': _id}, 'Making a preview'),
                  child: const Text('Make preview'),
                ),
                const SizedBox(height: 6),
                const Text("Made with ffmpeg alone, so it doesn't need Resolve", style: tiny),
              ],
            )
          : const Text('Make a plan to see it here', style: quiet),
    );
  }

  Future<void> _export() async {
    final id = _id;
    final outcome = await widget.model.run('export', {'plan': id}, 'Exporting an MP4');
    if (!mounted || outcome?['state'] != 'done') return;
    setState(() => _exports[id] = outcome!['result'] as Json);
  }

  /// A finished file for posting, without Resolve. It says what it made and where.
  Widget _exportRow() {
    final model = widget.model;
    final made = _exports[_id];
    final loudness = made?['loudness'] as num?;
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4),
      child: Row(
        children: [
          OutlinedButton(onPressed: model.busy ? null : _export, child: const Text('Export MP4')),
          const SizedBox(width: 10),
          Expanded(
            child: Swap(
              child: made == null
                  ? const Text('Full size, loudness set for YouTube, TikTok and Reels. Resolve isn\'t needed.', key: ValueKey('export-hint'), style: tiny)
                  : Row(
                      key: ValueKey(('export', made['path'])),
                      children: [
                        const DrawnCheck(size: 13),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${made['width']}x${made['height']}, ${(made['seconds'] as num).round()} s'
                            '${loudness == null ? ', no sound' : ', loudness ${loudness.toStringAsFixed(1)} to -14 LUFS'}',
                            style: mono,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        RevealButton(() => reveal(made['path'] as String)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noteBar() {
    final model = widget.model;
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          ValueListenableBuilder(
            valueListenable: _screen.position,
            builder: (_, position, _) => Text(fineClock(position.inMilliseconds / 1000), style: mono),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _note,
              enabled: model.plan != null,
              maxLength: 500,
              buildCounter: nearLimitCounter,
              onSubmitted: (_) => _addNote(),
              decoration: const InputDecoration(hintText: 'Note at this moment, such as: make this title faster'),
            ),
          ),
          IconButton(
            tooltip: 'Add note',
            onPressed: model.busy || model.plan == null ? null : _addNote,
            icon: const PhosphorIcon(PhosphorIconsRegular.notePencil, size: 18),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    if (!model.isOpen) return const Empty('Open a project first');
    final footage = model.footage;
    if (footage == null || footage['analysed'] != true) return const Empty('Add and analyse a clip on the Footage page first');
    final hasPlan = model.plan != null;
    final entry = model.plans.where((item) => item['id'] == model.planId).firstOrNull;
    final stale = ((entry?['stale'] as List?) ?? const []).cast<String>();
    final missing = (model.report!['missing'] as List).cast<Json>();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _player()),
              if (hasPlan && _plan['preview_path'] != null)
                const Padding(
                  padding: EdgeInsets.only(top: 6, left: 4),
                  child: Text('Preview at your clip\'s full size. Colour isn\'t final.', style: tiny),
                ),
              if (hasPlan) _exportRow(),
              const SizedBox(height: 10),
              _noteBar(),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  controller: _panel,
                  children: [
                    for (final item in missing) Alert('The ${item['kind']} ${item['id']}: ${item['reason']}.', color: bad),
                    if (hasPlan) ...[
                      _revisions(),
                      const SizedBox(height: 10),
                      for (final reason in stale) Alert('Out of date: $reason.'),
                      _summary(),
                      _checks(),
                      _clipStarts(),
                      _title(),
                      _texts(),
                      _broll(),
                      _send(),
                      _notes(),
                      _transcript(),
                      _cuts(),
                    ],
                    _newPlan(),
                  ],
                ),
              ),
              if (hasPlan) ...[const SizedBox(height: 8), _decision()],
            ],
          ),
        ),
      ],
    );
  }
}

/// One line of the transcript. When a revision or a click changes whether it's kept, the line
/// lights up for a moment and its colour and strike-through fade over, so what changed shows.
class _SentenceRow extends StatefulWidget {
  const _SentenceRow({super.key, required this.sentence, required this.onSeek, required this.onChange});

  final Json sentence;
  final VoidCallback onSeek;
  final VoidCallback? onChange;

  @override
  State<_SentenceRow> createState() => _SentenceRowState();
}

class _SentenceRowState extends State<_SentenceRow> with SingleTickerProviderStateMixin {
  late final AnimationController _wash = AnimationController(vsync: this, duration: Motion.wash, value: 1);

  bool get _kept => widget.sentence['kept'] == true;

  @override
  void didUpdateWidget(_SentenceRow old) {
    super.didUpdateWidget(old);
    if ((old.sentence['kept'] == true) != _kept) _wash.forward(from: 0);
  }

  @override
  void dispose() {
    _wash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kept = _kept;
    final label = widget.sentence['label'] as String?;
    // A cut line washes in its new colour. A line brought back washes neutral, because mint is only for what's active.
    final washColor = kept ? Graphite.text : bad;
    return AnimatedBuilder(
      animation: _wash,
      builder: (context, child) => DecoratedBox(
        decoration: BoxDecoration(
          color: washColor.withValues(alpha: .14 * (1 - Curves.easeOut.transform(_wash.value))),
          borderRadius: BorderRadius.circular(6),
        ),
        child: child,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: widget.onSeek,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: kept ? 0 : 1),
                  duration: Motion.settle,
                  curve: Motion.curve,
                  builder: (context, cut, _) => Text(
                    widget.sentence['text'] as String,
                    style: TextStyle(
                      fontSize: 13,
                      decoration: cut > 0 ? TextDecoration.lineThrough : null,
                      decorationColor: bad.withValues(alpha: cut),
                      color: Color.lerp(Graphite.text, bad, cut),
                    ),
                  ),
                ),
              ),
              if (label != null) ...[const SizedBox(width: 6), Tag(label.replaceAll('_', ' '))],
              IconButton(
                iconSize: 15,
                visualDensity: VisualDensity.compact,
                tooltip: kept ? 'Cut this sentence' : 'Bring it back',
                onPressed: widget.onChange,
                icon: Swap(
                  alignment: Alignment.center,
                  child: PhosphorIcon(kept ? PhosphorIconsRegular.scissors : PhosphorIconsRegular.arrowCounterClockwise, key: ValueKey(kept), size: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
