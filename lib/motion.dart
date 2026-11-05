import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// How things move. Every animation reads this, so Reduce Motion is honoured everywhere.
///
/// With Reduce Motion on, slides, scales and drawing go, and fades stay, because a fade
/// helps reading and doesn't move anything. Motion is critically damped: nothing bounces,
/// because nothing here was thrown.
abstract final class Motion {
  /// A state changing in place: a label, a colour, a mark.
  static const quick = Duration(milliseconds: 160);

  /// Something arriving or a page changing.
  static const settle = Duration(milliseconds: 240);

  /// Long enough to see what changed, then gone.
  static const wash = Duration(milliseconds: 900);

  static const curve = Curves.easeOutCubic;

  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// macOS's Reduce Motion setting. Flutter's Mac engine doesn't pass it on, so the window does.
class ReduceMotion extends ValueNotifier<bool> {
  ReduceMotion._() : super(false) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') value = call.arguments == true;
    });
    _channel.invokeMethod<bool>('get').then((on) => value = on == true, onError: (_) {});
  }

  static const _channel = MethodChannel('aie/motion');
  static final instance = ReduceMotion._();
}

/// Plays once when it first appears: a fade, and a short rise unless motion is reduced.
/// `play` is read once, so a page that rebuilds while polling can't cut it short. Pass false
/// for what was already there when a page opened, so only news moves. Key it by what it shows.
/// `delay` lets a list arrive one row after another.
class Arrive extends StatefulWidget {
  const Arrive({super.key, required this.child, this.play = true, this.rise = 8, this.delay = Duration.zero});

  final Widget child;
  final bool play;
  final double rise;
  final Duration delay;

  @override
  State<Arrive> createState() => _ArriveState();
}

class _ArriveState extends State<Arrive> with SingleTickerProviderStateMixin {
  late final AnimationController _shown = AnimationController(vsync: this, duration: Motion.settle, value: widget.play ? 0 : 1);
  late final Animation<double> _eased = CurvedAnimation(parent: _shown, curve: Motion.curve);

  @override
  void initState() {
    super.initState();
    if (!widget.play) return;
    if (widget.delay == Duration.zero) {
      _shown.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _shown.forward();
      });
    }
  }

  @override
  void dispose() {
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    return AnimatedBuilder(
      animation: _eased,
      child: widget.child,
      // The same wrappers whatever the moment, so the child is never rebuilt from scratch.
      builder: (context, child) => Opacity(
        opacity: _eased.value,
        child: Transform.translate(offset: Offset(0, reduced ? 0 : widget.rise * (1 - _eased.value)), child: child),
      ),
    );
  }
}

/// A number that counts up to its value once, when it first appears. With Reduce Motion it's just there.
class CountUp extends StatelessWidget {
  const CountUp(this.value, {super.key, required this.format, this.style, this.play = true});

  final double value;
  final String Function(double value) format;
  final TextStyle? style;
  final bool play;

  @override
  Widget build(BuildContext context) {
    final still = !play || Motion.reduced(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: still ? value : 0, end: value),
      duration: const Duration(milliseconds: 420),
      curve: Motion.curve,
      builder: (context, shown, _) => Text(format(shown), style: style),
    );
  }
}

/// Ticks for a track's beats, taller where the music is louder, drawn left to right once.
class BeatStrip extends StatelessWidget {
  const BeatStrip({super.key, required this.marks, required this.energy, this.play = true, this.height = 22});

  /// Where each beat falls, from 0 at the start of the track to 1 at its end.
  final List<double> marks;
  final List<double> energy;
  final bool play;
  final double height;

  @override
  Widget build(BuildContext context) {
    final still = !play || Motion.reduced(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: still ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOutCubic,
      builder: (context, drawn, _) => CustomPaint(size: Size(double.infinity, height), painter: _BeatPainter(marks, energy, drawn)),
    );
  }
}

class _BeatPainter extends CustomPainter {
  _BeatPainter(this.marks, this.energy, this.drawn);

  final List<double> marks;
  final List<double> energy;
  final double drawn;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Graphite.muted
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, size.height - .5), Offset(size.width * drawn, size.height - .5), Paint()..color = Graphite.line);
    for (final (index, mark) in marks.indexed) {
      if (mark > drawn) break;
      final loud = index < energy.length ? energy[index] : 1.0;
      final tall = size.height * (.3 + .7 * loud);
      final x = mark * size.width;
      canvas.drawLine(Offset(x, size.height - 1), Offset(x, size.height - tall), paint);
    }
  }

  @override
  bool shouldRepaint(_BeatPainter old) => old.drawn != drawn || old.marks != marks || old.energy != energy;
}

