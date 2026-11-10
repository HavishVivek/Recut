import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../drop.dart';
import '../engine.dart';
import '../project.dart';
import '../theme.dart';
import '../ui.dart';

/// Your logo, kept for this Mac, and where new videos wear it: small in the corner, and drawn in at the end.
/// It's yours, not a project's, so every project uses it. "No brand" in a request leaves it out of that video.
class BrandKit extends StatelessWidget {
  const BrandKit({super.key, required this.model});

  final ProjectModel model;

  Json get _brand => (model.settings?['brand'] as Json?) ?? const {'logo': '', 'watermark': false, 'outro': false};

  Future<void> _change(Json body) async {
    try {
      await model.api.changeBrand(body);
      await model.loadSettings();
    } on EngineError catch (error) {
      model.complain(error.message);
    }
  }

  Future<void> _choose() async {
    const pictures = XTypeGroup(label: 'Logo', extensions: pictureExtensions);
    final file = await openFile(acceptedTypeGroups: [pictures]);
    if (file != null) await _change({'logo': file.path});
  }

  @override
  Widget build(BuildContext context) {
    final brand = _brand;
    final logo = brand['logo'] as String? ?? '';
    return Section(
      'Brand kit',
      children: [
        const Text('Your logo for new videos: small in the corner, and drawn in under the closing line. A PNG with a clear background looks best.', style: tiny),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: Graphite.raised, borderRadius: BorderRadius.circular(smallCorner), border: Border.all(color: Graphite.line)),
              alignment: Alignment.center,
              child: logo.isEmpty
                  ? const Text('No logo', style: tiny)
                  : Image.file(File(logo), width: 60, height: 60, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Text('Logo', style: tiny)),
            ),
            const SizedBox(width: 12),
            OutlinedButton(onPressed: _choose, child: Text(logo.isEmpty ? 'Choose a logo' : 'Change the logo')),
            const SizedBox(width: 8),
            if (logo.isNotEmpty) TextButton(onPressed: () => _change({'remove': true}), child: const Text('Remove')),
          ],
        ),
        if (logo.isNotEmpty) ...[
          const SizedBox(height: 6),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('In the corner of every new video', style: small),
            value: brand['watermark'] == true,
            onChanged: (on) => _change({'watermark': on}),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Drawn in at the end', style: small),
            value: brand['outro'] == true,
            onChanged: (on) => _change({'outro': on}),
          ),
        ],
      ],
    );
  }
}
