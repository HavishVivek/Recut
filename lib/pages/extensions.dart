import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../engine.dart';
import '../project.dart';
import '../theme.dart';
import '../ui.dart';

/// Skills and MCP servers on this Mac. Each project chooses which to use on its Assistant page.
class ExtensionsSettings extends StatelessWidget {
  const ExtensionsSettings({super.key, required this.model, required this.extensions, this.skillsKey, this.serversKey, this.stylesKey});

  final ProjectModel model;
  final Json extensions;

  /// Where each section is, so the side bar's menu can scroll to it.
  final Key? skillsKey;
  final Key? serversKey;
  final Key? stylesKey;

  List<Json> _list(String key) => ((extensions[key] as List?) ?? const []).cast<Json>();

  Future<void> _addSkillFolder() async {
    final folder = await getDirectoryPath(confirmButtonText: 'Add this skill');
    if (folder != null) await model.changeExtensions({'op': 'add_skill', 'folder': folder});
  }

  Future<void> _addSkillFile() async {
    const skills = XTypeGroup(label: 'Skill package', extensions: ['skill', 'zip']);
    final file = await openFile(acceptedTypeGroups: [skills]);
    if (file != null) await model.changeExtensions({'op': 'add_skill_file', 'path': file.path});
  }

  /// Measure up to three of a person's finished videos and keep what they share as a style.
  Future<void> _learnStyle() async {
    const videos = XTypeGroup(label: 'Videos', extensions: ['mp4', 'mov', 'm4v']);
    final files = await openFiles(acceptedTypeGroups: [videos], confirmButtonText: 'Learn from these');
    if (files.isEmpty) return;
    final first = files.first.name;
    final stem = first.contains('.') ? first.substring(0, first.lastIndexOf('.')) : first;
    await model.learnStyle('$stem style', [for (final file in files.take(3)) file.path]);
  }

  Future<void> _addServer(BuildContext context) async {
    final made = await showDialog<Json>(context: context, builder: (_) => const _ServerDialog());
    if (made != null) await model.changeExtensions({'op': 'add_server', ...made});
  }

  Widget _row(String title, String detail, Widget action) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: small.copyWith(color: Graphite.text)),
                if (detail.isNotEmpty) Text(detail, style: tiny, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 10),
          action,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = model.busy;
    final all = _list('skills');
    final skills = [for (final item in all) if (item['style'] != true) item];
    final styles = [for (final item in all) if (item['style'] == true) item];
    final servers = _list('servers');
    final claudeSkills = _list('claude_skills');
    final claudeServers = _list('claude_servers');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          key: stylesKey,
          'Styles',
          children: [
            const Text('Choose up to three of your finished videos. The app measures their colours and how fast things arrive and hold, '
                'and keeps that as a style. Turn it on for a project on the Assistant page, and new videos are made in it.', style: tiny),
            const SizedBox(height: 6),
            if (styles.isEmpty) const Text('No styles learned yet.', style: quiet),
            for (final item in styles)
              _row(item['name'] as String, item['description'] as String,
                  TextButton(onPressed: busy ? null : () => model.changeExtensions({'op': 'remove_skill', 'folder': item['folder']}), child: const Text('Remove'))),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(onPressed: busy ? null : _learnStyle, child: const Text('Learn from my videos')),
            ),
          ],
        ),
        Section(
          key: skillsKey,
          'Skills',
          children: [
            const Text('A skill is a folder with a SKILL.md, the same as Claude Code uses. It guides how the AI writes videos and reads your edits. '
                'The AI can\'t run a skill\'s scripts, so turn on an MCP server for anything that needs a program.', style: tiny),
            const SizedBox(height: 6),
            if (skills.isEmpty) const Text('No skills added yet.', style: quiet),
            for (final item in skills)
              _row(item['name'] as String, item['description'] as String,
                  TextButton(onPressed: busy ? null : () => model.changeExtensions({'op': 'remove_skill', 'folder': item['folder']}), child: const Text('Remove'))),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(onPressed: busy ? null : _addSkillFile, child: const Text('Add a .skill file')),
                OutlinedButton(onPressed: busy ? null : _addSkillFolder, child: const Text('Add a skill folder')),
              ],
            ),
            if (claudeSkills.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('From Claude Code on this Mac (${claudeSkills.length})', style: small),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final item in claudeSkills)
                      _row(item['name'] as String, item['description'] as String,
                          TextButton(onPressed: busy ? null : () => model.changeExtensions({'op': 'add_skill', 'folder': item['folder']}), child: const Text('Add'))),
                  ],
                ),
              ),
            ],
          ],
        ),
        Section(
          key: serversKey,
          'MCP servers',
          children: [
            const Text('A server is a program on this Mac that offers tools. It starts only when the AI needs it, and every tool the AI wants to use '
                'waits for you to allow it.', style: tiny),
            const SizedBox(height: 6),
            if (servers.isEmpty) const Text('No servers added yet.', style: quiet),
            for (final item in servers)
              _row(item['name'] as String, item['command'] as String,
                  TextButton(onPressed: busy ? null : () => model.changeExtensions({'op': 'remove_server', 'name': item['name']}), child: const Text('Remove'))),
            const SizedBox(height: 6),
            OutlinedButton(onPressed: busy ? null : () => _addServer(context), child: const Text('Add a server')),
            if (claudeServers.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('From Claude on this Mac', style: small),
              for (final item in claudeServers)
                _row(item['name'] as String, item['command'] as String,
                    TextButton(onPressed: busy ? null : () => model.changeExtensions({'op': 'import_server', 'name': item['name']}), child: const Text('Add'))),
            ],
          ],
        ),
      ],
    );
  }
}

