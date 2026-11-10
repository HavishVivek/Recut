import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../engine.dart';
import '../project.dart';
import '../theme.dart';
import '../ui.dart';

Color _statusColor(String status) {
  switch (status) {
    case 'connected':
      return good;
    case 'starting':
    case 'rate_limited':
    case 'auth_required':
      return waiting;
    case 'failed':
      return bad;
    case 'unavailable':
      return Graphite.faint;
    case 'configured':
    default:
      return Graphite.muted;
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'connected':
      return 'Connected';
    case 'starting':
      return 'Starting...';
    case 'rate_limited':
      return 'Rate-limited';
    case 'auth_required':
      return 'Authentication required';
    case 'unavailable':
      return 'Unavailable';
    case 'failed':
      return 'Failed';
    case 'configured':
    default:
      return 'Configured';
  }
}

Color _toolStatusColor(String status) {
  switch (status) {
    case 'available':
      return good;
    case 'rate_limited':
    case 'auth_required':
      return waiting;
    case 'failed':
      return bad;
    case 'unavailable':
      return Graphite.faint;
    case 'unknown':
    default:
      return Graphite.muted;
  }
}

String _toolStatusLabel(String status, String? retryIn) {
  switch (status) {
    case 'available':
      return 'Available';
    case 'rate_limited':
      return retryIn != null ? 'Rate-limited ($retryIn)' : 'Rate-limited';
    case 'auth_required':
      return 'Authentication required';
    case 'unavailable':
      return 'Unavailable';
    case 'failed':
      return 'Failed';
    case 'unknown':
    default:
      return 'Not tested';
  }
}

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
            const SizedBox(height: 8),
            if (servers.isEmpty) const Text('No servers added yet.', style: quiet),
            for (final item in servers)
              _McpServerCard(model: model, server: item, busy: busy),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(onPressed: busy ? null : () => _addServer(context), child: const Text('Add a server')),
            ),
            if (claudeServers.isNotEmpty) ...[
              const SizedBox(height: 12),
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

class _McpServerCard extends StatefulWidget {
  const _McpServerCard({required this.model, required this.server, required this.busy});

  final ProjectModel model;
  final Json server;
  final bool busy;

  @override
  State<_McpServerCard> createState() => _McpServerCardState();
}

class _McpServerCardState extends State<_McpServerCard> {
  bool _showTechnical = false;
  bool _testing = false;
  bool _discovering = false;

  Future<void> _testConnection() async {
    setState(() => _testing = true);
    try {
      await widget.model.changeExtensions({'op': 'test_server', 'name': widget.server['name']});
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _discoverTools() async {
    setState(() => _discovering = true);
    try {
      await widget.model.changeExtensions({'op': 'discover_tools', 'name': widget.server['name']});
    } finally {
      if (mounted) setState(() => _discovering = false);
    }
  }

  Future<void> _runTestTool(BuildContext context, Json tool) async {
    final name = widget.server['name'] as String;
    final toolName = tool['name'] as String;
    final args = await showDialog<Json>(
      context: context,
      builder: (_) => _TestToolDialog(serverName: name, tool: tool),
    );
    if (args != null) {
      await widget.model.changeExtensions({
        'op': 'test_tool',
        'name': name,
        'tool': toolName,
        'arguments': args,
      });
    }
  }

  Future<void> _addOrEditCredential(BuildContext context, {String? existingKey}) async {
    final name = widget.server['name'] as String;
    final result = await showDialog<Json>(
      context: context,
      builder: (_) => _CredentialDialog(serverName: name, existingKey: existingKey),
    );
    if (result != null) {
      await widget.model.changeExtensions({
        'op': 'add_credential',
        'name': name,
        'key': result['key'],
        'secret': result['secret'],
      });
    }
  }

  Future<void> _showMigrationPreview(BuildContext context, Json legacy) async {
    final name = widget.server['name'] as String;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _MigrationPreviewDialog(serverName: name, preview: legacy),
    );
    if (confirmed == true) {
      await widget.model.changeExtensions({
        'op': 'migrate_credentials',
        'name': name,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final server = widget.server;
    final name = server['name'] as String;
    final command = server['command'] as String? ?? '';
    final rawStatus = _testing ? 'starting' : (server['connection_status'] as String? ?? server['status'] as String? ?? 'configured');
    final plainLanguage = server['plain_language'] as String? ?? '';
    final technical = server['technical_detail'] as String? ?? '';
    final advice = server['actionable_advice'] as String? ?? '';
    final tools = ((server['tools'] as List?) ?? const []).cast<Json>();
    final credentials = (server['credentials'] as Json?) ?? const {};
    final legacy = server['legacy_migration'] as Json?;
    final busy = widget.busy || _testing || _discovering;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Graphite.surface,
        borderRadius: BorderRadius.circular(corner),
        border: Border.all(color: Graphite.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: small.copyWith(color: Graphite.text, fontWeight: FontWeight.w600)),
                    if (command.isNotEmpty) Text(command, style: mono.copyWith(fontSize: 11, color: Graphite.muted)),
                  ],
                ),
              ),
              Status(_statusLabel(rawStatus), _statusColor(rawStatus)),
            ],
          ),
          if (plainLanguage.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(plainLanguage, style: small.copyWith(color: Graphite.text)),
          ],
          if (advice.isNotEmpty && rawStatus != 'connected') ...[
            const SizedBox(height: 2),
            Text(advice, style: tiny.copyWith(color: Graphite.muted)),
          ],

          // Legacy plaintext credentials migration banner
          if (legacy != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Graphite.raised,
                borderRadius: BorderRadius.circular(corner),
                border: Border.all(color: waiting.withValues(alpha: .5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: waiting),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('Plaintext credentials detected in configuration',
                            style: small.copyWith(color: waiting, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('Migrate secrets to macOS Keychain so they are kept out of ordinary settings files and visible command arguments.',
                      style: tiny),
                  const SizedBox(height: 6),
                  OutlinedButton(
                    onPressed: busy ? null : () => _showMigrationPreview(context, legacy),
                    child: const Text('Preview & migrate credentials'),
                  ),
                ],
              ),
            ),
          ],

          // Credentials Section
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: Text('Credentials (secure store)', style: small.copyWith(fontWeight: FontWeight.w600))),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add credential', style: tiny),
                onPressed: busy ? null : () => _addOrEditCredential(context),
              ),
            ],
          ),
          if (credentials.isEmpty)
            const Text('No credentials configured in secure store.', style: quiet)
          else
            for (final entry in credentials.entries)
              _CredentialRow(
                keyName: entry.key,
                info: entry.value as Json,
                busy: busy,
                onReplace: () => _addOrEditCredential(context, existingKey: entry.key),
                onRemove: () => widget.model.changeExtensions({
                  'op': 'remove_credential',
                  'name': name,
                  'key': entry.key,
                }),
              ),

          if (technical.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => setState(() => _showTechnical = !_showTechnical),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_showTechnical ? Icons.expand_less : Icons.expand_more, size: 16, color: Graphite.muted),
                    const SizedBox(width: 4),
                    Text(_showTechnical ? 'Hide technical details' : 'Show technical details', style: tiny),
                  ],
                ),
              ),
            ),
            if (_showTechnical)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(top: 4, bottom: 4),
                decoration: BoxDecoration(
                  color: Graphite.raised,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Graphite.line),
                ),
                child: SelectableText(technical, style: mono.copyWith(fontSize: 11)),
              ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton(
                onPressed: busy ? null : _testConnection,
                child: const Text('Test connection'),
              ),
              OutlinedButton(
                onPressed: busy ? null : _discoverTools,
                child: const Text('Discover tools'),
              ),
              TextButton(
                onPressed: busy ? null : () => widget.model.changeExtensions({'op': 'remove_server', 'name': name}),
                child: const Text('Remove'),
              ),
            ],
          ),
          if (tools.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Discovered tools (${tools.length})', style: small.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            for (final tool in tools)
              _ToolCard(
                tool: tool,
                busy: busy,
                onRun: () => _runTestTool(context, tool),
              ),
          ],
        ],
      ),
    );
  }
}

