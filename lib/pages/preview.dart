import 'dart:io';

import 'package:flutter/material.dart';

import '../engine.dart';
import '../motion.dart';
import '../project.dart';
import '../theme.dart';
import '../ui.dart';

String _clock(num seconds) {
  final whole = seconds.round();
  return '${whole ~/ 60}:${(whole % 60).toString().padLeft(2, '0')}';
}

String _count(num value) => value >= 1000000
    ? '${(value / 1000000).toStringAsFixed(1)}M'
    : value >= 1000
    ? '${(value / 1000).toStringAsFixed(0)}k'
    : '$value';

/// Shows what a found video is before a person picks it: four stills from through it, its
/// details and its description. Only its id goes to the engine, which builds every address.
/// Returns true when they choose to use it.
Future<bool> showVideoPreview(BuildContext context, ProjectModel model, Json video, {bool canUse = true}) async {
  final chosen = await showDialog<bool>(
    context: context,
    builder: (_) => VideoPreview(model: model, video: video, canUse: canUse),
  );
  return chosen == true;
}

class VideoPreview extends StatefulWidget {
  const VideoPreview({super.key, required this.model, required this.video, this.canUse = true});

  final ProjectModel model;
  final Json video;
  final bool canUse;

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  Json? _preview;
  String? _problem;

  @override
  void initState() {
    super.initState();
    // Starting the job tells every page the project is busy, which can't happen mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final video = widget.video;
    if (widget.model.busy) {
      setState(() => _problem = 'Something else is running. Look again once it finishes.');
      return;
    }
    final outcome = await widget.model.run('preview_reference', {'id': video['id'], 'short': video['short'] == true}, 'Opening the video', quiet: true);
    if (!mounted) return;
    setState(() {
      if (outcome?['state'] == 'done') {
        _preview = outcome!['result'] as Json;
      } else {
        _problem = outcome?['error'] as String? ?? "The video couldn't be opened just now. Try again.";
      }
    });
  }

  Widget _stills(List<String> stills) {
    if (stills.isEmpty) return const Text('YouTube had no stills for this video.', style: tiny);
    return Row(
      children: [
        for (final (index, path) in stills.indexed) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(smallCorner),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(color: Graphite.raised),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _details(Json preview) {
    final facts = [
      if ((preview['channel'] as String? ?? '').isNotEmpty) preview['channel'] as String,
      '${_count(preview['views'] as num? ?? 0)} views',
      if ((preview['likes'] as num? ?? 0) > 0) '${_count(preview['likes'] as num)} likes',
      _clock(preview['seconds'] as num? ?? 0),
      if ((preview['uploaded'] as String? ?? '').isNotEmpty) preview['uploaded'] as String,
    ];
    final chapters = ((preview['chapters'] as List?) ?? const []).cast<Json>();
    final description = preview['description'] as String? ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stills(((preview['stills'] as List?) ?? const []).cast<String>()),
        const SizedBox(height: 6),
        const Text('Stills from the start, a quarter, half and three quarters of the way in.', style: tiny),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: Text(facts.join('  ·  '), style: mono, overflow: TextOverflow.ellipsis)),
            if (preview['short'] == true) const Tag('short'),
          ],
        ),
        if (chapters.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Chapters', style: quiet),
          const SizedBox(height: 4),
          for (final chapter in chapters)
            Text('${_clock(chapter['seconds'] as num)}  ${chapter['title']}', style: small, overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: 12),
        const Text('Description', style: quiet),
        const SizedBox(height: 4),
        // Plain text a person can read and copy. Nothing in it is a link.
        SelectableText(description.isEmpty ? 'No description.' : description, style: small),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final link = preview?['link'] as String?;
    return AlertDialog(
      title: Text(widget.video['title'] as String? ?? 'Video', maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 640,
        height: 440,
        child: Swap(
          alignment: Alignment.topLeft,
          child: _problem != null
              ? Align(key: const ValueKey('problem'), alignment: Alignment.topLeft, child: Alert(_problem!, color: bad))
              : preview == null
              ? const Column(
                  key: ValueKey('loading'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [LinearProgressIndicator(minHeight: 2), SizedBox(height: 8), Text('Opening the video’s details', style: quiet)],
                )
              : SingleChildScrollView(key: const ValueKey('preview'), child: _details(preview)),
        ),
      ),
      actions: [
        if (link != null) TextButton(onPressed: () => openInBrowser(link), child: const Text('Watch on YouTube')),
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close')),
        if (widget.canUse) FilledButton(onPressed: preview == null ? null : () => Navigator.pop(context, true), child: const Text('Use this')),
      ],
    );
  }
}
