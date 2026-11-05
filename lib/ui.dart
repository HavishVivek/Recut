import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'motion.dart';
import 'theme.dart';

const quiet = TextStyle(fontSize: 13, color: Graphite.muted);
const small = TextStyle(fontSize: 13, color: Graphite.text);
const tiny = TextStyle(fontSize: 12, color: Graphite.muted);
const good = Graphite.mint;
const waiting = Graphite.amber;
const bad = Graphite.coral;

/// For anything exact: frames, times, IDs, hashes and paths.
const mono = TextStyle(fontFamily: monospace, fontSize: 12, color: Graphite.muted);

/// A flat surface with a hairline edge. Depth comes from these steps, not from shadows.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.enter = true});

  final Widget child;
  final EdgeInsets padding;

  /// Arrive in line as the page opens. A panel inside a section arrives with the section.
  final bool enter;

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Graphite.surface,
        borderRadius: BorderRadius.circular(corner),
        border: Border.all(color: Graphite.line),
      ),
      child: child,
    );
    return enter ? EnterOnPage(child: panel) : panel;
  }
}

class Heading extends StatelessWidget {
  const Heading(this.title, this.subtitle, {super.key, this.trailing});

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return EnterOnPage(
      child: Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(subtitle, style: quiet),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
      ),
    );
  }
}

class Section extends StatelessWidget {
  const Section(this.title, {super.key, required this.children, this.trailing});

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
                ?trailing,
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class Dot extends StatelessWidget {
  const Dot(this.color, {super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class Status extends StatelessWidget {
  const Status(this.text, this.color, {super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Dot(color),
        const SizedBox(width: 8),
        Flexible(child: Text(text, style: TextStyle(fontSize: 12, color: color))),
      ],
    );
  }
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color = Graphite.muted});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color == Graphite.muted ? Graphite.lineStrong : color.withValues(alpha: .5)),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}

/// A labelled fact. Selectable, because people paste these into bug reports.
class Fact extends StatelessWidget {
  const Fact(this.name, this.value, {super.key, this.width = 130, this.exact = false});

  final String name;
  final String value;
  final double width;

  /// Paths, hashes and IDs read better in the technical face.
  final bool exact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: width, child: Text(name, style: quiet)),
          Expanded(child: SelectableText(value, style: exact ? mono.copyWith(color: Graphite.text) : small)),
        ],
      ),
    );
  }
}

/// A warning a person should read before going on.
class Alert extends StatelessWidget {
  const Alert(this.text, {super.key, this.color = waiting, this.action});

  final String text;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(smallCorner),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: color))),
          ?action,
        ],
      ),
    );
  }
}

/// Shown on a page that needs something earlier in the flow.
class Empty extends StatelessWidget {
  const Empty(this.text, {super.key, this.action, this.icon = PhosphorIconsDuotone.folderOpen});

  final String text;
  final Widget? action;
  final PhosphorIconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PhosphorIcon(icon, size: 36, color: Graphite.faint),
          const SizedBox(height: 12),
          Text(text, style: quiet),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

/// Opens a file in Finder.
class RevealButton extends StatelessWidget {
  const RevealButton(this.onPressed, {super.key, this.label = 'Show in Finder'});

  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextButton(onPressed: onPressed, child: Text(label));
  }
}

/// One video player. Pages keep theirs alive so playback survives moving around.
class Screen {
  Screen(bool enabled) {
    if (enabled) {
      player = Player();
      controller = VideoController(player!);
      player!.stream.position.listen((value) => position.value = value);
    }
  }

  Player? player;
  VideoController? controller;
  final position = ValueNotifier<Duration>(Duration.zero);
  String? _showing;

  bool get available => controller != null;

  /// Shows a file, starting from `at` if given, as soon as the player can seek in it.
  Future<void> show(String? path, {Duration? at}) async {
    if (path == _showing) {
      if (at != null) seek(at);
      return;
    }
    _showing = path;
    if (path == null) {
      await player?.stop();
      position.value = Duration.zero;
    } else {
      await player?.open(Media(path), play: false);
      // Captions can be a track in the file, and a player leaves those off.
      await player?.setSubtitleTrack(SubtitleTrack.auto());
      if (at != null) {
        await player?.stream.duration.firstWhere((length) => length > Duration.zero).timeout(const Duration(seconds: 5), onTimeout: () => Duration.zero);
        seek(at);
      }
    }
  }

  void seek(Duration to) {
    position.value = to;
    player?.seek(to);
  }

  void dispose() {
    player?.dispose();
    position.dispose();
  }
}

class ScreenView extends StatelessWidget {
  const ScreenView(this.screen, {super.key, this.placeholder});

  final Screen screen;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    final controller = screen.controller;
    return ClipRRect(
      borderRadius: BorderRadius.circular(corner),
      child: ColoredBox(
        color: Colors.black,
        child: controller == null
            ? Center(child: placeholder ?? const Text('Preview unavailable', style: quiet))
            : Stack(
                fit: StackFit.expand,
                children: [
                  Video(controller: controller),
                  if (placeholder != null) Center(child: placeholder),
                ],
              ),
      ),
    );
  }
}

String clock(num seconds) {
  final whole = seconds.floor();
  final minutes = (whole ~/ 60).toString().padLeft(2, '0');
  final rest = (whole % 60).toString().padLeft(2, '0');
  return '$minutes:$rest';
}

/// Tenths matter when a note lands on a cut.
String fineClock(num seconds) {
  final minutes = seconds ~/ 60;
  final rest = (seconds - minutes * 60).toStringAsFixed(1).padLeft(4, '0');
  return '$minutes:$rest';
}

String formatTime(Duration d) => clock(d.inSeconds);

/// Frames and their time together, because frames are what's exact.
String frameAndTime(num frame, num fps) =>
    '$frame  (${fineClock(frame / fps)})';

/// A long path's end is the part that tells folders apart.
String endOfPath(String path) {
  final parts = path.split('/').where((part) => part.isNotEmpty).toList();
  return !path.startsWith('/') || parts.length <= 3 ? path : '…/${parts.sublist(parts.length - 3).join('/')}';
}

Color colourFrom(String hex) =>
    Color(int.parse(hex.substring(1), radix: 16) + 0xFF000000);
