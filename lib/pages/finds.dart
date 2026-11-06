import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../engine.dart';
import '../motion.dart';
import '../project.dart';
import '../theme.dart';
import '../ui.dart';
import 'preview.dart';

String clock(num seconds) {
  final whole = seconds.round();
  return '${whole ~/ 60}:${(whole % 60).toString().padLeft(2, '0')}';
}

String views(num value) => value >= 1000000
    ? '${(value / 1000000).toStringAsFixed(1)}M views'
    : value >= 1000
    ? '${(value / 1000).toStringAsFixed(0)}k views'
    : '$value views';

/// Popular short videos about what this clip is about. The words are suggested from what's said,
/// a person can change them, and only their click on Search sends them to YouTube.
class FindReferences extends StatefulWidget {
  const FindReferences(this.model, {super.key});

  final ProjectModel model;

  @override
  State<FindReferences> createState() => _FindReferencesState();
}

class _FindReferencesState extends State<FindReferences> {
  final _words = TextEditingController();
  List<Json>? _results;
  String? _using;
  String? _problem;
  String? _why;
  int _search = 0;

  ProjectModel get model => widget.model;

  @override
  void dispose() {
    _words.dispose();
    super.dispose();
  }

  Future<void> _suggest() async {
    final outcome = await model.run('reference_words', {}, 'Working out what the video is about', quiet: true);
    if (!mounted || outcome == null) return;
    setState(() {
      if (outcome['state'] == 'done') {
        final result = outcome['result'] as Json;
        _words.text = result['words'] as String? ?? '';
        _why = result['why'] as String?;
        _problem = null;
      } else {
        _problem = outcome['error'] as String?;
      }
    });
  }

  Future<void> _find() async {
    final words = _words.text.trim();
    if (words.isEmpty) return;
    final outcome = await model.run('find_references', {'words': words}, 'Searching YouTube', quiet: true);
    if (!mounted || outcome == null) return;
    setState(() {
      if (outcome['state'] == 'done') {
        _results = ((outcome['result'] as Json)['results'] as List).cast<Json>();
        _problem = null;
        _search++;
      } else {
        _problem = outcome['error'] as String?;
      }
    });
  }

  Future<void> _use(Json video) async {
    setState(() => _using = video['id'] as String);
    final outcome = await model.run('use_reference', {'id': video['id'], 'short': video['short'] == true}, 'Fetching and measuring the reference');
    if (!mounted || outcome == null) return;
    final done = outcome['state'] == 'done';
    setState(() {
      _using = null;
      _problem = done ? null : outcome['error'] as String?;
      // The choice now shows above as the measured style, so the list has done its job.
      if (done) _results = null;
    });
    if (done) model.say('Using “${video['title']}” as the reference');
  }

  /// Shows the video's stills and details first. Its own Use this does what Use does here.
  Future<void> _preview(Json video) async {
    if (await showVideoPreview(context, model, video) && mounted) await _use(video);
  }

  Widget _result(Json video, int index) {
    final dimmed = _using != null && _using != video['id'];
    return Arrive(
      key: ValueKey(('video', _search, video['id'])),
      delay: Duration(milliseconds: 30 * index),
      child: AnimatedOpacity(
        opacity: dimmed ? .35 : 1,
        duration: Motion.settle,
        curve: Motion.curve,
        child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: model.busy ? null : () => _preview(video),
                      child: Text(video['title'] as String, style: small, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('${video['channel']}  ·  ${views(video['views'] as num)}  ·  ${clock(video['seconds'] as num)}', style: mono, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (video['short'] == true) ...[const Tag('short'), const SizedBox(width: 8)],
            TextButton(onPressed: model.busy ? null : () => _preview(video), child: const Text('Preview')),
            TextButton(onPressed: model.busy ? null : () => _use(video), child: const Text('Use')),
          ],
        ),
      ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Section(
      'Find a reference',
      children: [
        const Text('Popular short videos about the same thing. Pick one and the cut takes its colours, title place and pace.', style: quiet),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _words,
                style: small,
                decoration: const InputDecoration(hintText: 'What the video is about, such as robotic arm build'),
                onSubmitted: (_) => _find(),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: model.busy ? null : _suggest, child: const Text('Suggest words')),
            const SizedBox(width: 8),
            FilledButton(onPressed: model.busy ? null : _find, child: const Text('Search')),
          ],
        ),
        if (_why != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_why!, style: tiny)),
        if (_problem != null) Padding(padding: const EdgeInsets.only(top: 8), child: Alert(_problem!, color: bad)),
        if (results != null) ...[
          const SizedBox(height: 8),
          if (results.isEmpty) const Text('No short videos matched. Try other words.', style: quiet),
          for (final (index, video) in results.indexed) _result(video, index),
        ],
        const SizedBox(height: 8),
        const Text('Only these words go to YouTube, and only when you press Search. Footage, music and words are never copied from a reference.', style: tiny),
      ],
    );
  }
}

/// Music to cut to: a person's own file, or a Creative Commons track from Openverse.
class MusicSection extends StatefulWidget {
  const MusicSection(this.model, {super.key});

  final ProjectModel model;

  @override
  State<MusicSection> createState() => _MusicSectionState();
}