/// Swaps one thing for another with a cross-fade, and a short rise unless motion is reduced.
/// Give each state's child its own key, or nothing changes.
class Swap extends StatelessWidget {
  const Swap({super.key, required this.child, this.alignment = Alignment.centerLeft});

  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    return AnimatedSwitcher(
      duration: Motion.quick,
      switchInCurve: Motion.curve,
      switchOutCurve: Motion.curve,
      layoutBuilder: (current, previous) => Stack(alignment: alignment, children: [...previous, ?current]),
      transitionBuilder: (child, animation) {
        final fade = FadeTransition(opacity: animation, child: child);
        if (reduced) return fade;
        return SlideTransition(
          position: Tween(begin: const Offset(0, .25), end: Offset.zero).animate(animation),
          child: fade,
        );
      },
      child: child,
    );
  }
}

/// A tick that draws itself left to right. With Reduce Motion it appears whole.
class DrawnCheck extends StatelessWidget {
  const DrawnCheck({super.key, this.size = 12, this.color = Graphite.mint});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduced ? 1 : 0, end: 1),
      duration: Motion.settle,
      curve: Curves.easeInOutCubic,
      builder: (context, t, _) => CustomPaint(size: Size.square(size), painter: _CheckPainter(t, color)),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * .14, size.height * .54)
      ..lineTo(size.width * .40, size.height * .78)
      ..lineTo(size.width * .88, size.height * .24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, size.width / 7)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * progress), paint);
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress || old.color != color;
}

/// Which page is opening, and when. Headings and sections read it to arrive top to bottom: the
/// heading first, then each section a moment after the one above. Only the first moment after a
/// page opens counts, so a page that refreshes while you read it never replays.
class PageEntrance extends InheritedWidget {
  const PageEntrance({super.key, required this.arrival, required this.openedAt, required super.child});

  /// Counts up each time the page opens. Zero is a page not opened yet.
  final int arrival;
  final DateTime openedAt;

  static PageEntrance? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PageEntrance>();

  @override
  bool updateShouldNotify(PageEntrance old) => arrival != old.arrival;
}

/// Fades and rises into place as its page opens, after whatever sits above it on screen.
///
/// Its turn comes from where it really is, measured after layout. Flutter tells waiting widgets in
/// no particular order, and going by that once brought a page's heading in last.
class EnterOnPage extends StatefulWidget {
  const EnterOnPage({super.key, required this.child});

  final Widget child;

  static const rise = 18.0;
  static const step = Duration(milliseconds: 55);
  // About one section's height. Everything this far further down waits one more step.
  static const band = 90.0;
  static const longest = 7;
  // The page leaving fades over this, and the first piece waits for it.
  static const lead = Duration(milliseconds: 70);
  // The status bar sits above every page, so places are counted from below it.
  static const pageTop = 56.0;
  // Past this, the page has opened and anything new is a refresh, which shouldn't move.
  static const window = Duration(milliseconds: 900);

  @override
  State<EnterOnPage> createState() => _EnterOnPageState();
}

class _EnterOnPageState extends State<EnterOnPage> with SingleTickerProviderStateMixin {
  late final AnimationController _shown = AnimationController(vsync: this, duration: const Duration(milliseconds: 340), value: 1);
  late final Animation<double> _eased = CurvedAnimation(parent: _shown, curve: Motion.curve);
  int? _played;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final entrance = PageEntrance.of(context);
    if (entrance == null || entrance.arrival == 0 || entrance.arrival == _played) return;
    _played = entrance.arrival;
    if (DateTime.now().difference(entrance.openedAt) > EnterOnPage.window) return;
    _shown.value = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject();
      final top = box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero).dy : 0.0;
      final place = ((top - EnterOnPage.pageTop) / EnterOnPage.band).floor().clamp(0, EnterOnPage.longest);
      Future<void>.delayed(EnterOnPage.lead + EnterOnPage.step * place, () {
        if (mounted) _shown.forward();
      });
    });
  }

  @override
  void dispose() {
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    return AnimatedBuilder(
      animation: _eased,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _eased.value,
        child: Transform.translate(offset: Offset(0, reduced ? 0 : EnterOnPage.rise * (1 - _eased.value)), child: child),
      ),
    );
  }
}
