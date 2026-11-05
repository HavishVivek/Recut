import 'package:flutter/material.dart';

import '../engine.dart';
import '../project.dart';
import '../ui.dart';

/// Brings one clip from a folder into the open project. A project holds one clip, so a
/// folder with several asks which. The file is referenced, so it stays where it is.
Future<void> importFrom(BuildContext context, ProjectModel model, String folder) async {
  final seen = await model.inspect(folder);
  if (seen == null) return;
  final videos = (seen['videos'] as List).cast<Json>();
  if (videos.isEmpty) {
    model.complain('There are no videos in that folder.');
    return;
  }
  if (!context.mounted) return;
  final chosen = videos.length == 1 ? videos.single : await _pick(context, seen['name'] as String, videos);
  if (chosen != null) await model.run('add_clip', {'path': chosen['path']}, 'Adding the clip');
}

Future<Json?> _pick(BuildContext context, String folder, List<Json> videos) {
  String size(num bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  return showDialog<Json>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Choose a clip from $folder'),
      content: SizedBox(
        width: 520,
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('A project holds one clip. The rest stay in the folder, and nothing is copied.', style: quiet),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                children: [
                  for (final video in videos)
                    ListTile(
                      dense: true,
                      title: Text(video['name'] as String, style: small, overflow: TextOverflow.ellipsis),
                      trailing: Text(size(video['size'] as num), style: tiny),
                      onTap: () => Navigator.pop(context, video),
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