class _CredentialRow extends StatelessWidget {
  const _CredentialRow({
    required this.keyName,
    required this.info,
    required this.busy,
    required this.onReplace,
    required this.onRemove,
  });

  final String keyName;
  final Json info;
  final bool busy;
  final VoidCallback onReplace;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    // Only whether a key is there is ever sent, never the key: saved, missing, locked or unavailable.
    final state = info['state'] as String? ?? (info['configured'] == true ? 'saved' : 'missing');
    final masked = info['masked'] as String? ?? '••••••••';
    final inArguments = info['delivery'] == 'argument';
    final (label, colour) = switch (state) {
      'saved' => ('Saved ($masked)', good),
      'locked' => ('Keychain locked', waiting),
      'unavailable' => ('Keychain unavailable', bad),
      _ => ('Not saved', bad),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(keyName, style: mono.copyWith(color: Graphite.text, fontWeight: FontWeight.w500)),
                const SizedBox(width: 8),
                Status(label, colour),
                if (inArguments) ...[
                  const SizedBox(width: 8),
                  const Tooltip(
                    message: 'Filled into a command-line argument when the server starts. While it runs, other programs on this Mac can read its arguments.',
                    child: Text('argument', style: tiny),
                  ),
                ],
              ],
            ),
          ),
          TextButton(
            onPressed: busy ? null : onReplace,
            child: const Text('Replace', style: tiny),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: busy ? null : onRemove,
            child: const Text('Remove', style: tiny),
          ),
        ],
      ),
    );
  }
}

