import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../engine.dart';
import '../project.dart';
import '../ui.dart';
import 'import.dart';

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({
    super.key,
    required this.model,
    required this.visible,
    required this.onOpened,
  });

  final ProjectModel model;
  final bool visible;
  /// Told whether the project has footage, so it can open on the page that's useful first.
  final void Function(bool withFootage) onOpened;

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  Json? _listing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ProjectsPage old) {
    super.didUpdateWidget(old);
    if (widget.visible && !old.visible) _load();
  }

  Future<void> _load() async {
    try {
      final found = await widget.model.api.projects();
      if (mounted) setState(() => _listing = found);
    } on EngineError catch (error) {
      widget.model.complain('$error');
    }
  }

  /// `footage` and `name` come filled in when someone picked a folder of clips.
  Future<void> _create({String? footage, String? name}) async {
    final made = await showDialog<_NewProject>(
      context: context,
      builder: (_) => _NewProjectDialog(location: _listing?['folder'] as String? ?? '', footage: footage, name: name),
    );
    if (made == null) return;
    final opened = await widget.model.create(made.name, location: made.location, footage: made.footage);
    await _load();
    if (!opened) return;
    // Footage can come any time, so an empty project opens where work starts without it.
    widget.onOpened(made.footage != null);
    if (made.footage != null && mounted) await importFrom(context, widget.model, made.footage!);
  }

  /// A project opens. A folder of clips starts a new project from it.
  Future<void> _openFolder() async {
    final path = await getDirectoryPath(confirmButtonText: 'Choose');
    if (path == null) return;
    final seen = await widget.model.inspect(path);
    if (seen == null) return;
    if (seen['is_project'] == true) {
      await _open(path);
    } else if ((seen['videos'] as List).isNotEmpty) {
      await _create(footage: path, name: seen['name'] as String);
    } else {
      widget.model.complain('That folder has no project and no videos in it.');
    }
  }

  Future<void> _open(String path) async {
    final opened = await widget.model.open(path);
    await _load();
    if (opened) widget.onOpened(widget.model.footage != null);
  }

  Future<void> _reviewPage() async {
    try {
      await openInBrowser(await widget.model.api.reviewPage());
    } on EngineError catch (error) {
      widget.model.complain('$error');
    }
  }

  Widget _current(ProjectModel model) {
    final report = model.report!;
    final footage = model.footage;
    final missing = (report['missing'] as List).cast<Json>();
    final stale = (model.state?['stale_titles'] as List? ?? const []).cast<Json>();
    return Section(
      report['stem'] as String,
      trailing: TextButton(
        onPressed: model.busy
            ? null
            : () async {
                await model.close();
                await _load();
              },
        child: const Text('Close project'),
      ),
      children: [
        Fact('Folder', report['root'] as String, exact: true),
        Fact('Clip', footage?['name'] as String? ?? 'None yet'),
        Fact('Original', footage?['path'] as String? ?? 'Referenced in place when added. Never copied or changed.', exact: footage != null),
        if (footage != null) Fact('Content hash', footage['hash'] as String, exact: true),
        Fact('Proxy', footage?['proxy'] as String? ?? 'Made after analysis', exact: footage?['proxy'] != null),
        Fact('Revisions', '${model.plans.length}'),
        Fact('Manifest', report['manifest'] as String, exact: true),
        const SizedBox(height: 10),
        if (missing.isEmpty)
          const Status('All media is where it was registered', good)
        else
          for (final item in missing)
            Alert('Missing media. The ${item['kind']} ${item['id']}: ${item['reason']}.', color: bad),
        for (final item in stale)
          Alert('Out of date. ${item['id']}: ${item['reason']}.'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            RevealButton(() => reveal(report['root'] as String), label: 'Show folder'),
            RevealButton(() => reveal(report['manifest'] as String), label: 'Show manifest'),
            TextButton(onPressed: _reviewPage, child: const Text('Open review page in browser')),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final projects = ((_listing?['projects'] as List?) ?? const []).cast<Json>();
    final open = _listing?['open'];
    return ListView(
      children: [
        Heading(
          'Projects',
          _listing == null
              ? 'Looking for projects. If macOS asks for access to your drive, choose Allow.'
              : 'New projects go in ${_listing!['folder']} unless you choose another place',
          trailing: Wrap(
            spacing: 8,
            children: [
              TextButton(onPressed: model.busy ? null : _openFolder, child: const Text('Open folder')),
              FilledButton(onPressed: model.busy ? null : _create, child: const Text('New project')),
            ],
          ),
        ),
        if (model.isOpen) _current(model),
        if (_listing != null && projects.isEmpty)
          const Text('No projects yet. Make one to start.', style: quiet),
        for (final item in projects.where((item) => item['path'] != open))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item['name'] as String, style: const TextStyle(fontWeight: FontWeight.w500)),
                        const SizedBox(height: 2),
                        Text(item['path'] as String, style: mono),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: model.busy ? null : () => _open(item['path'] as String),
                    child: const Text('Open'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _NewProject {
  const _NewProject(this.name, this.location, this.footage);

  final String name;
  final String location;
  final String? footage;
}

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog({required this.location, this.footage, this.name});

  final String location;
  final String? footage;
  final String? name;

  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  late final _name = TextEditingController(text: widget.name);
  late String _location = widget.location;
  late String? _footage = widget.footage;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// The engine refuses this too. Catching it here keeps what's been filled in.
  bool get _insideFootage {
    final footage = _footage;
    return footage != null && (_location == footage || _location.startsWith('$footage/'));
  }

  void _finish() {
    final name = _name.text.trim();
    if (name.isNotEmpty && !_insideFootage) Navigator.pop(context, _NewProject(name, _location, _footage));
  }

  Future<void> _chooseLocation() async {
    final path = await getDirectoryPath(initialDirectory: _location, confirmButtonText: 'Save here');
    if (path != null) setState(() => _location = path);
  }



  Widget _place(String label, String value, String action, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          SizedBox(width: 92, child: Text(label, style: quiet)),
          Expanded(child: Tooltip(message: value, child: Text(endOfPath(value), style: small, maxLines: 2))),
          const SizedBox(width: 8),
          TextButton(onPressed: onPressed, child: Text(action)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New project'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              onSubmitted: (_) => _finish(),
              decoration: const InputDecoration(labelText: 'Project name', border: OutlineInputBorder()),
            ),
            _place('Save in', _location, 'Change', _chooseLocation),
            // Only a project started from a folder of clips brings footage. Otherwise it's added any time, on Footage.
            if (_footage != null) _place('Footage', _footage!, 'Don\'t import', () => setState(() => _footage = null)),
            if (_insideFootage) ...[
              const SizedBox(height: 10),
              const Alert('Save the project outside the footage folder, so nothing is ever written beside your originals.'),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ValueListenableBuilder(
          valueListenable: _name,
          builder: (_, value, _) => FilledButton(
            onPressed: value.text.trim().isEmpty || _insideFootage ? null : _finish,
            child: const Text('Create'),
          ),
        ),
      ],
    );
  }
}