class _ServerDialog extends StatefulWidget {
  const _ServerDialog();

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  final _name = TextEditingController();
  final _command = TextEditingController();
  final _args = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _command.dispose();
    _args.dispose();
    super.dispose();
  }

  void _add() {
    if (_name.text.trim().isEmpty || _command.text.trim().isEmpty) return;
    final args = _args.text.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
    Navigator.pop(context, {'name': _name.text.trim(), 'command': _command.text.trim(), 'args': args});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add an MCP server'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: _command, style: mono.copyWith(color: Graphite.text), decoration: const InputDecoration(labelText: 'Program, such as npx or python3')),
            TextField(
              controller: _args,
              minLines: 2,
              maxLines: 5,
              style: mono.copyWith(color: Graphite.text),
              decoration: const InputDecoration(labelText: 'Arguments, one per line'),
            ),
            const SizedBox(height: 10),
            const Text('Only add servers you trust. A server runs as you, and can do anything you can on this Mac.', style: tiny),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _add, child: const Text('Add server')),
      ],
    );
  }
}

/// Which skills and servers this project's AI uses. Off by default, so nothing joins a project unasked.
class ProjectExtensions extends StatelessWidget {
  const ProjectExtensions({super.key, required this.model});

  final ProjectModel model;

  @override
  Widget build(BuildContext context) {
    final extensions = (model.state?['extensions'] as Json?) ?? const {};
    final skills = ((extensions['skills'] as List?) ?? const []).cast<Json>();
    final servers = ((extensions['servers'] as List?) ?? const []).cast<Json>();
    return Section(
      'Skills and tools',
      children: [
        if (skills.isEmpty && servers.isEmpty) const Text('Add skills and MCP servers in Settings, then turn them on here for this project.', style: tiny),
        for (final item in skills)
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(item['name'] as String, style: small),
            value: item['on'] == true,
            onChanged: model.busy ? null : (on) => model.changeAssistant('use_skill', {'folder': item['folder'], 'on': on}, 'Changing skills'),
          ),
        for (final item in servers)
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(item['name'] as String, style: small),
            subtitle: const Text('MCP server. Each tool asks you first.', style: tiny),
            value: item['on'] == true,
            onChanged: model.busy ? null : (on) => model.changeAssistant('use_server', {'name': item['name'], 'on': on}, 'Changing tools'),
          ),
      ],
    );
  }
}