class _CredentialDialog extends StatefulWidget {
  const _CredentialDialog({required this.serverName, this.existingKey});

  final String serverName;
  final String? existingKey;

  @override
  State<_CredentialDialog> createState() => _CredentialDialogState();
}

class _CredentialDialogState extends State<_CredentialDialog> {
  late final TextEditingController _keyController;
  final _secretController = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(text: widget.existingKey ?? '');
  }

  @override
  void dispose() {
    _keyController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  void _save() {
    final key = _keyController.text.trim();
    final secret = _secretController.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Environment variable name is required.');
      return;
    }
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key)) {
      setState(() => _error = 'Variable name must be valid identifier (e.g. TAVILY_API_KEY).');
      return;
    }
    if (secret.isEmpty) {
      setState(() => _error = 'Secret value cannot be empty.');
      return;
    }
    Navigator.pop(context, {'key': key, 'secret': secret});
  }

  @override
  Widget build(BuildContext context) {
    final isReplacing = widget.existingKey != null;
    return AlertDialog(
      title: Text(isReplacing ? 'Replace credential: ${widget.existingKey}' : 'Add credential to ${widget.serverName}'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _keyController,
              enabled: !isReplacing,
              style: mono.copyWith(color: Graphite.text),
              decoration: const InputDecoration(labelText: 'Environment variable name (e.g. TAVILY_API_KEY)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _secretController,
              obscureText: _obscure,
              style: mono.copyWith(color: Graphite.text),
              decoration: InputDecoration(
                labelText: 'Secret / API Key value',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, size: 18),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: tiny.copyWith(color: bad)),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Graphite.raised,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Graphite.line),
              ),
              child: const Text(
                'Saved in your login Keychain, never in the app\'s settings, the chat or the activity log. When the server starts, '
                'it gets the key as the environment variable named above, so the key isn\'t on its command line. Programs running '
                'as you can still read a running server\'s environment, so only give keys to servers you trust.',
                style: tiny,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save credential')),
      ],
    );
  }
}

class _MigrationPreviewDialog extends StatelessWidget {
  const _MigrationPreviewDialog({required this.serverName, required this.preview});

  final String serverName;
  final Json preview;

