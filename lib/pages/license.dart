import 'package:flutter/material.dart';

import '../engine.dart';
import '../motion.dart';
import '../project.dart';
import '../theme.dart';
import '../ui.dart';

/// Pro, Free, or a developer's build. A key is checked by the engine on this Mac, and nothing is sent anywhere.
class LicenseSettings extends StatefulWidget {
  const LicenseSettings({super.key, required this.model});

  final ProjectModel model;

  @override
  State<LicenseSettings> createState() => _LicenseSettingsState();
}

class _LicenseSettingsState extends State<LicenseSettings> {
  final _key = TextEditingController();
  String? _problem;
  bool _sending = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _change(Future<Json> Function() asking) async {
    setState(() {
      _sending = true;
      _problem = null;
    });
    try {
      widget.model.settings = await asking();
      _key.clear();
    } on EngineError catch (error) {
      _problem = error.message;
    } catch (error) {
      _problem = '$error';
    }
    if (mounted) setState(() => _sending = false);
    widget.model.notifyAfterChange();
  }

  @override
  Widget build(BuildContext context) {
    final view = (widget.model.settings?['license'] as Json?) ?? const {'tier': 'developer'};
    final tier = view['tier'] as String;
    final license = view['license'] as Json?;
    return Section(
      'License',
      children: [
        Swap(
          child: switch (tier) {
            'pro' => Row(
              key: const ValueKey('pro'),
              children: [
                const DrawnCheck(size: 14),
                const SizedBox(width: 8),
                Expanded(child: Text('Pro, for ${license?['licensee']}. Updates until ${license?['updates_until']}.', style: small)),
                TextButton(onPressed: _sending ? null : () => _change(widget.model.api.removeLicense), child: const Text('Remove key')),
              ],
            ),
            'free' => const Text(
              'Free: plan, review, edit by asking, preview and build to Resolve, on one clip. Pro adds shorts, music, b-roll, new videos, '
              'Learn my style, skills and MCP servers, more than one clip in a cut, and MP4 export.',
              key: ValueKey('free'),
              style: quiet,
            ),
            _ => const Text('A developer\'s build, so everything is on.', key: ValueKey('developer'), style: quiet),
          },
        ),
        if (tier == 'free') ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _key,
                  style: mono.copyWith(color: Graphite.text),
                  decoration: const InputDecoration(hintText: 'Paste your key, starting with AIE1-'),
                  onSubmitted: (_) => _change(() => widget.model.api.addLicense(_key.text)),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _sending ? null : () => _change(() => widget.model.api.addLicense(_key.text)), child: const Text('Add key')),
            ],
          ),
        ],
        if (_problem != null) Padding(padding: const EdgeInsets.only(top: 8), child: Alert(_problem!, color: bad)),
        const SizedBox(height: 8),
        const Text('The key is checked on this Mac. There\'s no account, and nothing is sent anywhere.', style: tiny),
      ],
    );
  }
}
