import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../engine.dart';
import '../motion.dart';
import '../project.dart';
import '../theme.dart';
import '../ui.dart';
import 'finds.dart';
import 'exchange.dart';

const _zones = {
  'lower_left': 'Lower left',
  'lower_center': 'Lower centre',
  'lower_right': 'Lower right',
  'center': 'Centre',
  'left': 'Left',
  'right': 'Right',
  'upper_left': 'Upper left',
  'upper_right': 'Upper right',
};
final _hex = RegExp(r'^#[0-9A-Fa-f]{6}$');

class StylePage extends StatefulWidget {
  const StylePage({super.key, required this.model});

  final ProjectModel model;

  @override
  State<StylePage> createState() => _StylePageState();
}

class _StylePageState extends State<StylePage> {
  final _colours = [TextEditingController(), TextEditingController(), TextEditingController()];
  String? _zone;
  String? _font;
  double _seconds = 2.5;
  List<String> _fonts = const [];
  Json? _loaded;
  // The reference shown when the page opened. A new one's colours settle in one by one.
  String? _seenReference;
  bool _seen = false;

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    widget.model.removeListener(_sync);
    for (final colour in _colours) {
      colour.dispose();
    }
    super.dispose();
  }

  /// Takes the engine's values only when they change, so typing isn't overwritten.
  void _sync() {
    final chosen = widget.model.style?['chosen'] as Json?;
    if (chosen == null || identical(chosen, _loaded)) return;
    _loaded = chosen;
    final palette = (chosen['palette'] as List).cast<String>();
    for (final (index, colour) in _colours.indexed) {
      colour.text = palette[index < palette.length ? index : palette.length - 1];
    }
    setState(() {
      _zone = chosen['zone'] as String;
      _font = chosen['font'] as String;
      _seconds = (chosen['title_seconds'] as num).toDouble();
    });
  }

  Future<void> _loadFonts() async {
    final outcome = await widget.model.run('fonts', {}, 'Listing installed fonts', quiet: true);
    final fonts = (outcome?['result'] as Json?)?['fonts'] as List?;
    if (fonts != null && mounted) setState(() => _fonts = fonts.cast<String>());
  }

  Future<void> _save() async {
    final palette = [for (final colour in _colours) colour.text.trim().toUpperCase()];
    if (!palette.every(_hex.hasMatch)) {
      widget.model.complain('Colours look like #FF6A3D.');
      return;
    }
    // Only what changed goes, because the engine marks whatever it's sent as a person's choice.
    final chosen = _loaded!;
    final seconds = double.parse(_seconds.toStringAsFixed(1));
    final changes = <String, dynamic>{
      if (palette.join() != (chosen['palette'] as List).join()) 'palette': palette,
      if (_zone != chosen['zone']) 'zone': _zone,
      if (_font != chosen['font']) 'font': _font,
      if (seconds != (chosen['title_seconds'] as num).toDouble()) 'title_seconds': seconds,
    };
    if (changes.isNotEmpty) await widget.model.run('style', changes, 'Saving the style');
  }

  Widget _swatch(String hex, {double size = 22}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _hex.hasMatch(hex) ? colourFrom(hex) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Graphite.lineStrong),
      ),
    );
  }

  Widget _measured(Json style) {
    final measured = style['measured'] as Json;
    final palette = (measured['palette'] as List).cast<Json>();
    final box = (measured['title_bbox_norm'] as List).cast<num>();
    final whole = box[0] == 0 && box[1] == 0 && box[2] == 1 && box[3] == 1;
    final onScreen = measured['title_on_screen_s'] as Json?;
    final reference = '${style['path']}';
    final fresh = _seen && _seenReference != reference;
    if (!_seen || _seenReference != reference) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _seen = true;
        _seenReference = reference;
      });
    }
    return Section(
      'Measured from ${style['reference']}',
      children: [
        const Text('Facts read from its pixels', style: quiet),
        const SizedBox(height: 10),
        for (final (index, colour) in palette.indexed)
          Arrive(
            key: ValueKey(('swatch', reference, index)),
            play: fresh,
            delay: Duration(milliseconds: 60 * index),
            rise: 6,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  _swatch(colour['hex'] as String),
                  const SizedBox(width: 10),
                  SelectableText(colour['hex'] as String, style: mono),
                  const Spacer(),
                  CountUp(((colour['share'] as num) * 100).toDouble(), play: fresh, style: mono, format: (value) => '${value.toStringAsFixed(1)}%'),
                ],
              ),
            ),
          ),
        const SizedBox(height: 6),
        Fact('Title area', whole ? 'None found' : box.map((value) => value.toStringAsFixed(2)).join(', ')),
        Fact('On screen', onScreen == null ? 'Not measured' : '${onScreen['value']} s, at ${onScreen['at']}'),
        if (measured['cuts_per_minute'] != null) Fact('Cutting pace', '${measured['cuts_per_minute']} cuts a minute', exact: true),
      ],
    );
  }

  Widget _interpreted(Json style) {
    final claims = (style['interpreted'] as List).cast<Json>();
    return Section(
      'Interpreted',
      children: [
        const Text('Readings of those facts, which may be wrong', style: quiet),
        const SizedBox(height: 10),
        if (claims.isEmpty) const Text('Nothing to say about this one', style: quiet),
        for (final claim in claims)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(claim['claim'] as String, style: small),
                Text('${((claim['confidence'] as num) * 100).round()}% sure. ${claim['evidence']}', style: tiny),
              ],
            ),
          ),
      ],
    );
  }

  Widget _source(Json style, String field) {
    final who = (style['applied_to'] as Json)[field] as String?;
    return Tag(who == 'user_choice' ? 'your choice' : 'from reference');
  }

  Widget _choices(Json style) {
    final model = widget.model;
    final zone = _zone;
    return Section(
      'Title style',
      trailing: FilledButton(onPressed: model.busy ? null : _save, child: const Text('Save style')),
      children: [
        const Text('This is what the next plan uses. The measurements above stay as they were.', style: quiet),
        const SizedBox(height: 12),
        for (final (index, name) in const ['Plate', 'Text', 'Accent'].indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(width: 72, child: Text(name, style: quiet)),
                ValueListenableBuilder(
                  valueListenable: _colours[index],
                  builder: (_, value, _) => _swatch(value.text),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _colours[index],
                    style: mono,
                    decoration: InputDecoration(isDense: true, hintText: '#FF6A3D', labelText: null, semanticCounterText: '$name colour'),
                  ),
                ),
                if (index == 0) ...[const SizedBox(width: 10), _source(style, 'palette')],
              ],
            ),
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            const SizedBox(width: 72, child: Text('Position', style: quiet)),
            DropdownButton<String>(
              value: zone,
              underline: const SizedBox.shrink(),
              icon: const PhosphorIcon(PhosphorIconsRegular.caretDown, size: 14),
              items: [for (final item in _zones.entries) DropdownMenuItem(value: item.key, child: Text(item.value, style: small))],
              onChanged: (value) => setState(() => _zone = value),
            ),
            const SizedBox(width: 10),
            _source(style, 'zone'),
          ],
        ),
        Row(
          children: [
            const SizedBox(width: 72, child: Text('Font', style: quiet)),
            if (_fonts.isEmpty) ...[
              Text(_font ?? '', style: small),
              const SizedBox(width: 8),
              TextButton(onPressed: model.busy ? null : _loadFonts, child: const Text('Choose')),
            ] else
              DropdownButton<String>(
                value: _fonts.contains(_font) ? _font : null,
                underline: const SizedBox.shrink(),
                icon: const PhosphorIcon(PhosphorIconsRegular.caretDown, size: 14),
                hint: Text(_font ?? '', style: small),
                menuMaxHeight: 420,
                items: [for (final font in _fonts) DropdownMenuItem(value: font, child: Text(font, style: small))],
                onChanged: (value) => setState(() => _font = value),
              ),
            const SizedBox(width: 10),
            _source(style, 'font'),
          ],
        ),
        Row(
          children: [
            const SizedBox(width: 72, child: Text('Length', style: quiet)),
            SizedBox(
              width: 220,
              child: Slider(
                min: 1,
                max: 8,
                divisions: 70,
                value: _seconds.clamp(1, 8),
                label: '${_seconds.toStringAsFixed(1)} s',
                onChanged: (value) => setState(() => _seconds = value),
              ),
            ),
            Text('${_seconds.toStringAsFixed(1)} s', style: small),
            const SizedBox(width: 10),
            _source(style, 'title_seconds'),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    if (!model.isOpen) return const Empty('Open a project first');
    final style = model.style;
    return ListView(
      children: [
        Heading(
          'Style',
          'An image or video guides the title and the pace of the cut. It only lends measurements.',
          trailing: ReferenceButtons(model),
        ),
        if (style == null)
          const Text('No reference yet. Without one, titles use the default style.', style: quiet)
        else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _measured(style)),
              const SizedBox(width: 12),
              Expanded(child: _interpreted(style)),
            ],
          ),
          _choices(style),
          Text('Never copied: ${(style['not_copied'] as List).join(', ')}.', style: tiny),
        ],
        const SizedBox(height: 16),
        FindReferences(model),
        const SizedBox(height: 16),
        MusicSection(model),
      ],
    );
  }
}
