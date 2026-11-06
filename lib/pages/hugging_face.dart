import 'package:flutter/material.dart';

import '../engine.dart';
import '../motion.dart';
import '../project.dart';
import '../theme.dart';
import '../ui.dart';

/// Finds a GGUF model on Hugging Face and has Ollama download it to this Mac.
/// Once it's here it's listed with the other models, for the default or one project.
class HuggingFaceSettings extends StatefulWidget {
  const HuggingFaceSettings({super.key, required this.model, this.pollEvery = const Duration(seconds: 1)});

  final ProjectModel model;
  final Duration pollEvery;

  @override
  State<HuggingFaceSettings> createState() => _HuggingFaceSettingsState();
}

class _HuggingFaceSettingsState extends State<HuggingFaceSettings> {
  final _words = TextEditingController();
  List<Json>? _results;
  Json? _files;
  String? _tag;
  Json? _download;
  String? _problem;
  bool _looking = false;
  bool _following = false;

  Api get _api => widget.model.api;

  @override
  void initState() {
    super.initState();
    // A download outlives this page, so pick up one that's still going.
    final running = widget.model.settings?['download'] as Json?;
    if (running != null) {
      _download = running;
      if (running['running'] == true) _follow();
    }
  }

  @override
  void dispose() {
    _words.dispose();
    super.dispose();
  }

  bool get _downloading => _download?['running'] == true;

  Future<void> _look(Future<void> Function() asking) async {
    setState(() {
      _looking = true;
      _problem = null;
    });
    try {
      await asking();
    } on EngineError catch (error) {
      _problem = error.message;
    } catch (error) {
      _problem = '$error';
    }
    if (mounted) setState(() => _looking = false);
  }

  /// Words search. Anything with a slash is taken as a repository someone pasted.
  Future<void> _search() async {
    final text = _words.text.trim();
    if (text.isEmpty || _looking) return;
    if (text.contains('/')) return _choose(text);
    await _look(() async {
      _files = null;
      _results = await _api.searchModels(text);
    });
  }

  Future<void> _choose(String repo) => _look(() async {
    final files = await _api.modelFiles(repo);
    _files = files;
    _tag = files['recommended'] as String? ?? ((files['files'] as List).first as Json)['tag'] as String;
  });

  Future<void> _start() async {
    final files = _files;
    if (files == null || _downloading) return;
    await _look(() async {
      _download = await _api.downloadModel(files['repo'] as String, _tag);
    });
    if (_downloading) _follow();
  }

  /// Reads progress until it ends. Only one loop runs, however often this is called.
  Future<void> _follow() async {
    if (_following) return;
    _following = true;
    while (mounted && _downloading) {
      await Future<void>.delayed(widget.pollEvery);
      if (!mounted) break;
      try {
        final latest = await _api.modelDownload();
        if (mounted) setState(() => _download = latest);
      } on EngineError catch (error) {
        if (mounted) setState(() => _problem = error.message);
        break;
      }
    }
    _following = false;
    if (!mounted) return;
    if (_download?['done'] == true) {
      await widget.model.loadSettings();
      widget.model.say('Downloaded ${_download!['name']}');
    }
  }

  Future<void> _cancel() async {
    try {
      final latest = await _api.cancelModelDownload();
      if (mounted) setState(() => _download = {...?_download, ...latest});
    } on EngineError catch (error) {
      if (mounted) setState(() => _problem = error.message);
    }
  }

  String _size(num bytes) => bytes >= 1024 * 1024 * 1024 ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB' : '${(bytes / (1024 * 1024)).round()} MB';

  String _count(num value) => value >= 1000000
      ? '${(value / 1000000).toStringAsFixed(1)}M'
      : value >= 1000
      ? '${(value / 1000).toStringAsFixed(0)}k'
      : '$value';

