import 'package:aie_app/motion.dart';
import 'package:aie_app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {bool reduce = false}) => MediaQuery(
  data: MediaQueryData(disableAnimations: reduce),
  child: Directionality(textDirection: TextDirection.ltr, child: Center(child: child)),
);

double opacityOf(WidgetTester tester) => tester.widget<Opacity>(find.byType(Opacity).first).opacity;

double riseOf(WidgetTester tester) => tester.widget<Transform>(find.byType(Transform).first).transform.getTranslation().y;

void main() {
  testWidgets('news fades and rises in, then settles', (tester) async {
    await tester.pumpWidget(host(const Arrive(child: Text('new'))));
    expect(opacityOf(tester), 0);
    expect(riseOf(tester), 8);
    await tester.pump(Motion.settle ~/ 2);
    expect(opacityOf(tester), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(opacityOf(tester), 1);
    expect(riseOf(tester), 0);
  });

  testWidgets('what was already there does not move', (tester) async {
    await tester.pumpWidget(host(const Arrive(play: false, child: Text('old'))));
    expect(opacityOf(tester), 1);
    expect(riseOf(tester), 0);
  });

  testWidgets('a rebuild that says not to play does not cut an arrival short', (tester) async {
    await tester.pumpWidget(host(const Arrive(key: ValueKey('a'), child: Text('new'))));
    await tester.pump(Motion.settle ~/ 4);
    await tester.pumpWidget(host(const Arrive(key: ValueKey('a'), play: false, child: Text('new'))));
    expect(opacityOf(tester), lessThan(1));
    await tester.pumpAndSettle();
    expect(opacityOf(tester), 1);
  });

  testWidgets('with Reduce Motion it only fades', (tester) async {
    await tester.pumpWidget(host(const Arrive(child: Text('new')), reduce: true));
    expect(riseOf(tester), 0);
    await tester.pump(Motion.settle ~/ 2);
    expect(riseOf(tester), 0);
    expect(opacityOf(tester), inExclusiveRange(0, 1));
  });

  testWidgets('a swap cross-fades between keyed states', (tester) async {
    await tester.pumpWidget(host(const Swap(child: Text('one', key: ValueKey(1)))));
    await tester.pumpWidget(host(const Swap(child: Text('two', key: ValueKey(2)))));
    await tester.pump(Motion.quick ~/ 2);
    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('one'), findsNothing);
  });

  testWidgets('with Reduce Motion a swap doesn\'t slide', (tester) async {
    await tester.pumpWidget(host(const Swap(child: Text('one', key: ValueKey(1))), reduce: true));
    await tester.pumpWidget(host(const Swap(child: Text('two', key: ValueKey(2))), reduce: true));
    await tester.pump(Motion.quick ~/ 2);
    expect(find.byType(SlideTransition), findsNothing);
    expect(find.byType(FadeTransition), findsWidgets);
  });

  testWidgets('a tick draws itself, or appears whole with Reduce Motion', (tester) async {
    await tester.pumpWidget(host(const DrawnCheck()));
    expect(find.byType(TweenAnimationBuilder<double>), findsOneWidget);
    final drawing = tester.widget<TweenAnimationBuilder<double>>(find.byType(TweenAnimationBuilder<double>));
    expect(drawing.tween.begin, 0);
    await tester.pumpWidget(host(const DrawnCheck(key: ValueKey('whole')), reduce: true));
    final whole = tester.widget<TweenAnimationBuilder<double>>(find.byType(TweenAnimationBuilder<double>));
    expect(whole.tween.begin, 1);
  });

  testWidgets('a delayed arrival waits its turn, then plays', (tester) async {
    await tester.pumpWidget(host(const Arrive(delay: Duration(milliseconds: 90), child: Text('third'))));
    await tester.pump(const Duration(milliseconds: 60));
    expect(opacityOf(tester), 0);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(Motion.settle ~/ 2);
    expect(opacityOf(tester), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(opacityOf(tester), 1);
  });

  testWidgets('a number counts up once, or is just there with Reduce Motion', (tester) async {
    await tester.pumpWidget(host(CountUp(120, format: (value) => value.toStringAsFixed(0))));
    expect(find.text('0'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('120'), findsOneWidget);
    await tester.pumpWidget(host(CountUp(98, key: const ValueKey('still'), format: (value) => value.toStringAsFixed(0)), reduce: true));
    expect(find.text('98'), findsOneWidget);
  });

  testWidgets('a beat strip draws left to right once, and whole with Reduce Motion', (tester) async {
    await tester.pumpWidget(host(const SizedBox(width: 200, child: BeatStrip(marks: [.1, .5, .9], energy: [1, .5, 0]))));
    final drawing = tester.widget<TweenAnimationBuilder<double>>(find.byType(TweenAnimationBuilder<double>));
    expect(drawing.tween.begin, 0);
    await tester.pumpWidget(host(const SizedBox(width: 200, child: BeatStrip(key: ValueKey('whole'), marks: [.1], energy: [1])), reduce: true));
    expect(tester.widget<TweenAnimationBuilder<double>>(find.byType(TweenAnimationBuilder<double>)).tween.begin, 1);
  });

  testWidgets('a button gives on the press itself, before release, unless motion is reduced', (tester) async {
    Future<double> pressedScale({bool reduce = false}) async {
      await tester.pumpWidget(MaterialApp(
        theme: graphiteTheme(),
        home: MediaQuery(data: MediaQueryData(disableAnimations: reduce), child: Center(child: FilledButton(onPressed: () {}, child: const Text('Go')))),
      ));
      final gesture = await tester.startGesture(tester.getCenter(find.text('Go')));
      await tester.pumpAndSettle();
      final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
      await gesture.up();
      await tester.pumpAndSettle();
      return scale;
    }

    expect(await pressedScale(), .95);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    expect(await pressedScale(reduce: true), 1);
  });

  testWidgets('a page\'s pieces arrive top to bottom when it opens, and a refresh later doesn\'t replay', (tester) async {
    Widget page(int arrival, DateTime opened) => host(PageEntrance(
      arrival: arrival,
      openedAt: opened,
      // The lower piece is built first, as Flutter may tell it first. Its place on screen still decides.
      child: SizedBox(
        height: 600,
        child: Stack(children: [
          const Positioned(top: 400, left: 0, child: EnterOnPage(child: Text('lower'))),
          const Positioned(top: 0, left: 0, child: EnterOnPage(child: Text('upper'))),
        ]),
      ),
    ));
    double opacity(String text) => tester.widget<Opacity>(find.ancestor(of: find.text(text), matching: find.byType(Opacity)).first).opacity;

    await tester.pumpWidget(page(1, DateTime.now()));
    expect(opacity('upper'), 0);
    expect(opacity('lower'), 0);
    await tester.pump(const Duration(milliseconds: 60));
    expect(opacity('upper'), 0, reason: 'it waits for the page leaving to go');
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 40));
    expect(opacity('upper'), greaterThan(0));
    expect(opacity('lower'), 0, reason: 'what sits lower waits its turn');
    await tester.pumpAndSettle();
    expect(opacity('lower'), 1);

    await tester.pumpWidget(page(1, DateTime.now()));
    await tester.pump();
    expect(opacity('upper'), 1, reason: 'the same opening rebuilt is a refresh');

    await tester.pumpWidget(page(2, DateTime.now().subtract(const Duration(seconds: 5))));
    await tester.pump();
    expect(opacity('upper'), 1, reason: 'too long after opening, so nothing moves');

    await tester.pumpWidget(page(3, DateTime.now()));
    expect(opacity('upper'), 0, reason: 'opening again plays again');
    await tester.pumpAndSettle();
  });

  testWidgets('a page that was never opened doesn\'t animate', (tester) async {
    await tester.pumpWidget(host(PageEntrance(arrival: 0, openedAt: DateTime.now(), child: const EnterOnPage(child: Text('quiet')))));
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
  });
}
