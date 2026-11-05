import 'package:flutter/material.dart';

import '../engine.dart';
import '../project.dart';
import '../ui.dart';

const _meaning = {
  'apply_plan': 'Build this plan as a new timeline in Resolve. Earlier timelines stay as they are.',
  'confirm_removal': 'This removes more than 40% of the sentences. Over that limit, a person has to agree.',
  'overwrite_timeline': 'A timeline with this name is already in Resolve. If it differs from the plan, it is kept as __partial and rebuilt.',
};

List<Json> flaggedIn(Json plan) => (plan['sentences'] as List).cast<Json>().where((item) => item['note'] != null).toList();

/// Shows a person exactly what they're agreeing to. If the real gate finds more
/// once Resolve is reached, they're asked about that too, instead of it passing unseen.
Future<void> approvePlan(BuildContext context, ProjectModel model) async {
  final plan = model.plan!;
  final gate = plan['gate'] as Json?;
  var needs = ((gate?['pending'] as List?) ?? const ['apply_plan']).cast<String>();
  final flagged = flaggedIn(plan).length;
  while (true) {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Approve ${(plan['id'] as String).replaceFirst('pln_', '')}?'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final action in needs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_meaning[action] ?? action, style: small),
                ),
              if (flagged > 0) Alert('$flagged flagged ${flagged == 1 ? 'sentence is' : 'sentences are'} still in the cut.'),
              const SizedBox(height: 4),
              const Text('Resolve must be open with the bridge started.', style: quiet),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not yet')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Approve and build')),
        ],
      ),
    );
    if (yes != true) return;
    final outcome = await model.run(
      'approve',
      {'plan': plan['id'], 'by': reviewer, 'confirmed': needs},
      'Building in Resolve',
      cancellable: true,
    );
    final more = (outcome?['needs'] as List?)?.cast<String>();
    if (more == null || !context.mounted) return;
    needs = [...needs, ...more];
  }
}