class _MusicSectionState extends State<MusicSection> {
  final _words = TextEditingController();
  List<Json>? _results;
  // The track on screen when the page opened. A new one draws its beats; that one is just there.
  String? _seenTrack;
  bool _seen = false;
  String? _problem;
  int _search = 0;

  ProjectModel get model => widget.model;

  @override
  void dispose() {
    _words.dispose();
    super.dispose();
  }

  void _ended(Json? outcome) {
    if (!mounted || outcome == null) return;
    setState(() => _problem = outcome['state'] == 'done' ? null : outcome['error'] as String?);
  }

  Future<void> _fromComputer() async {
    const music = XTypeGroup(label: 'Music', extensions: ['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg', 'aif', 'aiff']);
    final file = await openFile(acceptedTypeGroups: [music]);
    if (file == null) return;
    _ended(await model.run('music_file', {'path': file.path}, 'Reading the music and finding its beats'));
  }

  Future<void> _find() async {
    final words = _words.text.trim();
    if (words.isEmpty) return;
    final outcome = await model.run('find_music', {'words': words}, 'Searching Openverse', quiet: true);
    if (!mounted || outcome == null) return;
    setState(() {
      if (outcome['state'] == 'done') {
        _results = ((outcome['result'] as Json)['results'] as List).cast<Json>();
        _problem = null;
        _search++;
      } else {
        _problem = outcome['error'] as String?;
      }
    });
  }

  Future<void> _use(Json track) async => _ended(await model.run('use_music', {'id': track['id']}, 'Downloading the music and finding its beats'));

  Future<void> _clear() async => _ended(await model.run('clear_music', {}, 'Removing the music'));

  String _licence(String licence) => switch (licence) {
    'cc0' => 'CC0',
    'pdm' => 'public domain',
    'yours' => 'your file',
    _ => 'CC ${licence.toUpperCase()}',
  };

  Widget _chosen(Json track) {
    final fresh = _seen && _seenTrack != track['id'];
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(border: Border.all(color: Graphite.line), borderRadius: BorderRadius.circular(smallCorner)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(track['title'] as String, style: small, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(
                  children: [
                    CountUp((track['bpm'] as num).toDouble(), play: fresh, style: mono, format: (value) => '${value.toStringAsFixed(1)} BPM'),
                    Text('  ·  ${clock(track['seconds'] as num)}  ·  ${track['beats']} beats', style: mono),
                  ],
                ),
                const SizedBox(height: 6),
                BeatStrip(
                  key: ValueKey(('beats', track['id'])),
                  play: fresh,
                  marks: [for (final mark in (track['marks'] as List? ?? const [])) (mark as num).toDouble()],
                  energy: [for (final loud in (track['energy'] as List? ?? const [])) (loud as num).toDouble()],
                ),
                if ((track['credit'] as String).isNotEmpty) ...[const SizedBox(height: 4), Text('Credit: ${track['credit']}', style: tiny)],
              ],
            ),
          ),
          Tag(_licence(track['licence'] as String)),
          const SizedBox(width: 8),
          TextButton(onPressed: model.busy ? null : _clear, child: const Text('Remove')),
        ],
      ),
    );
  }

  Widget _result(Json track, int index) {
    return Arrive(
      key: ValueKey(('track', _search, track['id'])),
      delay: Duration(milliseconds: 30 * index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track['title'] as String, style: small, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('${track['creator']}  ·  ${clock(track['seconds'] as num)}', style: mono, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Tag(_licence(track['licence'] as String)),
            const SizedBox(width: 8),
            TextButton(onPressed: model.busy ? null : () => _use(track), child: const Text('Use')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chosen = model.music;
    final results = _results;
    final shown = chosen == null ? null : _chosen(chosen);
    if (!_seen || chosen?['id'] != _seenTrack) {
      // Remember after this frame, so the build that shows a new track still sees it as new.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _seen = true;
        _seenTrack = chosen?['id'] as String?;
      });
    }
    return Section(
      'Music',
      trailing: OutlinedButton(onPressed: model.busy ? null : _fromComputer, child: const Text('From computer')),
      children: [
        const Text('Cuts land on its beats, and it\'s lowered while anyone talks.', style: quiet),
        const SizedBox(height: 10),
        if (shown != null) shown else const Padding(padding: EdgeInsets.only(bottom: 10), child: Text('No music chosen.', style: tiny)),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _words,
                style: small,
                decoration: const InputDecoration(hintText: 'Free music from Openverse, such as upbeat electronic'),
                onSubmitted: (_) => _find(),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: model.busy ? null : _find, child: const Text('Search')),
          ],
        ),
        if (_problem != null) Padding(padding: const EdgeInsets.only(top: 8), child: Alert(_problem!, color: bad)),
        if (results != null) ...[
          const SizedBox(height: 8),
          if (results.isEmpty) const Text('No reusable music matched. Try other words.', style: quiet),
          for (final (index, track) in results.indexed) _result(track, index),
        ],
        const SizedBox(height: 8),
        const Text('Openverse tracks are offered only under CC0, public domain, CC BY or CC BY-SA, and each one\'s credit is shown. '
            'Then ask the Assistant: “make a short with no talking, cut to the beat”, or “add music under this”.', style: tiny),
      ],
    );
  }
}
