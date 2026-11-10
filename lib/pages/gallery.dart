import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../engine.dart';
import '../motion.dart';
import '../project.dart';
import '../theme.dart';
import '../ui.dart';
import 'assistant.dart' show MadeVideo;

/// The gallery's name for the brand kit's logo. A logo field carries this, never a path.
const brandLogo = 'Brand kit logo';

/// Animations made from a form: pick a template, fill it in with your own words and photos, see a still, make it.
class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key, required this.model, required this.visible, this.enablePreview = false});

  final ProjectModel model;
  final bool visible;
  final bool enablePreview;

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  Json? _gallery;
  Json? _chosen;
  final Map<String, dynamic> _values = {};
  final Map<String, TextEditingController> _typed = {};
  String _shape = 'upright';
  String? _still;
  bool _stillIsOverlay = false;
  List<String> _problems = const [];
  String? _said;
  Json? _made;
  Timer? _waiting;
  int _asked = 0;

  ProjectModel get model => widget.model;

  @override
  void didUpdateWidget(GalleryPage old) {
    super.didUpdateWidget(old);
    if (widget.visible && !old.visible) _later();
  }

  @override
  void initState() {
    super.initState();
    if (widget.visible) _later();
  }

  // A job can't start while the shell is building, so it starts once the frame is drawn.
  void _later() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });

  @override
  void dispose() {
    _waiting?.cancel();
    for (final controller in _typed.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (!model.isOpen) return;
    final outcome = await model.run('gallery', {}, 'Opening the gallery', quiet: true);
    if (!mounted || outcome?['state'] != 'done') return;
    setState(() => _gallery = outcome!['result'] as Json);
  }

  List<Json> get _templates => ((_gallery?['templates'] as List?) ?? const []).cast<Json>();
  List<Json> get _fields => ((_chosen?['fields'] as List?) ?? const []).cast<Json>();
  List<String> get _photos => ((_gallery?['photos'] as List?) ?? const []).cast<String>();
  List<Json> get _clips => ((_gallery?['clips'] as List?) ?? const []).cast<Json>();

  void _choose(Json? template) {
    _waiting?.cancel();
    for (final controller in _typed.values) {
      controller.dispose();
    }
    _typed.clear();
    _values.clear();
    for (final field in ((template?['fields'] as List?) ?? const []).cast<Json>()) {
      final initial = field['default'] as String? ?? '';
      if (initial.isNotEmpty) _values[field['key'] as String] = initial;
    }
    setState(() {
      _chosen = template;
      _still = null;
      _problems = const [];
      _said = null;
      _made = null;
    });
  }

  void _set(String key, dynamic value) {
    _values[key] = value;
    _made = null;
    _waiting?.cancel();
    // A still is drawn once a person pauses, not on every key.
    _waiting = Timer(const Duration(milliseconds: 700), _preview);
    setState(() {});
  }

  void _reshape(String shape) {
    _shape = shape;
    _made = null;
    _waiting?.cancel();
    _waiting = Timer(const Duration(milliseconds: 300), _preview);
    setState(() {});
  }

  Json _body() => {'template': _chosen!['id'], 'values': Map<String, dynamic>.from(_values), 'shape': _shape};

  Future<void> _preview() async {
    if (_chosen == null || !mounted) return;
    if (model.busy) {
      _waiting = Timer(const Duration(milliseconds: 600), _preview);
      return;
    }
    final asked = ++_asked;
    final outcome = await model.run('template_preview', _body(), 'Drawing ${(_chosen!['name'] as String).toLowerCase()}', quiet: true);
    if (!mounted || asked != _asked) return;
    setState(() {
      if (outcome?['state'] == 'done') {
        final result = outcome!['result'] as Json;
        _still = result['path'] as String;
        _stillIsOverlay = result['overlay'] == true;
        _problems = ((result['problems'] as List?) ?? const []).cast<String>();
        _said = null;
      } else {
        // What's still missing is said in the person's words, beside the form.
        _said = outcome?['error'] as String?;
      }
    });
  }

  Future<void> _make() async {
    final name = _chosen!['name'] as String;
    final outcome = await model.run('make_template', _body(), 'Making ${name.toLowerCase()}');
    if (!mounted) return;
    setState(() {
      if (outcome?['state'] == 'done') {
        _made = outcome!['result'] as Json;
        _said = null;
      } else {
        _said = outcome?['error'] as String?;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!model.isOpen) return const Empty('Open a project first');
    final chosen = _chosen;
    return ListView(
      children: [
        Heading(
          chosen == null ? 'Make' : chosen['name'] as String,
          chosen == null ? 'Animations from a form: your words, your photos, no conversation' : chosen['about'] as String,
          trailing: chosen == null ? null : TextButton.icon(onPressed: () => _choose(null), icon: const PhosphorIcon(PhosphorIconsRegular.squaresFour, size: 14), label: const Text('All templates')),
        ),
        if (_gallery == null) const Padding(padding: EdgeInsets.all(16), child: Text('Opening the gallery…', style: quiet)),
        if (_gallery != null && chosen == null) _grid(),
        if (chosen != null) _editor(chosen),
      ],
    );
  }

  Widget _grid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final (index, template) in _templates.indexed)
            Arrive(
              key: ValueKey('card-${template['id']}'),
              delay: Duration(milliseconds: 30 * index),
              child: _TemplateCard(template: template, onTap: () => _choose(template)),
            ),
        ],
      ),
    );
  }

  Widget _editor(Json chosen) {
    final made = _made;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final field in _fields) Padding(padding: const EdgeInsets.only(bottom: 14), child: _field(field)),
                  _shapePicker(),
                  const SizedBox(height: 14),
                  if (_said != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Alert(_said!)),
                  for (final problem in _problems) Padding(padding: const EdgeInsets.only(bottom: 6), child: Alert(problem, color: bad)),
                  Row(
                    children: [
                      FilledButton(onPressed: model.busy || _problems.isNotEmpty ? null : _make, child: const Text('Make it')),
                      const SizedBox(width: 10),
                      Text('${chosen['seconds']} seconds${chosen['overlay'] == true ? ', with a clear background' : ''}', style: tiny),
                    ],
                  ),
                  if (made != null) ...[
                    const SizedBox(height: 16),
                    Arrive(key: ValueKey(made['path']), child: _result(made)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(width: 300, child: _stillView()),
        ],
      ),
    );
  }

  Widget _result(Json made) {
    final path = made['path'] as String;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [const DrawnCheck(size: 14), const SizedBox(width: 8), Expanded(child: Text(made['answer'] as String? ?? '', style: small))]),
        if (made['overlay'] != true)
          MadeVideo(video: {'path': path, 'scenes': const [], 'upright': made['upright'] == true}, onChangeScene: (_) {}, enablePreview: widget.enablePreview),
        RevealButton(() => reveal(path)),
      ],
    );
  }

  Widget _stillView() {
    final still = _still;
    final aspect = switch (_shape) { 'square' => 1.0, 'wide' => 16 / 9, _ => 9 / 16 };
    return Panel(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Preview', style: tiny),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: aspect,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(smallCorner),
              child: Swap(
                alignment: Alignment.center,
                child: still == null
                    ? Container(key: const ValueKey('none'), color: Graphite.raised, alignment: Alignment.center, child: const Text('Fill it in to see it', style: tiny))
                    : Stack(
                        key: ValueKey(still),
                        fit: StackFit.expand,
                        children: [
                          // An overlay is shown over a checkerboard, so its clear background reads as clear.
                          if (_stillIsOverlay) const CustomPaint(painter: _Checks()),
                          Image.file(File(still), fit: BoxFit.contain, gaplessPlayback: true),
                          if (_shape == 'upright') const SafeZones(),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shapePicker() {
    return Row(
      children: [
        const Text('Shape  ', style: tiny),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'upright', label: Text('9:16')),
            ButtonSegment(value: 'square', label: Text('1:1')),
            ButtonSegment(value: 'wide', label: Text('16:9')),
          ],
          selected: {_shape},
          showSelectedIcon: false,
          onSelectionChanged: (picked) => _reshape(picked.first),
        ),
      ],
    );
  }

  TextEditingController _controller(String key) => _typed.putIfAbsent(key, () => TextEditingController(text: _textOf(_values[key])));

  String _textOf(dynamic value) => value is List ? value.join('\n') : (value as String? ?? '');

  Widget _field(Json field) {
    final key = field['key'] as String;
    final label = field['label'] as String;
    final hint = field['hint'] as String? ?? '';
    final limit = field['limit'] as int? ?? 40;
    final required = field['required'] == true;
    final title = Text(required ? label : '$label (optional)', style: tiny);
    switch (field['kind']) {
      case 'text':
        return TextField(
          controller: _controller(key),
          maxLength: limit,
          buildCounter: nearLimitCounter,
          decoration: InputDecoration(labelText: required ? label : '$label (optional)', hintText: hint),
          onChanged: (text) => _set(key, text),
        );
      case 'lines':
      case 'wires':
      case 'code':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            const SizedBox(height: 4),
            TextField(
              controller: _controller(key),
              minLines: field['kind'] == 'code' ? 6 : 3,
              maxLines: field['kind'] == 'code' ? 14 : 6,
              style: field['kind'] == 'code' ? mono.copyWith(color: Graphite.text) : null,
              decoration: InputDecoration(hintText: hint, helperText: 'Up to ${field['most']} lines'),
              onChanged: (text) => _set(key, text.split('\n').where((line) => line.trim().isNotEmpty).toList()),
            ),
          ],
        );
      case 'photo':
        return _picker(key, title, [
          for (final photo in _photos) (photo, photo),
          if (_gallery?['brand_logo'] == true && key == 'logo') (brandLogo, brandLogo),
        ], empty: 'Add photos on the Assistant page first.');
      case 'media':
        return _picker(key, title, [
          for (final photo in _photos) (photo, photo),
          for (final clip in _clips) ('clip:${clip['id']}', clip['name'] as String),
        ], empty: 'Add a screenshot as a photo, or a recording as a clip.');
      case 'part':
        final parts = ((_gallery?['parts'] as List?) ?? const []).cast<Json>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: _controller(key), decoration: InputDecoration(labelText: label, hintText: 'Such as HC-05, or any part'), onChanged: (text) => _set(key, text)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final part in parts)
                ActionChip(
                  label: Text(part['name'] as String, style: tiny),
                  onPressed: () {
                    _controller(key).text = part['name'] as String;
                    _set(key, part['name']);
                  },
                ),
            ]),
          ],
        );
      case 'spots':
        return _SpotPicker(
          photo: _photoPath(_values['photo'] as String?),
          spots: ((_values[key] as List?) ?? const []).cast<Json>(),
          most: field['most'] as int? ?? 3,
          limit: limit,
          onChanged: (spots) => _set(key, spots),
        );
    }
    return Text(label, style: tiny);
  }

  String? _photoPath(String? name) {
    if (name == null) return null;
    final found = model.photos.where((photo) => photo['name'] == name);
    return found.isEmpty ? null : found.first['path'] as String;
  }

  Widget _picker(String key, Widget title, List<(String, String)> options, {required String empty}) {
    final current = _values[key] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        const SizedBox(height: 4),
        if (options.isEmpty)
          Text(empty, style: quiet)
        else
          DropdownButton<String>(
            value: options.any((option) => option.$1 == current) ? current : null,
            hint: const Text('Choose one', style: quiet),
            isExpanded: true,
            items: [for (final (value, shown) in options) DropdownMenuItem(value: value, child: Text(shown, overflow: TextOverflow.ellipsis))],
            onChanged: (value) => _set(key, value),
          ),
      ],
    );
  }
}

