import 'package:flutter/material.dart';

import '../engine.dart';
import '../project.dart';
import '../ui.dart';

class ActivityPage extends StatelessWidget {
  const ActivityPage({super.key, required this.model, required this.onShowPlan});

  final ProjectModel model;
  final ValueChanged<String> onShowPlan;

  Widget _revisions() {
    final plans = model.plans;
    return Section(
      'Revision history',
      children: [
        if (plans.isEmpty) const Text('No plans yet', style: quiet),
        for (final item in plans.reversed)
          InkWell(
            onTap: () => onShowPlan(item['id'] as String),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(width: 56, child: Text((item['id'] as String).replaceFirst('pln_', ''), style: small)),
                  Expanded(child: Text(item['timeline'] as String, style: mono)),
                  if (item['base'] != null) Text('from ${(item['base'] as String).replaceFirst('pln_', '')}  ', style: tiny),
                  if ((item['stale'] as List).isNotEmpty) ...[const Tag('out of date', color: waiting), const SizedBox(width: 6)],
                  Text(item['state'] as String? ?? item['review'] as String? ?? 'proposed', style: mono),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _assets(Json activity) {
    final assets = (activity['assets'] as List).cast<Json>();
    final versions = (activity['versions'] as List).cast<Json>();
    return Section(
      'Assets and versions',
      children: [
        const Text('Resolve and EffectCraft share these IDs. Nothing else connects them.', style: quiet),
        const SizedBox(height: 8),
        for (final item in assets)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(width: 130, child: Text(item['id'] as String, style: mono)),
                SizedBox(width: 80, child: Text(item['kind'] as String, style: tiny)),
                Expanded(child: Text(item['name'] as String? ?? '', style: tiny, overflow: TextOverflow.ellipsis)),
                Text(_short(item['hash'] as String?), style: mono),
              ],
            ),
          ),
        if (versions.isNotEmpty) const SizedBox(height: 10),
        for (final item in versions)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(width: 130, child: Text('${item['asset']} r${item['rev']}', style: mono)),
                Expanded(child: Text('${item['frames']} frames, ${(item['details'] as Json)['tool'] ?? ''}', style: tiny)),
                if (item['stale'] == true) const Tag('out of date', color: waiting),
                RevealButton(() => reveal('${item['path']}/comp.ecproj'), label: 'Show'),
              ],
            ),
          ),
      ],
    );
  }

  Widget _models(Json activity) {
    final calls = (activity['model_calls'] as List).cast<Json>();
    final tokensIn = calls.fold<int>(0, (total, item) => total + (item['prompt_tokens'] as int));
    final tokensOut = calls.fold<int>(0, (total, item) => total + (item['output_tokens'] as int));
    final seconds = calls.fold<num>(0, (total, item) => total + (item['seconds'] as num));
    return Section(
      'Model calls',
      children: [
        Text(
          calls.isEmpty
              ? 'None yet. Everything runs on this machine, and repeated requests come from the cache.'
              : '${calls.length} calls, $tokensIn tokens in, $tokensOut out, ${seconds.toStringAsFixed(1)} s. All local.',
          style: quiet,
        ),
        if (calls.isNotEmpty) const SizedBox(height: 8),
        for (final item in calls.reversed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(width: 70, child: Text(item['purpose'] as String, style: small)),
                Expanded(
                  child: Text(
                    '${item['attempts']} tries, ${item['prompt_tokens']} in, ${item['output_tokens']} out, '
                    '${(item['seconds'] as num).toStringAsFixed(1)} s',
                    style: tiny,
                  ),
                ),
                Text(item['outcome'] as String, style: tiny),
              ],
            ),
          ),
      ],
    );
  }

  Widget _log(Json activity) {
    final events = (activity['events'] as List).cast<Json>();
    return Section(
      'Action log',
      children: [
        for (final item in events.reversed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 74, child: Text(_time(item['at'] as String), style: mono)),
                Expanded(child: SelectableText(item['message'] as String, style: small)),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!model.isOpen) return const Empty('Open a project first');
    final activity = model.activity!;
    return ListView(
      children: [
        Heading(
          'Activity',
          'Everything that changed something, and why',
          trailing: TextButton(onPressed: model.busy ? null : model.refresh, child: const Text('Refresh')),
        ),
        _revisions(),
        _assets(activity),
        _models(activity),
        _log(activity),
      ],
    );
  }
}

String _short(String? hash) => hash == null ? '' : hash.substring(0, 12);

/// Stored in UTC, shown as this machine's time of day.
String _time(String stamp) {
  final local = DateTime.parse(stamp).toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
