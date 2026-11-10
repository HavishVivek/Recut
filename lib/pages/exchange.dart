import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../drop.dart';
import '../engine.dart';
import '../project.dart';
import '../theme.dart';
import '../ui.dart';

/// Picks one item from a list, which is how every clip moves in or out.
Future<Json?> _pick(BuildContext context, String title, String note, List<Json> items, String Function(Json) label, {String? Function(Json)? detail}) {
  return showDialog<Json>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 520,
        height: 340,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(note, style: quiet),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                children: [
                  for (final item in items)
                    ListTile(
                      dense: true,
                      title: Text(label(item), style: small, overflow: TextOverflow.ellipsis),
                      subtitle: detail?.call(item) == null ? null : Text(detail!(item)!, style: mono, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(context, item),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    ),
  );
}

/// Takes a clip from whatever Resolve has open. It stays where it is on disk.
Future<void> importFromResolve(BuildContext context, ProjectModel model) async {
  final outcome = await model.run('resolve_clips', {}, 'Reading Resolve\'s media pool', quiet: true);
  final seen = outcome?['result'] as Json?;
  if (seen == null || !context.mounted) return;
  final clips = (seen['clips'] as List).cast<Json>();
  if (clips.isEmpty) {
    model.complain('${seen['project'] ?? 'Resolve'} has no video in its media pool.');
    return;
  }
  final chosen = await _pick(context, 'Choose a clip from ${seen['project']}', 'A project holds one clip. Nothing changes in Resolve, and nothing is copied.', clips,
      (item) => item['name'] as String, detail: (item) => endOfPath(item['path'] as String));
  if (chosen != null) await model.run('add_clip', {'path': chosen['path']}, 'Adding the clip');
}

/// Brings an EffectCraft project in as the clip, or as the graphic if there's a clip already.
Future<void> importFromEffectCraft(ProjectModel model) async {
  const projects = XTypeGroup(label: 'EffectCraft project', extensions: ['ecproj']);
  final file = await openFile(acceptedTypeGroups: [projects]);
  if (file == null) return;
  final outcome = await model.run('import_effectcraft', {'path': file.path}, 'Importing from EffectCraft');
  final done = outcome?['result'] as Json?;
  if (done == null) return;
  model.say(done['used_as'] == 'clip' ? 'That project is now this project\'s clip.' : 'That project is now the graphic. The next plan or revision uses it in place of the title.');
}

/// Sends a clip from this project to another app. Originals are referenced, never moved.
Future<void> sendClip(BuildContext context, ProjectModel model, {required bool toResolve}) async {
  final outcome = await model.run('sendable', {}, 'Finding what can be sent', quiet: true);
  final items = ((outcome?['result'] as Json?)?['items'] as List?)?.cast<Json>();
  if (items == null || !context.mounted) return;
  final target = toResolve ? 'Resolve' : 'EffectCraft';
  final note = toResolve ? 'It goes into the media pool of the project open in Resolve.' : 'This makes a new EffectCraft project with the clip on a comp.';
  final chosen = await _pick(context, 'Send to $target', note, items, (item) => item['label'] as String, detail: (item) => endOfPath(item['path'] as String));
  if (chosen == null) return;
  final sent = await model.run(toResolve ? 'send_to_resolve' : 'send_to_effectcraft', {'key': chosen['key']}, 'Sending to $target', quiet: true);
  await model.refresh();
  final done = sent?['result'] as Json?;
  if (done == null) return;
  if (toResolve) {
    model.say('${done['name']} is now in ${done['project']}. Save the project in Resolve to keep it.');
  } else if (context.mounted) {
    await _opened(context, done['project'] as String);
  }
}

Future<void> _opened(BuildContext context, String project) {
  return showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Sent to EffectCraft'),
      content: SizedBox(width: 460, child: Text(endOfPath(project), style: mono.copyWith(color: Graphite.text))),
      actions: [
        TextButton(onPressed: () => reveal(project), child: const Text('Show in Finder')),
        FilledButton(
          onPressed: () {
            openInEffectCraft(project);
            Navigator.pop(context);
          },
          child: const Text('Open in EffectCraft'),
        ),
      ],
    ),
  );
}

/// The two ways in for a reference, shared by Style and the Assistant.
class ReferenceButtons extends StatelessWidget {
  const ReferenceButtons(this.model, {super.key, this.onAdded});

  final ProjectModel model;
  final Future<void> Function()? onAdded;

  Future<void> _fromComputer() async {
    const pictures = XTypeGroup(label: 'Image or short clip', extensions: ['png', 'jpg', 'jpeg', 'webp', 'mp4', 'mov', 'mkv', 'm4v', 'webm']);
    final file = await openFile(acceptedTypeGroups: [pictures]);
    if (file == null) return;
    await model.run('reference', {'path': file.path}, 'Measuring the reference');
    await onAdded?.call();
  }

  Future<void> _fromLink(BuildContext context) async {
    final link = await showDialog<String>(context: context, builder: (_) => const _LinkDialog());
    if (link == null) return;
    await model.run('reference_link', {'link': link}, 'Fetching the reference');
    await onAdded?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        OutlinedButton(onPressed: model.busy ? null : _fromComputer, child: const Text('From computer')),
        OutlinedButton(onPressed: model.busy ? null : () => _fromLink(context), child: const Text('From a link')),
      ],
    );
  }
}

