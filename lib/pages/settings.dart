import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../engine.dart';
import '../motion.dart';
import '../project.dart';
import '../theme.dart';
import '../ui.dart';
import 'assistant.dart';
import 'extensions.dart';
import 'hugging_face.dart';
import 'license.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.model, required this.visible, this.section});

  final ProjectModel model;
  final bool visible;

  /// A section chosen from the side bar's menu, to scroll to.
  final ValueListenable<String?>? section;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _places = {
    for (final id in ['models', 'huggingface', 'project', 'styles', 'skills', 'servers', 'license', 'account', 'ollama', 'about']) id: GlobalKey(),
  };

  /// Models listed when the page first had any. One that arrives later, from a download, moves in.
  Set<String>? _knownModels;

  @override
  void initState() {
    super.initState();
    widget.section?.addListener(_show);
  }

  @override
  void dispose() {
    widget.section?.removeListener(_show);
    super.dispose();
  }

  /// Scroll to the chosen section once it's built. Settings may still be loading the first time.
  void _show([int tries = 0]) {
    final id = widget.section?.value;
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final place = _places[id]?.currentContext;
      if (place != null) {
        Scrollable.ensureVisible(place, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
      } else if (tries < 20 && mounted) {
        Future<void>.delayed(const Duration(milliseconds: 100), () => _show(tries + 1));
      }
    });
  }

  Widget _at(String id, Widget child) => KeyedSubtree(key: _places[id], child: child);

  @override
  void didUpdateWidget(SettingsPage old) {
    super.didUpdateWidget(old);
    if (widget.visible && !old.visible) {
      // This runs during a build, and loading tells the shell to rebuild.
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.model.loadSettings());
    }
  }

  String _size(num bytes) => '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';

  Widget _models(Json settings) {
    final model = widget.model;
    final models = (settings['models'] as List).cast<Json>();
    final fallback = settings['default_model'] as String;
    final planning = settings['planning_model'] as String;
    final names = {for (final item in models) item['name'] as String};
    // Nothing to compare with until Ollama has listed something.
    if (_knownModels == null && names.isNotEmpty) _knownModels = names;
    final known = _knownModels ?? names;
    return Section(
      'AI model',
      children: [
        const Text('The default is what any project set to Same as default uses. Each project can choose its own on its Assistant page.', style: quiet),
        const SizedBox(height: 10),
        if (models.isEmpty) const Text('No models found. Start Ollama, then look again.', style: quiet),
        for (final item in models)
          Arrive(
            key: ValueKey(('model', item['name'])),
            play: known.add(item['name'] as String),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Dot(item['name'] == fallback ? good : Graphite.lineStrong),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(item['name'] as String, style: mono.copyWith(color: Graphite.text)),
                  ),
                  Text('${item['parameters']}, ${_size(item['size'] as num)}', style: mono),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 110,
                    child: item['name'] == fallback
                        ? const Center(child: Tag('default', color: good))
                        : TextButton(onPressed: model.busy ? null : () => model.setDefaultModel(item['name'] as String), child: const Text('Make default')),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text('Planning cuts and reading notes stay on $planning, the only model tested for that.', style: tiny),
        const Text('Only models on this Mac are listed. Nothing is downloaded unless you press Download under Hugging Face.', style: tiny),
      ],
    );
  }

  Widget _project() {
    final model = widget.model;
    final calls = ((model.activity?['model_calls'] as List?) ?? const []).cast<Json>();
    final tokensIn = calls.fold<int>(0, (total, item) => total + (item['prompt_tokens'] as int));
    final tokensOut = calls.fold<int>(0, (total, item) => total + (item['output_tokens'] as int));
    return Section(
      'This project: ${model.report?['stem']}',
      children: [
        ModelPicker(model: model),
        const SizedBox(height: 6),
        Text('${calls.length} model calls, $tokensIn tokens in, $tokensOut out', style: tiny),
      ],
    );
  }

  Widget _account(Json settings) {
    final user = settings['user'] as Json;
    final ollama = settings['ollama'] as Json;
    final account = ollama['account'] as Json?;
    return Section(
      'Account',
      children: [
        Fact('Name', user['name'] as String),
        Fact('Mac user', user['user'] as String, exact: true),
        const Fact('Plan', 'Local. No sign-in, subscription or API key'),
        Fact('Approvals made as', reviewer),
        Fact('Ollama account', _ollamaAccount(ollama, account)),
        const Fact('Your footage', 'Stays on this Mac. Hosted models are never offered'),
      ],
    );
  }

  String _ollamaAccount(Json ollama, Json? account) {
    if (ollama['running'] != true) return 'Unknown, because Ollama isn\'t running';
    if (ollama['signed_in'] != true) return 'Not signed in. Local models don\'t need it';
    final details = [account?['name'], account?['email'], account?['plan']].whereType<String>();
    return details.isEmpty ? 'Signed in' : 'Signed in as ${details.join(', ')}';
  }

  Widget _ollama(Json settings) {
    final ollama = settings['ollama'] as Json;
    final running = ollama['running'] == true;
    return Section(
      'Ollama',
      trailing: TextButton(onPressed: widget.model.loadSettings, child: const Text('Check Ollama')),
      children: [
        Row(children: [running ? const Status('Running on this Mac', good) : const Status('Not running', waiting)]),
        if (running) ...[const SizedBox(height: 6), Fact('Version', ollama['version'] as String? ?? 'Unknown')],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final settings = model.settings;
    return ListView(
      children: [
        const Heading('Settings', 'The AI model and your account on this Mac'),
        if (settings == null)
          const Text('Looking for models', style: quiet)
        else ...[
          _at('models', _models(settings)),
          _at('huggingface', HuggingFaceSettings(model: model)),
          if (model.isOpen) _at('project', _project()),
          if (settings['extensions'] != null)
            ExtensionsSettings(
              model: model,
              extensions: settings['extensions'] as Json,
              skillsKey: _places['skills'],
              serversKey: _places['servers'],
              stylesKey: _places['styles'],
            ),
          _at('license', LicenseSettings(model: model)),
          _at('account', _account(settings)),
          _at('ollama', _ollama(settings)),
          Section(
            key: _places['about'],
            'About',
            children: [
              const Text('Geist and Geist Mono are bundled under the SIL Open Font License. Phosphor Icons are bundled under the MIT License.', style: tiny),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => showLicensePage(context: context, applicationName: 'AI Editor'),
                  child: const Text('Licenses'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
