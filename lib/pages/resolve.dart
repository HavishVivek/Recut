import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../engine.dart';
import '../motion.dart';
import '../project.dart';
import '../theme.dart';
import '../ui.dart';
import 'approve.dart';

const _working = {'QUEUED', 'RENDERING_ASSETS', 'ASSETS_READY', 'APPLYING', 'VERIFYING'};
const _stepNames = {
  'check_hand_edits': 'Check for hand edits',
  'build_timeline': 'Build the timeline',
  'verify_timeline': 'Read it back and compare',
  'save_project': 'Save the Resolve project',
};

class ResolvePage extends StatefulWidget {
  const ResolvePage({super.key, required this.model, required this.visible});

  final ProjectModel model;
  final bool visible;

  @override
  State<ResolvePage> createState() => _ResolvePageState();
}

class _ResolvePageState extends State<ResolvePage> {
  Json? _check;
  Json? _readBack;
  String? _readBackPlan;

  @override
  void didUpdateWidget(ResolvePage old) {
    super.didUpdateWidget(old);
    final model = widget.model;
    if (widget.visible && !old.visible && _check == null && model.isOpen && !model.busy) {
      // This runs during a build, and starting a job changes what the shell shows.
      WidgetsBinding.instance.addPostFrameCallback((_) => _runCheck());
    }
  }

  Future<void> _runCheck() async {
    final outcome = await widget.model.run('resolve_check', {}, 'Asking Resolve what it can do', quiet: true);
    if (mounted) setState(() => _check = outcome?['result'] as Json?);
  }

  Future<void> _readTimeline() async {
    final id = widget.model.planId!;
    final outcome = await widget.model.run('read_back', {'plan': id}, 'Reading the timeline from Resolve', quiet: true);
    if (mounted) {
      setState(() {
        _readBack = outcome?['result'] as Json?;
        _readBackPlan = id;
      });
    }
  }

