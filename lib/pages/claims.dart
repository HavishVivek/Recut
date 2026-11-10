import 'dart:convert';

import 'package:flutter/material.dart';

import '../engine.dart';
import '../project.dart';
import '../theme.dart';
import '../ui.dart';

/// Claims a project's scenes make, and the sources behind them. Everything is typed or picked by a person:
/// nothing is fetched, and only a person's click marks a claim verified. A source's text is shown as plain
/// text, never acted on.
class ClaimsPanel extends StatelessWidget {
  const ClaimsPanel({super.key, required this.model});

  final ProjectModel model;

  Json get _board => (model.state?['board'] as Json?) ?? const {};
  List<Json> _list(String key) => ((_board[key] as List?) ?? const []).cast<Json>();

  Future<void> _change(Json body, String label) => model.changeAssistant('board', body, label);
  Future<void> _research(Json body, String label) => model.changeAssistant('research', body, label);
  Json get _found => (model.state?['research'] as Json?) ?? const {};

  static const statusWords = {
    'unverified': ('Unverified', Graphite.muted),
    'evidence_linked': ('Evidence linked', waiting),
    'human_verified': ('Human verified', good),
    'needs_review': ('Needs review', waiting),
    'contradicted': ('Contradicted', bad),
  };

  @override
  Widget build(BuildContext context) {
    final scenes = _list('scenes');
    final claims = _list('claims');
    final sources = _list('evidence');
    final busy = model.busy;
    final waitingLinks = claims.expand((claim) => ((claim['scenes'] as List?) ?? const []).cast<Json>())
        .where((link) => link['review_state'] == 'needs_review').length;
    return Section(
      'Claims and sources',
      children: [
        const Text('What your scenes say, and where it comes from. Sources are typed in by you, and only you can mark a claim verified.', style: tiny),
        if (waitingLinks > 0) Alert('$waitingLinks ${waitingLinks == 1 ? 'link needs' : 'links need'} review after a script change.'),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          OutlinedButton(onPressed: busy ? null : () => _addScene(context), child: const Text('Add scene', style: tiny)),
          OutlinedButton(onPressed: busy ? null : () => _addClaim(context), child: const Text('Add claim', style: tiny)),
          OutlinedButton(onPressed: busy ? null : () => _addSource(context), child: const Text('Add source', style: tiny)),
          if (((_found['servers_on'] as List?) ?? const []).isNotEmpty)
            OutlinedButton(onPressed: busy ? null : () => _search(context), child: const Text('Search the web', style: tiny)),
        ]),
        ..._researchPart(context, claims, scenes),
        if (scenes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Scenes', style: small.copyWith(fontWeight: FontWeight.w600)),
          for (final scene in scenes)
            Row(children: [
              Expanded(child: Text('${scene['title']}  ·  revision ${scene['narration_rev']}', style: small, overflow: TextOverflow.ellipsis)),
              TextButton(onPressed: busy ? null : () => _editScript(context, scene), child: const Text('Edit script', style: tiny)),
            ]),
        ],
        if (claims.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Claims', style: small.copyWith(fontWeight: FontWeight.w600)),
          for (final claim in claims) _claimCard(context, claim, scenes, sources),
        ],
        if (sources.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Sources', style: small.copyWith(fontWeight: FontWeight.w600)),
          for (final source in sources) _sourceRow(context, source),
        ],
      ],
    );
  }

  Widget _claimCard(BuildContext context, Json claim, List<Json> scenes, List<Json> sources) {
    final (label, colour) = statusWords[claim['status']] ?? ('Unknown', bad);
    final links = ((claim['scenes'] as List?) ?? const []).cast<Json>();
    final evidence = ((claim['evidence'] as List?) ?? const []).cast<Json>();
    final verifiedBy = claim['verified_by'] as Json?;
    final busy = model.busy;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Graphite.raised, borderRadius: BorderRadius.circular(6), border: Border.all(color: Graphite.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(claim['text'] as String, style: small),
        const SizedBox(height: 4),
        Row(children: [
          Status(label, colour),
          if (verifiedBy != null) Expanded(child: Text('  by ${verifiedBy['actor']}', style: tiny, overflow: TextOverflow.ellipsis)),
        ]),
        for (final link in links)
          Row(children: [
            Expanded(
              child: Text(
                link['review_state'] == 'needs_review'
                    ? 'In ${link['title']}: script changed (revision ${link['current_rev']}), needs review'
                    : 'In ${link['title']}${link['reviewed_rev'] != null ? ', checked at revision ${link['reviewed_rev']}' : ''}',
                style: tiny.copyWith(color: link['review_state'] == 'needs_review' ? waiting : Graphite.muted),
              ),
            ),
            if (link['review_state'] == 'needs_review')
              TextButton(
                onPressed: busy ? null : () => _change({'op': 'review_link', 'scene_id': link['scene_id'], 'claim_id': claim['id']}, 'Reviewing a link'),
                child: const Text('Still right', style: tiny),
              ),
          ]),
        for (final item in evidence)
          Row(children: [
            Expanded(
              child: Text('${item['stance'] == 'contradicts' ? 'Contradicted by' : 'Supported by'} ${_name(item)}: "${item['excerpt']}"',
                  style: tiny, maxLines: 3, overflow: TextOverflow.ellipsis),
            ),
            TextButton(onPressed: () => _open(item['url'] as String), child: const Text('Open', style: tiny)),
          ]),
        Wrap(spacing: 2, children: [
          if (sources.isNotEmpty) TextButton(onPressed: busy ? null : () => _linkSource(context, claim, sources), child: const Text('Link source', style: tiny)),
          if (scenes.isNotEmpty) TextButton(onPressed: busy ? null : () => _attach(context, claim, scenes), child: const Text('Attach to scene', style: tiny)),
          PopupMenuButton<String>(
            enabled: !busy,
            tooltip: 'Review this claim',
            onSelected: (status) => _review(context, claim, status),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'human_verified', child: Text('I checked it: verified')),
              PopupMenuItem(value: 'needs_review', child: Text('Needs review')),
              PopupMenuItem(value: 'contradicted', child: Text('Contradicted')),
              PopupMenuItem(value: 'unverified', child: Text('Back to unverified')),
            ],
            child: const Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10), child: Text('Review', style: tiny)),
          ),
          TextButton(onPressed: () => _history(context, claim), child: const Text('History', style: tiny)),
        ]),
      ]),
    );
  }

  Widget _sourceRow(BuildContext context, Json source) {
    final claims = ((source['claims'] as List?) ?? const []).length;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_name(source), style: small, overflow: TextOverflow.ellipsis),
            Text(
              [
                if ((source['publisher'] as String? ?? '').isNotEmpty) source['publisher'],
                source['retrieved'],
                'used by $claims ${claims == 1 ? 'claim' : 'claims'}',
              ].join(' · '),
              style: tiny,
            ),
          ]),
        ),
        TextButton(onPressed: () => _open(source['url'] as String), child: const Text('Open', style: tiny)),
      ]),
    );
  }

  /// The last search: a call waiting for Allow, what went wrong, and the pages found, each with what can be kept.
  List<Widget> _researchPart(BuildContext context, List<Json> claims, List<Json> scenes) {
    final pending = _found['pending'] as Json?;
    final error = _found['error'] as Json?;
    final notice = _found['notice'] as String?;
    final results = ((_found['results'] as List?) ?? const []).cast<Json>();
    final busy = model.busy;
    return [
      if (pending != null)
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Graphite.raised, borderRadius: BorderRadius.circular(6), border: Border.all(color: waiting)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Run ${pending['tool']} on ${pending['server']}?', style: small.copyWith(fontWeight: FontWeight.w600)),
            Text(const JsonEncoder.withIndent(' ').convert(pending['arguments']), style: mono.copyWith(fontSize: 11)),
            const Text('It runs once. Nothing runs unless you allow it.', style: tiny),
            Wrap(spacing: 6, runSpacing: 4, children: [
              FilledButton(
                onPressed: busy ? null : () => _research({'op': 'run', 'call_id': pending['id'], 'allow': true}, 'Running ${pending['tool']}'),
                child: const Text('Allow'),
              ),
              TextButton(onPressed: busy ? null : () => _research({'op': 'run', 'call_id': pending['id'], 'allow': false}, 'Not running it'), child: const Text('Don\'t run it')),
            ]),
          ]),
        ),
      if (error != null)
        Alert([error['plain_language'], if (error['actionable_advice'] != null) error['actionable_advice']].join(' '),
            color: error['status'] == 'rate_limited' ? waiting : bad),
      if (notice != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(notice, style: tiny)),
      for (final result in results)
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: Graphite.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: (result['title'] as String? ?? '').isEmpty
                    ? const Text('No title came back', style: tiny)
                    : Text(result['title'] as String, style: small, overflow: TextOverflow.ellipsis),
              ),
              TextButton(onPressed: () => _open(result['url'] as String), child: const Text('Open', style: tiny)),
            ]),
            Text(result['url'] as String, style: mono.copyWith(fontSize: 11), overflow: TextOverflow.ellipsis),
            if (((result['metadata'] as Json?) ?? const {}).isNotEmpty)
              Text([for (final entry in (result['metadata'] as Json).entries) '${entry.key}: ${entry.value}'].join(' · '), style: tiny),
            const SizedBox(height: 4),
            Text('Search snippet', style: tiny.copyWith(fontWeight: FontWeight.w600)),
            SelectableText((result['snippet'] as String? ?? '').isEmpty ? '(no snippet came back)' : result['snippet'] as String, style: tiny, maxLines: 6),
            if ((result['page'] as String? ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Page text, read by ${result['read_by']}', style: tiny.copyWith(fontWeight: FontWeight.w600)),
              SelectableText(result['page'] as String, style: tiny, maxLines: 6),
            ],
            Wrap(spacing: 2, children: [
              TextButton(onPressed: busy ? null : () => _keep(context, result, claims, scenes), child: const Text('Keep an excerpt', style: tiny)),
              if ((result['page'] as String? ?? '').isEmpty)
                TextButton(onPressed: busy ? null : () => _research({'op': 'prepare_extract', 'result_id': result['id']}, 'Getting ready to read the page'),
                    child: const Text('Read page', style: tiny)),
              if (((result['saved'] as List?) ?? const []).isNotEmpty) const Padding(padding: EdgeInsets.only(top: 10), child: Text('kept', style: tiny)),
            ]),
          ]),
        ),
      if (results.isNotEmpty || error != null || notice != null)
        Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: busy ? null : () => _research({'op': 'clear'}, 'Clearing the search'), child: const Text('Clear search', style: tiny))),
    ];
  }

  Future<void> _search(BuildContext context) async {
    final values = await _ask(context, 'Search the web', const [('query', 'What to search for', 1)],
        note: 'You\'ll see exactly what will run, and nothing runs until you allow it. Results are kept only when you pick an excerpt.');
    if (values != null) await _research({'op': 'prepare_search', 'query': values['query']}, 'Getting the search ready');
  }

  Future<void> _keep(BuildContext context, Json result, List<Json> claims, List<Json> scenes) async {
    final picked = await showDialog<Json>(context: context, builder: (_) => _KeepDialog(result: result, claims: claims, scenes: scenes));
    if (picked != null) await _research({'op': 'save', 'result_id': result['id'], ...picked}, 'Keeping the excerpt');
  }

  /// Only a web address opens. The engine checked it when the source was added; this checks again before handing it to macOS.
  static Future<void> _open(String url) async {
    final parsed = Uri.tryParse(url);
    if (parsed != null && (parsed.scheme == 'https' || parsed.scheme == 'http') && parsed.host.isNotEmpty) await openInBrowser(url);
  }

  /// A source by its title when it has one, or else its address. A missing title is never made up.
  static String _name(Json source) {
    final title = (source['title'] as String? ?? '').trim();
    return title.isNotEmpty ? title : source['url'] as String;
  }

  Future<void> _addScene(BuildContext context) async {
    final values = await _ask(context, 'Add a scene', const [('title', 'Scene title', 1)]);
    if (values != null) await _change({'op': 'add_scene', 'title': values['title']}, 'Adding a scene');
  }

  Future<void> _editScript(BuildContext context, Json scene) async {
    final values = await _ask(context, 'Edit ${scene['title']}', const [
      ('narration', 'Script', 4),
      ('on_screen', 'Words on screen', 2),
      ('visual', 'What it shows', 2),
    ], start: {'narration': scene['narration'], 'on_screen': scene['on_screen'], 'visual': scene['visual']},
        note: 'Changing these makes a new revision. Claims on this scene are marked for review.');
    if (values != null) await _change({'op': 'edit_scene', 'id': scene['id'], ...values}, 'Saving the script');
  }

  Future<void> _addClaim(BuildContext context) async {
    final values = await _ask(context, 'Add a claim', const [('text', 'The claim, in one sentence', 2)]);
    if (values != null) await _change({'op': 'add_claim', 'text': values['text']}, 'Adding a claim');
  }

  Future<void> _addSource(BuildContext context) async {
    final values = await _ask(context, 'Add a source', const [
      ('url', 'Address (https://...)', 1),
      ('title', 'Page title, if you know it', 1),
      ('publisher', 'Publisher, if you know it', 1),
      ('excerpt', 'Excerpt copied from the page (up to 2000 characters)', 4),
      ('product_ids', 'Products or models, separated by commas', 1),
      ('notes', 'Your notes', 2),
    ], note: 'Nothing is fetched. Leave a field empty if you don\'t know it: nothing is filled in for you.');
    if (values != null) await _change({'op': 'add_evidence', ...values}, 'Adding a source');
  }

  Future<void> _linkSource(BuildContext context, Json claim, List<Json> sources) async {
    final picked = await showDialog<Json>(
      context: context,
      builder: (_) => _LinkDialog(sources: sources),
    );
    if (picked != null) await _change({'op': 'link_evidence', 'claim_id': claim['id'], ...picked}, 'Linking a source');
  }

  Future<void> _attach(BuildContext context, Json claim, List<Json> scenes) async {
    final scene = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Attach to which scene?'),
        children: [
          for (final scene in scenes)
            SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, scene['id'] as String), child: Text(scene['title'] as String)),
        ],
      ),
    );
    if (scene != null) await _change({'op': 'attach_claim', 'scene_id': scene, 'claim_id': claim['id']}, 'Attaching a claim');
  }

  Future<void> _review(BuildContext context, Json claim, String status) async {
    final values = await _ask(context, statusWords[status]!.$1, const [('notes', 'Why (optional)', 2)], optional: true);
    if (values != null) await _change({'op': 'review_claim', 'id': claim['id'], 'status': status, 'notes': values['notes'] ?? ''}, 'Reviewing a claim');
  }

  Future<void> _history(BuildContext context, Json claim) => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('History'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final step in ((claim['history'] as List?) ?? const []).cast<Json>())
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      '${step['at']}  ${statusWords[step['to_status']]?.$1 ?? step['to_status']}  ·  '
                      '${step['method'] == 'human' ? step['actor'] : 'automatic (${step['method'] == 'script_change' ? 'script changed' : 'linked source'})'}'
                      '${(step['notes'] as String? ?? '').isNotEmpty ? '\n${step['notes']}' : ''}',
                      style: tiny,
                    ),
                  ),
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
        ),
      );

  Future<Map<String, String>?> _ask(BuildContext context, String title, List<(String, String, int)> fields,
          {Map<String, dynamic> start = const {}, String? note, bool optional = false}) =>
      showDialog<Map<String, String>>(
        context: context,
        builder: (_) => _FieldsDialog(title: title, fields: fields, start: start, note: note, optional: optional),
      );
}

