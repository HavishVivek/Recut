import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../engine.dart';
import '../project.dart';
import '../ui.dart';
import 'exchange.dart';
import 'import.dart';

class FootagePage extends StatefulWidget {
  const FootagePage({super.key, required this.model, required this.enablePreview});

  final ProjectModel model;
  final bool enablePreview;

  @override
  State<FootagePage> createState() => _FootagePageState();
}

class _FootagePageState extends State<FootagePage> {
  late final Screen _screen = Screen(widget.enablePreview);

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
    super.dispose();
  }

  void _sync() {
    final footage = widget.model.footage;
    _screen.show(footage?['play'] as String? ?? footage?['proxy'] as String? ?? footage?['path'] as String?);
  }

  Future<void> _addClip() async {
    const videos = XTypeGroup(label: 'Video', extensions: ['mp4', 'mov', 'mkv', 'm4v']);
    final file = await openFile(acceptedTypeGroups: [videos]);
    if (file == null) return;
    await widget.model.run('add_clip', {'path': file.path}, 'Adding the clip');
  }

  Future<void> _importFolder() async {
    final path = await getDirectoryPath(confirmButtonText: 'Use this folder');
    if (path != null && mounted) await importFrom(context, widget.model, path);
  }

  void _seek(num seconds) => _screen.seek(Duration(milliseconds: (seconds * 1000).round()));

  Widget _facts(Json footage) {
    final model = widget.model;
    final facts = footage['facts'] as Json;
    final audio = footage['audio'] as Json?;
    final flags = [...facts['flags'] as List, ...(audio?['flags'] as List? ?? const [])];
    final timing = facts['timing'] as String;
    return Section(
      footage['name'] as String,
      trailing: footage['analysed'] == true
          ? TextButton(
              onPressed: model.busy ? null : () => model.run('analyse', {}, 'Analysing again'),
              child: const Text('Check again'),
            )
          : null,
      children: [
        Fact('Picture', '${facts['width']}x${facts['height']}, ${(facts['fps'] as num).toStringAsFixed(3)} fps'),
        Fact('Length', '${clock(facts['seconds'] as num)}, ${facts['frames']} frames'),
        Fact('Frame timing', facts['dropped_frames'] == 0 ? timing : '$timing, ${facts['dropped_frames']} dropped'),
        Fact('Audio', facts['has_audio'] == true ? (audio == null ? 'Not measured yet' : 'Speech ${audio['speech_db']} dB, room ${audio['noise_db']} dB') : 'None'),
        if (footage['language'] != null) Fact('Language', footage['language'] as String),
        Fact('Proxy', footage['proxy'] == null ? 'Not made yet' : 'Ready'),
        if (footage['using_copy'] == true) const Fact('Working from', 'A constant-rate copy. The original is unchanged.'),
        if (flags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final flag in flags) Tag('$flag'.replaceAll('_', ' '), color: waiting)],
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          children: [
            OutlinedButton(onPressed: model.busy ? null : () => sendClip(context, model, toResolve: true), child: const Text('Send to Resolve')),
            OutlinedButton(onPressed: model.busy ? null : () => sendClip(context, model, toResolve: false), child: const Text('Send to EffectCraft')),
            TextButton(onPressed: model.busy ? null : () => importFromEffectCraft(model), child: const Text('Add EffectCraft graphic')),
          ],
        ),
        if (footage['offer'] != null) ...[
          const SizedBox(height: 10),
          Alert(footage['offer'] as String),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: model.busy ? null : () => model.run('accept_copy', {}, 'Making a constant-rate copy'),
              child: const Text('Make a constant-rate copy'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _clips(Json footage) {
    final model = widget.model;
    final clips = ((footage['clips'] as List?) ?? const []).cast<Json>();
    final inCut = ((model.plan?['clips'] as List?) ?? const []).cast<String>();
    return Section(
      'Clips in this project',
      children: [
        for (final clip in clips)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(width: 20, child: Text('${clip['number']}', style: mono)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(clip['name'] as String, style: small, overflow: TextOverflow.ellipsis),
                      Text(_clipFacts(clip), style: tiny, overflow: TextOverflow.ellipsis),
                      Wrap(
                        spacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (clip['path'] != null) TextButton(onPressed: () => _screen.show(clip['path'] as String), child: const Text('Watch')),
                          if (clip['project'] != null) TextButton(onPressed: () => model.openProject(clip['project'] as String), child: const Text('Open in EffectCraft')),
                          if (clip['editing'] == true)
                            const Tag('Editing')
                          else ...[
                            TextButton(
                              onPressed: model.busy ? null : () => model.run('edit_clip', {'clip': clip['id']}, 'Switching to clip ${clip['number']}'),
                              child: const Text('Edit this clip'),
                            ),
                            if (inCut.contains('clip ${clip['number']}'))
                              TextButton(onPressed: model.busy ? null : () => model.changeCut('remove_from_cut', clip['id'] as String), child: const Text('Remove from cut'))
                            else
                              OutlinedButton(onPressed: model.busy ? null : () => model.changeCut('add_to_cut', clip['id'] as String), child: const Text('Add to cut')),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(onPressed: model.busy ? null : _addClip, child: const Text('Add another clip')),
            TextButton(onPressed: model.busy ? null : () => importFromResolve(context, model), child: const Text('From Resolve')),
          ],
        ),
      ],
    );
  }

  String _clipFacts(Json clip) {
    final rate = (clip['fps'] as num).toStringAsFixed((clip['fps'] as num) % 1 == 0 ? 0 : 2);
    final sound = clip['has_audio'] == true ? '' : ', no sound';
    final matched = clip['matched'] == true ? ', matched to this project' : '';
    return '${clip['width']}x${clip['height']}, $rate fps, ${clock(clip['seconds'] as num)}$sound$matched';
  }

  Widget _row(num at, String text, {String? extra, bool dim = false}) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _seek(at),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 48, child: Text(clock(at), style: mono)),
            Expanded(child: Text(text, style: dim ? quiet : small)),
            if (extra != null) Text(extra, style: tiny),
          ],
        ),
      ),
    );
  }

  Widget _found(Json footage) {
    final sentences = (footage['sentences'] as List).cast<Json>();
    final pauses = (footage['pauses'] as List).cast<Json>();
    final fillers = (footage['fillers'] as List).cast<Json>();
    final shots = (footage['shots'] as List).cast<num>();
    Widget listOf(List<Widget> rows, String empty) =>
        rows.isEmpty ? Padding(padding: const EdgeInsets.all(12), child: Text(empty, style: quiet)) : ListView(children: rows);
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: 10),
            tabs: [
              Tab(text: 'Transcript ${sentences.length}'),
              Tab(text: 'Pauses ${pauses.length}'),
              Tab(text: 'Fillers ${fillers.length}'),
              Tab(text: 'Shots ${shots.length}'),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: TabBarView(
              children: [
                listOf([for (final s in sentences) _row(s['start'] as num, s['text'] as String)], 'No speech found'),
                listOf([
                  for (final p in pauses)
                    _row(
                      p['start'] as num,
                      '${((p['end'] as num) - (p['start'] as num)).toStringAsFixed(2)} s',
                      extra: p['quiet'] == true ? 'quiet' : 'has sound',
                    ),
                ], 'No pauses found'),
                listOf([for (final f in fillers) _row(f['start'] as num, f['text'] as String)], 'No filler words found'),
                listOf([for (final at in shots) _row(at, 'Shot change')], 'One continuous shot'),
              ],
            ),
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
    if (footage == null) {
      return Empty(
        icon: PhosphorIconsDuotone.filmStrip,
        'Pick the clip for this project. It stays where it is and is never changed.',
        action: Wrap(
          spacing: 8,
          children: [
            FilledButton(onPressed: model.busy ? null : _addClip, child: const Text('Add clip')),
            TextButton(onPressed: model.busy ? null : _importFolder, child: const Text('Import from a folder')),
            TextButton(onPressed: model.busy ? null : () => importFromResolve(context, model), child: const Text('From Resolve')),
            TextButton(onPressed: model.busy ? null : () => importFromEffectCraft(model), child: const Text('From EffectCraft')),
          ],
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 3, child: ScreenView(_screen)),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _facts(footage),
              ConstrainedBox(constraints: const BoxConstraints(maxHeight: 210), child: SingleChildScrollView(child: _clips(footage))),
              Expanded(child: Panel(child: _found(footage))),
            ],
          ),
        ),
      ],
    );
  }
}