class _TemplateCard extends StatefulWidget {
  const _TemplateCard({required this.template, required this.onTap});

  final Json template;
  final VoidCallback onTap;

  @override
  State<_TemplateCard> createState() => _TemplateCardState();
}

class _TemplateCardState extends State<_TemplateCard> {
  bool _over = false;

  static const _icons = {
    'title_card': PhosphorIconsRegular.textT,
    'lower_third': PhosphorIconsRegular.identificationBadge,
    'product_reveal': PhosphorIconsRegular.sparkle,
    'callout': PhosphorIconsRegular.crosshair,
    'device': PhosphorIconsRegular.deviceMobile,
    'code_card': PhosphorIconsRegular.code,
    'wiring': PhosphorIconsRegular.plugs,
    'count_up': PhosphorIconsRegular.numberSquareNine,
    'bars': PhosphorIconsRegular.chartBar,
    'scope': PhosphorIconsRegular.waveSquare,
    'checklist': PhosphorIconsRegular.listChecks,
    'flow': PhosphorIconsRegular.flowArrow,
    'before_after': PhosphorIconsRegular.splitHorizontal,
    'logo_sting': PhosphorIconsRegular.seal,
  };

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    final template = widget.template;
    return MouseRegion(
      onEnter: (_) => setState(() => _over = true),
      onExit: (_) => setState(() => _over = false),
      child: AnimatedSlide(
        // A card lifts a little under the pointer. With Reduce Motion, only its edge changes.
        offset: _over && !reduced ? const Offset(0, -.02) : Offset.zero,
        duration: Motion.quick,
        curve: Motion.curve,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(corner),
          child: AnimatedContainer(
            duration: Motion.quick,
            curve: Motion.curve,
            width: 220,
            height: 132,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _over ? Graphite.hover : Graphite.surface,
              borderRadius: BorderRadius.circular(corner),
              border: Border.all(color: _over ? Graphite.lineStrong : Graphite.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  PhosphorIcon(_icons[template['id']] ?? PhosphorIconsRegular.sparkle, size: 18, color: Graphite.text),
                  const SizedBox(width: 8),
                  Expanded(child: Text(template['name'] as String, style: small.copyWith(fontWeight: FontWeight.w600))),
                  if (template['overlay'] == true) const Tag('overlay'),
                ]),
                const SizedBox(height: 8),
                Expanded(child: Text(template['about'] as String, style: tiny, maxLines: 3, overflow: TextOverflow.fade)),
                Text('${template['seconds']} s', style: mono),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The person's photo: a click places a spot, and each spot gets the label they type. Spots are shares of the photo.
class _SpotPicker extends StatelessWidget {
  const _SpotPicker({required this.photo, required this.spots, required this.most, required this.limit, required this.onChanged});

  final String? photo;
  final List<Json> spots;
  final int most;
  final int limit;
  final ValueChanged<List<Json>> onChanged;

  @override
  Widget build(BuildContext context) {
    final photo = this.photo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Spots: click the photo to place up to $most, then name each', style: tiny),
        const SizedBox(height: 6),
        if (photo == null)
          const Text('Choose the photo first.', style: quiet)
        else
          LayoutBuilder(
            builder: (context, box) {
              return _PhotoSpots(
                photo: photo,
                spots: spots,
                width: box.maxWidth.clamp(120, 420).toDouble(),
                onTap: spots.length >= most ? null : (x, y) => onChanged([...spots, {'label': '', 'x': x, 'y': y}]),
              );
            },
          ),
        for (final (index, spot) in spots.indexed)
          Padding(
            key: ValueKey('spot-$index-${spot['x']}-${spot['y']}'),
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: Graphite.mint, shape: BoxShape.circle),
                  child: Text('${index + 1}', style: const TextStyle(fontSize: 11, color: Graphite.onMint)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: spot['label'] as String? ?? '',
                    maxLength: limit,
                    buildCounter: nearLimitCounter,
                    decoration: const InputDecoration(hintText: 'What it is', isDense: true),
                    onChanged: (text) => onChanged([for (final (other, item) in spots.indexed) other == index ? {...item, 'label': text} : item]),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove this spot',
                  onPressed: () => onChanged([for (final (other, item) in spots.indexed) if (other != index) item]),
                  icon: const PhosphorIcon(PhosphorIconsRegular.x, size: 14),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PhotoSpots extends StatelessWidget {
  const _PhotoSpots({required this.photo, required this.spots, required this.width, required this.onTap});

  final String photo;
  final List<Json> spots;
  final double width;
  final void Function(double x, double y)? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: LayoutBuilder(
          builder: (context, box) {
            return FutureBuilder<Size>(
              future: _sizeOf(photo),
              builder: (context, sized) {
                final size = sized.data;
                if (size == null) return const SizedBox.shrink();
                // Where the photo actually sits inside the box, so a click maps to the photo, not the box around it.
                final scale = (box.maxWidth / size.width) < (box.maxHeight / size.height) ? box.maxWidth / size.width : box.maxHeight / size.height;
                final shown = Size(size.width * scale, size.height * scale);
                final offset = Offset((box.maxWidth - shown.width) / 2, (box.maxHeight - shown.height) / 2);
                return GestureDetector(
                  onTapUp: onTap == null
                      ? null
                      : (details) {
                          final at = details.localPosition - offset;
                          if (at.dx < 0 || at.dy < 0 || at.dx > shown.width || at.dy > shown.height) return;
                          onTap!(double.parse((at.dx / shown.width).toStringAsFixed(4)), double.parse((at.dy / shown.height).toStringAsFixed(4)));
                        },
                  child: MouseRegion(
                    cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.precise,
                    child: Stack(
                      children: [
                        Positioned(left: offset.dx, top: offset.dy, width: shown.width, height: shown.height, child: Image.file(File(photo), fit: BoxFit.fill)),
                        for (final (index, spot) in spots.indexed)
                          Positioned(
                            left: offset.dx + (spot['x'] as num) * shown.width - 11,
                            top: offset.dy + (spot['y'] as num) * shown.height - 11,
                            child: Arrive(
                              key: ValueKey('mark-$index-${spot['x']}'),
                              rise: 0,
                              child: Container(
                                width: 22,
                                height: 22,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Graphite.mint, width: 2), color: Graphite.canvas.withValues(alpha: .4)),
                                child: Text('${index + 1}', style: const TextStyle(fontSize: 11, color: Graphite.mint)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

final _sizes = <String, Future<Size>>{};

Future<Size> _sizeOf(String path) => _sizes.putIfAbsent(path, () async {
      final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
      final frame = await codec.getNextFrame();
      final size = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
      frame.image.dispose();
      codec.dispose();
      return size;
    });

class _Checks extends CustomPainter {
  const _Checks();

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 12.0;
    final light = Paint()..color = const Color(0xFF3A3C42);
    final dark = Paint()..color = const Color(0xFF2B2D32);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), ((x + y) ~/ cell).isEven ? light : dark);
      }
    }
  }

  @override
  bool shouldRepaint(_Checks old) => false;
}