class _FieldsDialog extends StatefulWidget {
  const _FieldsDialog({required this.title, required this.fields, required this.start, this.note, this.optional = false});

  final String title;
  final List<(String, String, int)> fields;
  final Map<String, dynamic> start;
  final String? note;
  final bool optional;

  @override
  State<_FieldsDialog> createState() => _FieldsDialogState();
}

class _FieldsDialogState extends State<_FieldsDialog> {
  late final Map<String, TextEditingController> _controllers = {
    for (final (key, _, _) in widget.fields) key: TextEditingController(text: (widget.start[key] as String?) ?? ''),
  };

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final (key, label, lines) in widget.fields)
                TextField(controller: _controllers[key], minLines: lines, maxLines: lines == 1 ? 1 : lines + 4, decoration: InputDecoration(labelText: label)),
              if (widget.note != null) ...[const SizedBox(height: 10), Text(widget.note!, style: tiny)],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, {for (final entry in _controllers.entries) entry.key: entry.value.text}),
            child: const Text('Save'),
          ),
        ],
      );
}

class _LinkDialog extends StatefulWidget {
  const _LinkDialog({required this.sources});

  final List<Json> sources;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late String _source = widget.sources.first['id'] as String;
  String _stance = 'supports';
  final _excerpt = TextEditingController();

