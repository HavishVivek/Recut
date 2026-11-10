import 'package:flutter/material.dart';

import 'motion.dart';
import 'theme.dart';
import 'ui.dart';

/// One stop of the guided tour: a page of the app, what to call it, and what it does in a sentence or two.
class TourStep {
  const TourStep(this.page, this.title, this.body);

  final int page;
  final String title;
  final String body;
}

/// A short guided tour over the real app. Each step opens its page, lights its place in the side bar, and says what
/// it's for. It never blocks for long: Skip ends it at once, and it can be taken again from Settings.
class GuidedTour extends StatefulWidget {
  const GuidedTour({super.key, required this.steps, required this.targets, required this.onPage, required this.onDone});

  final List<TourStep> steps;

  /// The side bar's entries, by page, so a step can light the one it's about.
  final List<GlobalKey> targets;
  final ValueChanged<int> onPage;
  final VoidCallback onDone;

  @override
  State<GuidedTour> createState() => _GuidedTourState();
}

class _GuidedTourState extends State<GuidedTour> {
  int _step = 0;
  Rect? _hole;

  @override
  void initState() {
    super.initState();
    // The tour can start while the shell is building, so its first page opens once the frame is drawn.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _show(0));
    });
  }

  void _show(int step) {
    _step = step;
    widget.onPage(widget.steps[step].page);
    // Where the lit entry is can only be read once it's laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    final target = widget.targets[widget.steps[_step].page].currentContext?.findRenderObject() as RenderBox?;
    final overlay = context.findRenderObject() as RenderBox?;
    if (target == null || overlay == null || !target.hasSize) return;
    final topLeft = overlay.globalToLocal(target.localToGlobal(Offset.zero));
    setState(() => _hole = (topLeft & target.size).inflate(4));
  }

  void _next() => _step + 1 < widget.steps.length ? setState(() => _show(_step + 1)) : widget.onDone();
  void _back() => setState(() => _show(_step - 1));

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_step];
    final hole = _hole;
    return LayoutBuilder(
      builder: (context, box) {
        const cardWidth = 340.0;
        final left = hole == null ? box.maxWidth / 2 - cardWidth / 2 : hole.right + 18;
        final top = hole == null ? box.maxHeight / 2 - 90 : (hole.center.dy - 70).clamp(16.0, box.maxHeight - 220.0);
        return Stack(
          children: [
            // The page shows through, dimmed, with the lit entry clear. A click outside the card goes nowhere.
            Positioned.fill(child: GestureDetector(onTap: () {}, child: CustomPaint(painter: _Dim(hole)))),
            Positioned(
              left: left,
              top: top,
              width: cardWidth,
              child: Arrive(
                key: ValueKey(_step),
                rise: 6,
                child: Material(
                  color: Graphite.raised,
                  borderRadius: BorderRadius.circular(corner),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(corner), border: Border.all(color: Graphite.lineStrong)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_step + 1} of ${widget.steps.length}', style: mono),
                        const SizedBox(height: 6),
                        Text(step.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Graphite.text)),
                        const SizedBox(height: 6),
                        Text(step.body, style: small),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            TextButton(onPressed: widget.onDone, child: const Text('Skip tour')),
                            const Spacer(),
                            if (_step > 0) TextButton(onPressed: _back, child: const Text('Back')),
                            const SizedBox(width: 4),
                            FilledButton(onPressed: _next, child: Text(_step + 1 == widget.steps.length ? 'Done' : 'Next')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Dim extends CustomPainter {
  const _Dim(this.hole);

  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final everything = Path()..addRect(Offset.zero & size);
    final cut = hole == null ? everything : Path.combine(PathOperation.difference, everything, Path()..addRRect(RRect.fromRectAndRadius(hole!, const Radius.circular(smallCorner))));
    canvas.drawPath(cut, Paint()..color = Graphite.canvas.withValues(alpha: .72));
    if (hole != null) {
      canvas.drawRRect(RRect.fromRectAndRadius(hole!, const Radius.circular(smallCorner)), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Graphite.mint);
    }
  }

  @override
  bool shouldRepaint(_Dim old) => old.hole != hole;
}

/// The tour's stops, in the order a new person meets the app. Each sentence says only what the app does today.
const tourSteps = [
  TourStep(0, 'Start with a project', 'Make or open one. Your footage stays where it is: a project only points at it.'),
  TourStep(1, 'Your clips', 'Add a clip and AI Editor listens to every word, here on this Mac.'),
  TourStep(3, 'Review the edit', 'Each change is a new revision with its own checks. Preview it before anything is built.'),
  TourStep(4, 'Build it in Resolve', 'Nothing reaches DaVinci Resolve until you approve it, and every build is read back.'),
  TourStep(5, 'Ask in words', 'Say what to change, or describe a new video. You get a draft with a storyboard before anything renders.'),
  TourStep(6, 'Make from a form', 'Title cards, callouts, a phone mockup, lower thirds: fill in a form, see a still, make it.'),
  TourStep(8, 'Everything runs here', 'Install the local models once, here. Your footage never leaves this Mac.'),
  TourStep(9, 'Your account', 'Sign in to unlock Pro, add your brand kit, or take this tour again.'),
];