/// Photos of real parts, which a new video uses before looking online. Each shows where it's
/// used and what it shows, so a photo named IMG_1234.jpg can still be found as a drone.
class PartPhotos extends StatelessWidget {
  const PartPhotos(this.model, {super.key});

  final ProjectModel model;

  Future<void> _add() async {
    const pictures = XTypeGroup(label: 'Photos, 3D models and sketches', extensions: [...pictureExtensions, ...modelExtensions, ...codeExtensions]);
    final files = await openFiles(acceptedTypeGroups: [pictures]);
    if (files.isEmpty) return;
    await model.run('add_pictures', {'paths': [for (final file in files) file.path]}, 'Adding your photos');
  }

  @override
  Widget build(BuildContext context) {
    final photos = model.photos;
    final unused = photos.where((photo) => photo['picture'] == true && (photo['scenes'] as List).isEmpty).length;
    return Section(
      'Your photos and 3D models',
      children: [
        const Text('New videos use these first, then look on Wikimedia Commons. A photo is found by its name and by what you say it shows.', style: tiny),
        const SizedBox(height: 4),
        const Text('A 3D model replaces a part\'s built-in shapes: servo.glb for the whole part, servo-motor.stl and so on for the inside view. '
            'An .ino sketch is what a scene about the code shows.', style: tiny),
        const SizedBox(height: 8),
        if (photos.isNotEmpty) ...[
          if (unused > 0 && photos.any((photo) => (photo['scenes'] as List).isNotEmpty))
            Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('$unused not used by the draft', style: tiny)),
          Wrap(
            spacing: 8,
            runSpacing: 10,
            children: [for (final photo in photos) _PhotoTile(key: ValueKey(photo['name']), model: model, photo: photo)],
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            OutlinedButton(onPressed: model.busy ? null : _add, child: const Text('Add photos or models')),
            // The photo model looks at new photos as they come in. This catches ones added before it was set up.
            if (photos.any((photo) => photo['picture'] == true && (photo['words'] as String? ?? '').isEmpty))
              TextButton(onPressed: model.busy ? null : () => model.run('describe_photos', {}, 'Looking at your photos'), child: const Text('Describe my photos')),
          ],
        ),
        const SizedBox(height: 4),
        const Text('Or drop them anywhere on the window.', style: tiny),
      ],
    );
  }
}

class _PhotoTile extends StatefulWidget {
  const _PhotoTile({super.key, required this.model, required this.photo});

  final ProjectModel model;
  final Json photo;

  @override
  State<_PhotoTile> createState() => _PhotoTileState();
}

class _PhotoTileState extends State<_PhotoTile> {
  // Two to a row in the Assistant's side panel.
  static const _tile = 125.0;

  late final _words = TextEditingController(text: widget.photo['words'] as String? ?? '');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // A person's words are kept when they leave the box, as well as on Return.
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
  }

  @override
  void didUpdateWidget(_PhotoTile old) {
    super.didUpdateWidget(old);
    final words = widget.photo['words'] as String? ?? '';
    if (!_focus.hasFocus && _words.text != words) _words.text = words;
  }

  @override
  void dispose() {
    _words.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final words = _words.text.trim();
    if (words == (widget.photo['words'] as String? ?? '') || widget.model.busy) return;
    await widget.model.run('photo_words', {'name': widget.photo['name'], 'words': words}, 'Saving what the photo shows');
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photo;
    final scenes = (photo['scenes'] as List).cast<int>();
    final picture = photo['picture'] == true;
    return SizedBox(
      width: _tile,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(smallCorner),
            child: Container(
              width: _tile,
              height: 80,
              color: Graphite.raised,
              alignment: Alignment.center,
              child: picture
                  ? Image.file(File(photo['path'] as String), width: _tile, height: 80, fit: BoxFit.contain, cacheWidth: 250,
                      errorBuilder: (_, _, _) => const SizedBox.shrink())
                  : Text(photo['kind'] == 'code' ? 'Sketch' : '3D model', style: tiny),
            ),
          ),
          const SizedBox(height: 4),
          Text(photo['name'] as String, style: mono, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(scenes.isEmpty ? 'Not used' : 'Scene ${scenes.join(', ')}', style: tiny.copyWith(color: scenes.isEmpty ? Graphite.faint : Graphite.text)),
          if (picture)
            TextField(
              controller: _words,
              focusNode: _focus,
              style: small,
              maxLength: 60,
              decoration: InputDecoration(
                hintText: 'What it shows',
                isDense: true,
                helperText: photo['by'] == 'model' ? 'Described by the photo model' : null,
                helperStyle: tiny,
              ),
              buildCounter: nearLimitCounter,
              onSubmitted: (_) => _save(),
            ),
        ],
      ),
    );
  }
}

class _LinkDialog extends StatefulWidget {
  const _LinkDialog();

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  final _link = TextEditingController();

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  void _use() {
    final link = _link.text.trim();
    if (link.isNotEmpty) Navigator.pop(context, link);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Use a video link as the reference'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _link,
              autofocus: true,
              style: mono.copyWith(color: Graphite.text),
              decoration: const InputDecoration(hintText: 'https://'),
              onSubmitted: (_) => _use(),
            ),
            const SizedBox(height: 10),
            const Text('Its first minute is downloaded and measured for colour and pace. Only use links you\'re allowed to download.', style: tiny),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _use, child: const Text('Use this link')),
      ],
    );
  }
}