  @override
  Widget build(BuildContext context) {
    final detected = ((preview['detected'] as List?) ?? const []).cast<Json>();
    final limitations = preview['limitations'] as String? ?? '';
    final cleanedArgs = ((preview['cleaned_args'] as List?) ?? const []).cast<String>();
    final argumentWarning = preview['argument_warning'] as String? ?? '';

    return AlertDialog(
      title: Text('Migrate credentials: $serverName'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Detected plaintext secrets will be moved into macOS Keychain:', style: small),
            const SizedBox(height: 6),
            for (final item in detected)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('• ${item['key']}: ${item['masked']} (from ${item['location']}, kept as ${item['delivery'] == 'argument' ? 'an argument' : 'an environment variable'})', style: mono),
              ),
            const SizedBox(height: 8),
            Text('Cleaned command arguments:', style: tiny.copyWith(color: Graphite.muted)),
            Text(cleanedArgs.isEmpty ? '(none)' : cleanedArgs.join(' '), style: mono.copyWith(fontSize: 11)),
            if (argumentWarning.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(argumentWarning, style: tiny.copyWith(color: waiting)),
            ],
            const SizedBox(height: 8),
            Text('Nothing changes until every key is saved in the Keychain and read back. If anything fails, the server keeps its current settings.',
                style: tiny.copyWith(color: Graphite.muted)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Graphite.raised,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Graphite.line),
              ),
              child: Text(
                'Limitations: $limitations',
                style: tiny.copyWith(color: Graphite.muted),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Migrate to Keychain')),
      ],
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.tool, required this.busy, required this.onRun});

  final Json tool;
  final bool busy;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final name = tool['name'] as String;
    final description = tool['description'] as String? ?? '';
    final status = tool['status'] as String? ?? 'unknown';
    final retryIn = tool['retry_available_in'] as String?;
    final lastResult = tool['last_result'] as Json?;
    final resultText = lastResult?['plain_language'] as String?;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Graphite.raised,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Graphite.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name, style: mono.copyWith(color: Graphite.text, fontWeight: FontWeight.w600)),
              ),
              Status(_toolStatusLabel(status, retryIn), _toolStatusColor(status)),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(description, style: tiny, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          if (resultText != null && resultText.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(resultText, style: tiny.copyWith(color: Graphite.text)),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: busy ? null : onRun,
              child: const Text('Run test tool'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TestToolDialog extends StatefulWidget {
  const _TestToolDialog({required this.serverName, required this.tool});

  final String serverName;
  final Json tool;

  @override
  State<_TestToolDialog> createState() => _TestToolDialogState();
}

class _TestToolDialogState extends State<_TestToolDialog> {
  late final TextEditingController _argsController;
  String? _error;

  @override
  void initState() {
    super.initState();
    final schema = widget.tool['schema'] as Json?;
    final properties = schema?['properties'] as Json?;
    final initial = <String, dynamic>{};
    if (properties != null) {
      for (final key in properties.keys) {
        initial[key] = '';
      }
    }
    const encoder = JsonEncoder.withIndent('  ');
    _argsController = TextEditingController(text: encoder.convert(initial));
  }

  @override
  void dispose() {
    _argsController.dispose();
    super.dispose();
  }

  void _run() {
    try {
      final text = _argsController.text.trim();
      final decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        setState(() => _error = 'Arguments must be a JSON object.');
        return;
      }
      Navigator.pop(context, decoded);
    } catch (e) {
      setState(() => _error = 'Invalid JSON: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final toolName = widget.tool['name'] as String;
    final description = widget.tool['description'] as String? ?? '';
    return AlertDialog(
      title: Text('Run test tool: $toolName'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (description.isNotEmpty) ...[
              Text(description, style: small),
              const SizedBox(height: 8),
            ],
            const Text('Arguments (JSON):', style: tiny),
            const SizedBox(height: 4),
            TextField(
              controller: _argsController,
              minLines: 3,
              maxLines: 8,
              style: mono.copyWith(color: Graphite.text),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: tiny.copyWith(color: bad)),
            ],
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Graphite.raised,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Graphite.line),
              ),
              child: Text(
                'Approval required: This tool will run on server "${widget.serverName}" on this Mac. '
                'Only run tools you trust.',
                style: tiny.copyWith(color: Graphite.muted),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _run, child: const Text('Allow and run')),
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
  final _credKey = TextEditingController();
  final _credSecret = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _command.dispose();
    _args.dispose();
    _credKey.dispose();
    _credSecret.dispose();
    super.dispose();
  }

  void _add() {
    if (_name.text.trim().isEmpty || _command.text.trim().isEmpty) return;
    final args = _args.text.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
    final credentials = <String, String>{};
    if (_credKey.text.trim().isNotEmpty && _credSecret.text.trim().isNotEmpty) {
      credentials[_credKey.text.trim()] = _credSecret.text.trim();
    }
    Navigator.pop(context, {
      'name': _name.text.trim(),
      'command': _command.text.trim(),
      'args': args,
      if (credentials.isNotEmpty) 'credentials': credentials,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add an MCP server'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
              TextField(controller: _command, style: mono.copyWith(color: Graphite.text), decoration: const InputDecoration(labelText: 'Program, such as npx or python3')),
              TextField(
                controller: _args,
                minLines: 2,
                maxLines: 4,
                style: mono.copyWith(color: Graphite.text),
                decoration: const InputDecoration(labelText: 'Arguments, one per line (no secrets)'),
              ),
              const SizedBox(height: 12),
              const Text('Optional secure credential:', style: tiny),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _credKey,
                      style: mono.copyWith(color: Graphite.text),
                      decoration: const InputDecoration(labelText: 'Env var name (e.g. TAVILY_API_KEY)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _credSecret,
                      obscureText: _obscure,
                      style: mono.copyWith(color: Graphite.text),
                      decoration: InputDecoration(
                        labelText: 'API Key / Secret',
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, size: 18),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text('Only add servers you trust. Secrets are kept securely in macOS Keychain and injected at launch time.', style: tiny),
            ],
          ),
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
            subtitle: Text('MCP server (${_statusLabel(item['connection_status'] as String? ?? 'configured')}). Each tool asks you first.', style: tiny),
            value: item['on'] == true,
            onChanged: model.busy ? null : (on) => model.changeAssistant('use_server', {'name': item['name'], 'on': on}, 'Changing tools'),
          ),
      ],
    );
  }
}