  @override
  void dispose() {
    _excerpt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Link a source'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            DropdownButton<String>(
              isExpanded: true,
              value: _source,
              items: [
                for (final source in widget.sources)
                  DropdownMenuItem(value: source['id'] as String, child: Text(ClaimsPanel._name(source), overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (value) => setState(() => _source = value ?? _source),
            ),
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'supports', label: Text('Supports')), ButtonSegment(value: 'contradicts', label: Text('Contradicts'))],
              selected: {_stance},
              onSelectionChanged: (value) => setState(() => _stance = value.first),
            ),
            TextField(controller: _excerpt, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'The excerpt for this claim (empty uses the source\'s own)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, {'evidence_id': _source, 'stance': _stance, 'excerpt': _excerpt.text}), child: const Text('Link')),
        ],
      );
}

/// Pick words from what came back. They're checked against it, so an excerpt can be shortened but never reworded.
class _KeepDialog extends StatefulWidget {
  const _KeepDialog({required this.result, required this.claims, required this.scenes});

  final Json result;
  final List<Json> claims;
  final List<Json> scenes;

  @override
  State<_KeepDialog> createState() => _KeepDialogState();
}

class _KeepDialogState extends State<_KeepDialog> {
  late String _source = (widget.result['snippet'] as String? ?? '').isNotEmpty ? 'snippet' : 'page';
  late final _excerpt = TextEditingController(text: _text);
  String? _link; // "claim:<id>" or "scene:<id>"
  String _stance = 'supports';