  Widget _progress(Json download) {
    final total = (download['total'] as num?) ?? 0;
    final completed = (download['completed'] as num?) ?? 0;
    final error = download['error'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  download['name'] as String? ?? '',
                  style: mono.copyWith(color: Graphite.text),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_downloading) TextButton(onPressed: _cancel, child: const Text('Cancel')),
            ],
          ),
          if (_downloading) ...[
            const SizedBox(height: 6),
            // Progress arrives once a second, so the bar glides between readings instead of jumping.
            if (total > 0)
              TweenAnimationBuilder<double>(
                tween: Tween(end: completed / total),
                duration: Motion.reduced(context) ? Duration.zero : widget.pollEvery,
                builder: (context, value, _) => LinearProgressIndicator(value: value, minHeight: 3),
              )
            else
              const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: 6),
            Text(total > 0 ? '${download['stage']}, ${_size(completed)} of ${_size(total)}' : '${download['stage']}', style: tiny),
          ] else if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Alert(error, color: bad),
            )
          else if (download['cancelled'] == true)
            const Text('Cancelled. Downloading it again carries on from where it stopped.', style: tiny)
          else if (download['done'] == true)
            const Status('On this Mac. Choose it above, or for one project on its Assistant page.', good),
        ],
      ),
    );
  }

  Widget _result(Json item) {
    final repo = item['repo'] as String;
    final chosen = _files?['repo'] == repo;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _looking ? null : () => _choose(repo),
                child: Text(
                  repo,
                  style: mono.copyWith(color: Graphite.text),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          Text('${_count(item['downloads'] as num)} downloads', style: mono),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: chosen
                ? const Center(child: Tag('open', color: good))
                : TextButton(onPressed: _looking ? null : () => _choose(repo), child: const Text('Details')),
          ),
        ],
      ),
    );
  }

  String _parameters(num count) => count >= 1e9 ? '${(count / 1e9).toStringAsFixed(1)}B parameters' : '${(count / 1e6).round()}M parameters';

  /// What the model is, from its card and Hugging Face's own facts, so a person can judge it before downloading.
  Widget _about(Json about) {
    final summary = about['summary'] as String? ?? '';
    final from = about['summary_from'] as String? ?? '';
    final base = about['base_model'] as String? ?? '';
    final facts = [
      if ((about['parameters'] as num? ?? 0) > 0) _parameters(about['parameters'] as num),
      if ((about['context'] as num? ?? 0) > 0) '${_count(about['context'] as num)} context',
      if ((about['license'] as String? ?? '').isNotEmpty) 'licence ${about['license']}',
      if ((about['updated'] as String? ?? '').isNotEmpty) 'updated ${about['updated']}',
      '${_count(about['downloads'] as num? ?? 0)} downloads',
      '${_count(about['likes'] as num? ?? 0)} likes',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(facts.join('  ·  '), style: mono),
        if (about['vision'] == true) ...[
          const SizedBox(height: 6),
          const Tag('can see pictures'),
        ],
        const SizedBox(height: 8),
        if (summary.isNotEmpty) ...[
          SelectableText(summary, style: small),
          if (from.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('From the card of $from', style: tiny)),
        ] else
          Text(
            base.isNotEmpty
                ? 'Made from $base. Its card doesn’t say more without a sign-in, so open it on Hugging Face to read about it.'
                : 'Its card doesn’t say what it is. Open it on Hugging Face to read more.',
            style: quiet,
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: () => openInBrowser(about['link'] as String), child: const Text('Open on Hugging Face')),
        ),
      ],
    );
  }

  Widget _chooser(Json files) {
    final options = (files['files'] as List).cast<Json>();
    final about = files['about'] as Json?;
    final memory = files['memory'] as num? ?? 0;
    final tooBig = options.any((option) => option['fits'] == false);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${files['repo']}', style: mono.copyWith(color: Graphite.text)),
          const SizedBox(height: 6),
          if (about != null) _about(about),
          const SizedBox(height: 4),
          const Text('Smaller files are quicker and use less memory. Larger ones answer better.', style: tiny),
          if (tooBig && memory > 0)
            Text('This Mac has ${_size(memory)} of memory. A file marked too big would leave too little for everything else.', style: tiny),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final option in options)
                ChoiceChip(
                  label: Text(
                    '${option['tag']}  ${_size(option['size'] as num)}${option['fits'] == false ? '  too big' : ''}',
                    style: mono.copyWith(color: option['fits'] == false ? Graphite.amber : Graphite.text),
                  ),
                  selected: _tag == option['tag'],
                  side: BorderSide(color: _tag == option['tag'] ? Graphite.mint : Graphite.line),
                  onSelected: (_) => setState(() => _tag = option['tag'] as String),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(onPressed: _downloading || _looking ? null : _start, child: Text('Download $_tag')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final running = widget.model.settings?['ollama']?['running'] == true;
    final results = _results;
    final files = _files;
    return Section(
      'Hugging Face',
      children: [
        const Text('Find a GGUF model on Hugging Face. Ollama downloads it and runs it on this Mac, so your footage never leaves it.', style: quiet),
        const SizedBox(height: 10),
        if (_download != null) _progress(_download!),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _words,
                enabled: running,
                style: small,
                decoration: const InputDecoration(hintText: 'Search, such as llama 3b, or paste a repository'),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: running && !_looking ? _search : null, child: const Text('Search')),
          ],
        ),
        if (!running)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Start Ollama to download a model.', style: tiny),
          ),
        if (_problem != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Alert(_problem!, color: bad),
          ),
        if (results != null) ...[
          const SizedBox(height: 8),
          if (results.isEmpty) const Text('No public GGUF models matched.', style: quiet),
          for (final item in results) _result(item),
        ],
        if (files != null) _chooser(files),
        const SizedBox(height: 8),
        const Text('Only your search words or the repository go to Hugging Face. Nothing downloads until you press Download.', style: tiny),
      ],
    );
  }
}