  Widget _capabilities() {
    final check = _check;
    final model = widget.model;
    final capabilities = ((check?['capabilities'] as List?) ?? const []).cast<Json>();
    return Section(
      'What this install can do',
      trailing: TextButton(onPressed: model.busy ? null : _runCheck, child: Text(check == null ? 'Check Resolve' : 'Check again')),
      children: [
        if (check == null)
          const Text('Only reads. Resolve stays on whatever it has open.', style: quiet)
        else ...[
          Fact('Resolve', '${check['product']}, ${check['version']}'),
          Fact('Open project', check['project'] as String? ?? 'None, or a dialog is in the way'),
          Fact('This project is', check['wanted_project'] as String),
          Fact('Page', check['page'] as String? ?? 'Unknown. A dialog may be blocking it'),
          const SizedBox(height: 8),
          for (final item in capabilities)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 104,
                    child: Status(item['status'] as String, item['status'] == 'verified' ? good : (item['status'] == 'absent' ? Graphite.faint : waiting)),
                  ),
                  Expanded(child: Text(item['id'] as String, style: mono)),
                  Expanded(child: Text(item['evidence'] as String, style: tiny)),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _stepRow(Json step) {
    final state = step['state'] as String;
    final name = step['name'] as String;
    final color = switch (state) {
      'succeeded' => good,
      'failed' || 'unknown' => bad,
      'running' => waiting,
      _ => Graphite.faint,
    };
    final label = name.startsWith('motion:') ? 'Render the title in EffectCraft' : (_stepNames[name] ?? name);
    final extra = step['reused'] == true ? 'reused' : (step['items'] != null ? '${step['items']} items match' : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 8),
            child: SizedBox.square(
              dimension: 14,
              child: Swap(
                alignment: Alignment.center,
                child: _StepMark(state, color, key: ValueKey(state)),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: small),
                if (step['error'] != null) Text(step['error'] as String, style: const TextStyle(fontSize: 12, color: bad)),
              ],
            ),
          ),
          if (extra != null)
            Swap(
              alignment: Alignment.centerRight,
              child: Text(extra, key: ValueKey(extra), style: tiny),
            ),
          const SizedBox(width: 10),
          Swap(
            alignment: Alignment.centerRight,
            child: Text(state, key: ValueKey(state), style: tiny),
          ),
        ],
      ),
    );
  }

  Widget _buttons(Json plan) {
    final model = widget.model;
    final id = plan['id'] as String;
    final run = plan['run'] as Json?;
    final state = run?['state'] as String?;
    void resume() => model.run('approve', {'plan': id, 'by': reviewer}, 'Resuming', cancellable: true);

    if (model.busy) return const SizedBox.shrink();
    if (state == null || state == 'AWAITING_APPROVAL') {
      return FilledButton(onPressed: () => approvePlan(context, model), child: const Text('Approve and build'));
    }
    if (state == 'APPLIED') {
      return FilledButton(
        onPressed: () => model.run('render', {'plan': id, 'by': reviewer}, 'Rendering the final video'),
        child: Text(plan['rendered'] == null ? 'Render final' : 'Render final again'),
      );
    }
    if (state == 'CANCELLED') {
      return FilledButton(onPressed: () => approvePlan(context, model), child: const Text('Run again'));
    }
    if (state == 'UNKNOWN_OUTCOME') {
      return Wrap(
        spacing: 8,
        children: [
          FilledButton(onPressed: resume, child: const Text('Look again')),
          TextButton(onPressed: () => model.run('settle', {'plan': id, 'by': reviewer, 'happened': true}, 'Carrying on'), child: const Text('It did happen')),
          TextButton(
            onPressed: () => model.run('settle', {'plan': id, 'by': reviewer, 'happened': false}, 'Running that step again'),
            child: const Text("It didn't happen"),
          ),
        ],
      );
    }
    if (run?['hand_edited'] == true) {
      return FilledButton(
        onPressed: () => model.run('skip_hand_edits', {'plan': id, 'by': reviewer}, 'Rebuilding without the hand edits', cancellable: true),
        child: const Text('Continue without those edits'),
      );
    }
    if (state == 'STALE') return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      children: [
        FilledButton(onPressed: resume, child: const Text('Resume')),
        TextButton(onPressed: () => model.cancelPlan(id), child: const Text('Cancel it')),
      ],
    );
  }

  Widget _run(Json plan) {
    final run = plan['run'] as Json?;
    final state = run?['state'] as String?;
    final steps = ((run?['steps'] as List?) ?? const []).cast<Json>();
    final approvals = ((run?['approvals'] as List?) ?? const []).cast<Json>();
    final interrupted = _working.contains(state) && !widget.model.busy;
    return Section(
      'Build ${(plan['id'] as String).replaceFirst('pln_', '')} as ${plan['timeline']}',
      children: [
        if (run == null)
          const Text('Nothing has reached Resolve yet. Every build makes a new timeline, and earlier ones stay.', style: quiet)
        else ...[
          Row(children: [Status(state!, state == 'APPLIED' ? good : (state == 'CANCELLED' ? Graphite.muted : waiting))]),
          if (run['reason'] != null) ...[const SizedBox(height: 8), Alert(run['reason'] as String)],
          if (interrupted) const Alert('This run stopped part-way. Resuming looks at what really happened before doing anything.'),
          if (state == 'CANCELLED') const Alert('Cancelled. Anything partly built is kept in Resolve with __partial on its name.'),
          if (state == 'STALE') const Alert('The plan changed after this run started. Make a new revision on the Review page.'),
          const SizedBox(height: 8),
          for (final step in steps) _stepRow(step),
          if (approvals.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final row in approvals) Text('${(row['action'] as String).replaceAll('_', ' ')}, by ${row['approved_by']}', style: tiny),
          ],
        ],
        if (plan['rendered'] != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [const Status('Final render checked, frame count matches', good), const Spacer(), RevealButton(() => reveal(plan['rendered'] as String))],
          ),
        ],
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerLeft, child: _buttons(plan)),
      ],
    );
  }

  Widget _reading(Json plan) {
    final model = widget.model;
    final seen = _readBackPlan == plan['id'] ? _readBack : null;
    final problems = ((seen?['problems'] as List?) ?? const []).cast<String>();
    final items = ((seen?['items'] as List?) ?? const []).cast<Json>();
    final counts = <String, int>{};
    for (final item in items) {
      final key = '${item['kind']} ${item['track']}';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return Section(
      'Timeline in Resolve',
      trailing: TextButton(onPressed: model.busy || plan['run'] == null ? null : _readTimeline, child: const Text('Read it now')),
      children: [
        if (seen == null)
          Text(plan['run'] == null ? 'Build this plan first.' : 'Reads the timeline back and compares it with the plan. Read-back is the truth.', style: quiet)
        else ...[
          if (problems.isEmpty) const Status('Matches the plan exactly', good),
          for (final problem in problems) Alert(problem, color: bad),
          if (seen['hand_edited'] == true) const Alert('Someone changed this timeline by hand since it was verified.'),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final item in counts.entries) Tag('${item.key}: ${item.value}')]),
          if (seen['names'] != null) ...[const SizedBox(height: 8), Text('Timelines: ${(seen['names'] as List).join(', ')}', style: tiny)],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    if (!model.isOpen) return const Empty('Open a project first');
    final plan = model.plan;
    return ListView(
      children: [
        const Heading('Resolve', 'Each build is a new timeline, checked by reading it back'),
        _capabilities(),
        if (plan == null)
          const Text('Make a plan on the Review page first.', style: quiet)
        else ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in model.plans)
                  Padding(
                    padding: const EdgeInsets.only(right: 6, bottom: 10),
                    child: ChoiceChip(
                      label: Text((item['id'] as String).replaceFirst('pln_', ''), style: small),
                      selected: item['id'] == model.planId,
                      onSelected: model.busy ? null : (_) => model.selectPlan(item['id'] as String),
                    ),
                  ),
              ],
            ),
          ),
          _run(plan),
          _reading(plan),
        ],
      ],
    );
  }
}

/// A step's mark. Done draws a tick, so the read-back that proves the build is seen to finish.
/// Running is a hollow ring rather than a spinner: the status bar already moves.
class _StepMark extends StatelessWidget {
  const _StepMark(this.state, this.color, {super.key});

  final String state;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      'succeeded' => DrawnCheck(size: 14, color: color),
      'failed' || 'unknown' => PhosphorIcon(PhosphorIconsBold.x, size: 12, color: color),
      'running' => Center(
        child: Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.6),
          ),
        ),
      ),
      _ => Center(child: Dot(color)),
    };
  }
}