  String get _text => (_source == 'page' ? widget.result['page'] : widget.result['snippet']) as String? ?? '';

  @override
  void dispose() {
    _excerpt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasPage = (widget.result['page'] as String? ?? '').isNotEmpty;
    final hasSnippet = (widget.result['snippet'] as String? ?? '').isNotEmpty;
    return AlertDialog(
      title: const Text('Keep an excerpt'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (hasPage && hasSnippet)
              SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'snippet', label: Text('Search snippet')), ButtonSegment(value: 'page', label: Text('Page text'))],
                selected: {_source},
                onSelectionChanged: (value) => setState(() {
                  _source = value.first;
                  _excerpt.text = _text;
                }),
              ),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(child: SelectableText(_text, style: tiny)),
            ),
            TextField(controller: _excerpt, minLines: 2, maxLines: 6,
                decoration: const InputDecoration(labelText: 'Excerpt: delete what you don\'t need, but don\'t reword it')),
            DropdownButton<String?>(
              isExpanded: true,
              value: _link,
              hint: const Text('Keep it without linking'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Keep it without linking')),
                for (final claim in widget.claims)
                  DropdownMenuItem<String?>(value: 'claim:${claim['id']}', child: Text('Claim: ${claim['text']}', overflow: TextOverflow.ellipsis)),
                for (final scene in widget.scenes)
                  DropdownMenuItem<String?>(value: 'scene:${scene['id']}', child: Text('Scene: ${scene['title']}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (value) => setState(() => _link = value),
            ),
            if (_link?.startsWith('claim:') == true)
              SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'supports', label: Text('Supports')), ButtonSegment(value: 'contradicts', label: Text('Contradicts'))],
                selected: {_stance},
                onSelectionChanged: (value) => setState(() => _stance = value.first),
              ),
            const SizedBox(height: 6),
            const Text('It\'s kept as an automated find, with its address and when it was found. It counts as verified only when you verify the claim.', style: tiny),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            'source': _source,
            'excerpt': _excerpt.text,
            if (_link?.startsWith('claim:') == true) ...{'claim_id': _link!.substring(6), 'stance': _stance},
            if (_link?.startsWith('scene:') == true) 'scene_id': _link!.substring(6),
          }),
          child: const Text('Keep'),
        ),
      ],
    );
  }
}
