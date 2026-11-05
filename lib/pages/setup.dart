import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../engine.dart';
import '../motion.dart';
import '../theme.dart';
import '../ui.dart';

/// What this Mac has, and the one step that fixes anything missing. It opens first until the
/// required pieces are ready. Nothing downloads until a person presses that row's button.
class SetupPage extends StatefulWidget {
  const SetupPage({super.key, required this.api, this.pollEvery = const Duration(seconds: 1)});

  final Api? api;
  final Duration pollEvery;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  Json? _view;
  String? _problem;
  bool _checking = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    if (widget.api != null) _check();
  }

  @override
  void didUpdateWidget(SetupPage old) {
    super.didUpdateWidget(old);
    if (old.api == null && widget.api != null) _check();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  bool get _working => (_view?['job'] as Json?)?['running'] == true || (_view?['download'] as Json?)?['running'] == true;

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final found = await widget.api!.setup();
      if (mounted) setState(() => _view = found);
    } on EngineError catch (error) {
      if (mounted) setState(() => _problem = error.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
    _follow();
  }

  /// While something downloads, read its progress; stop once it's finished.
  void _follow() {
    _poll?.cancel();
    if (!_working || !mounted) return;
    _poll = Timer(widget.pollEvery, _check);
  }

  Future<void> _act(String action, [Json body = const {}]) async {
    setState(() => _problem = null);
    try {
      final found = await widget.api!.setupAction(action, body);
      if (mounted) setState(() => _view = found);
    } on EngineError catch (error) {
      if (mounted) setState(() => _problem = error.message);
    }
    _follow();
  }

  Future<void> _press(Json row, String action) async {
    if (action == 'open_ollama_site') {
      await Process.run('open', [row['link'] as String]);
      return;
    }
    if (action == 'choose_cli') {
      final file = await openFile();
      if (file == null) return;
      return _act(action, {'path': file.path});
    }
    return _act(action);
  }

  Widget _progress(Json job) {
    final total = (job['total'] as num?) ?? 0;
    final completed = (job['completed'] as num?) ?? 0;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          total > 0
              ? TweenAnimationBuilder<double>(
                  tween: Tween(end: completed / total),
                  duration: Motion.reduced(context) ? Duration.zero : widget.pollEvery,
                  builder: (context, value, _) => LinearProgressIndicator(value: value, minHeight: 3),
                )
              : const LinearProgressIndicator(minHeight: 3),
          const SizedBox(height: 4),
          Swap(child: Text('${job['stage']}', key: ValueKey(job['stage']), style: tiny)),
        ],
      ),
    );
  }

  Widget _row(Json row) {
    final ready = row['ready'] == true;
    final required = row['required'] == true;
    final actions = (row['actions'] as List).cast<Json>();
    final job = _view?['job'] as Json?;
    final download = _view?['download'] as Json?;
    final busy = (row['id'] == 'speech' && job?['running'] == true) || (row['id'] == 'ollama' && download?['running'] == true);
    final failed = switch (row['id']) {
      'speech' => job?['error'] as String?,
      'ollama' => download?['error'] as String?,
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(row['name'] as String, style: const TextStyle(fontWeight: FontWeight.w500)),
                          if (!required) ...[const SizedBox(width: 8), const Tag('optional')],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(row['detail'] as String, style: quiet),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (!ready && !busy)
                  for (final action in actions)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilledButton(onPressed: _working ? null : () => _press(row, action['id'] as String), child: Text(action['label'] as String)),
                    ),
                if (busy && row['id'] == 'speech') TextButton(onPressed: () => _act('cancel'), child: const Text('Cancel')),
                Swap(
                  alignment: Alignment.centerRight,
                  child: ready
                      ? const Row(key: ValueKey('ready'), mainAxisSize: MainAxisSize.min, children: [DrawnCheck(size: 13), SizedBox(width: 6), Text('Ready', style: small)])
                      : Status(busy ? 'Working' : required ? 'Needs action' : 'Not set up', waiting, key: ValueKey(busy ? 'busy' : 'needs')),
                ),
              ],
            ),
            if (busy) _progress(row['id'] == 'speech' ? job! : download!),
            if (failed != null && !busy) Padding(padding: const EdgeInsets.only(top: 8), child: Alert(failed, color: bad)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    final rows = ((view?['rows'] as List?) ?? const []).cast<Json>();
    return ListView(
      children: [
        Heading(
          'Setup',
          view == null
              ? 'What the editor can reach on this Mac'
              : view['ready'] == true
              ? 'Everything the editor needs is here.'
              : 'A few things are missing. Each button fixes one, and nothing downloads until you press it.',
          trailing: TextButton(onPressed: widget.api == null || _checking ? null : _check, child: Text(_checking ? 'Checking' : 'Check again')),
        ),
        if (view == null) const Text('Waiting for the engine', style: TextStyle(color: Graphite.muted)),
        if (_problem != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Alert(_problem!, color: bad)),
        for (final (index, row) in rows.indexed) Arrive(key: ValueKey(('setup', row['id'])), delay: Duration(milliseconds: 40 * index), child: _row(row)),
      ],
    );
  }
}
