import 'package:flutter/material.dart';

/// Every colour in the app. Neutral graphite, so footage is the most colourful thing on
/// screen. Mint marks what's active or primary and nothing else.
class Graphite {
  static const canvas = Color(0xFF111214);
  static const surface = Color(0xFF18191C);
  static const raised = Color(0xFF202125);
  static const hover = Color(0xFF26282D);
  static const line = Color(0xFF2B2D32);
  static const lineStrong = Color(0xFF3B3E45);
  static const text = Color(0xFFE6E7E9);
  static const muted = Color(0xFFA0A3AA);
  static const faint = Color(0xFF70737B);
  static const mint = Color(0xFF6EE7B7);
  static const onMint = Color(0xFF0A1F17);
  static const amber = Color(0xFFE3B778);
  static const coral = Color(0xFFEE8F85);
}

const sans = 'Geist';
const monospace = 'GeistMono';
const corner = 8.0;
const smallCorner = 6.0;

const clear = WidgetStatePropertyAll<Color>(Colors.transparent);

/// Draws a button's fill and border inside a scale, so the whole button gives a little the
/// moment it's pressed, before the click lands. Material paints its own fill outside anything
/// a style can scale, so the fill moves in here and Material's is left clear.
ButtonLayerBuilder pressable({Color? fill, required Color hover, Color? disabled, Color? border, Color? disabledBorder}) =>
    (context, states, child) => PressedButton(states: states, fill: fill, hover: hover, disabled: disabled, border: border, disabledBorder: disabledBorder, child: child!);

/// The quieter filled button. The theme's fill is mint, which marks only what's primary, so a
/// tonal button names its own.
final tonal = ButtonStyle(backgroundBuilder: pressable(fill: Graphite.raised, hover: Graphite.hover, disabled: Graphite.surface));

class PressedButton extends StatelessWidget {
  const PressedButton({super.key, required this.states, required this.child, required this.hover, this.fill, this.disabled, this.border, this.disabledBorder});

  final Set<WidgetState> states;
  final Widget child;
  final Color? fill;
  final Color hover;
  final Color? disabled;
  final Color? border;
  final Color? disabledBorder;

  @override
  Widget build(BuildContext context) {
    final off = states.contains(WidgetState.disabled);
    final pressed = !off && states.contains(WidgetState.pressed);
    final over = !off && (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused));
    final color = off ? (disabled ?? fill) : over ? hover : fill;
    final edge = off ? (disabledBorder ?? border) : border;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnimatedScale(
      scale: pressed && !still ? .95 : 1,
      // In fast, so it answers the press; out at the usual pace.
      duration: pressed ? const Duration(milliseconds: 80) : const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: color ?? Colors.transparent,
          borderRadius: BorderRadius.circular(smallCorner),
          border: edge == null ? null : Border.all(color: edge),
        ),
        child: child,
      ),
    );
  }
}

ThemeData graphiteTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Graphite.mint,
    onPrimary: Graphite.onMint,
    secondary: Graphite.muted,
    onSecondary: Graphite.canvas,
    secondaryContainer: Graphite.raised,
    onSecondaryContainer: Graphite.text,
    error: Graphite.coral,
    onError: Graphite.canvas,
    surface: Graphite.surface,
    onSurface: Graphite.text,
    onSurfaceVariant: Graphite.muted,
    surfaceContainerHighest: Graphite.raised,
    surfaceContainerHigh: Graphite.raised,
    surfaceContainer: Graphite.raised,
    outline: Graphite.lineStrong,
    outlineVariant: Graphite.line,
  );
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(smallCorner));
  OutlineInputBorder field(Color color, [double width = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(smallCorner), borderSide: BorderSide(color: color, width: width));
  const label = TextStyle(fontFamily: sans, fontSize: 13, fontWeight: FontWeight.w500);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: sans,
    scaffoldBackgroundColor: Graphite.canvas,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Graphite.hover,
    focusColor: Graphite.hover,
    dividerColor: Graphite.line,
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -.2, color: Graphite.text),
      titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Graphite.text),
      titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Graphite.text),
      bodyMedium: TextStyle(fontSize: 13, color: Graphite.text),
      bodySmall: TextStyle(fontSize: 12, color: Graphite.muted),
      labelLarge: label,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 14), shape: rounded, textStyle: label)
          .copyWith(
            backgroundColor: clear,
            overlayColor: clear,
            backgroundBuilder: pressable(fill: Graphite.mint, hover: Color.lerp(Graphite.mint, Colors.white, .1)!, disabled: Graphite.raised),
          ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Graphite.text,
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: rounded,
        side: BorderSide.none,
        textStyle: label,
      ).copyWith(
        backgroundColor: clear,
        overlayColor: clear,
        backgroundBuilder: pressable(hover: Graphite.hover, border: Graphite.lineStrong, disabledBorder: Graphite.line),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Graphite.text, minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 10), shape: rounded, textStyle: label)
          .copyWith(backgroundColor: clear, overlayColor: clear, backgroundBuilder: pressable(hover: Graphite.hover)),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: Graphite.muted, shape: rounded)),
    dialogTheme: DialogThemeData(
      backgroundColor: Graphite.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(corner + 2), side: const BorderSide(color: Graphite.lineStrong)),
      titleTextStyle: const TextStyle(fontFamily: sans, fontSize: 16, fontWeight: FontWeight.w600, color: Graphite.text),
    ),
    tooltipTheme: TooltipThemeData(
      textStyle: const TextStyle(fontFamily: sans, fontSize: 12, color: Graphite.text),
      decoration: BoxDecoration(color: Graphite.hover, borderRadius: BorderRadius.circular(smallCorner), border: Border.all(color: Graphite.lineStrong)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Graphite.canvas,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      hintStyle: const TextStyle(color: Graphite.faint, fontSize: 13),
      labelStyle: const TextStyle(color: Graphite.muted, fontSize: 13),
      border: field(Graphite.line),
      enabledBorder: field(Graphite.line),
      disabledBorder: field(Graphite.line),
      focusedBorder: field(Graphite.mint),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Graphite.text,
      unselectedLabelColor: Graphite.muted,
      indicatorColor: Graphite.mint,
      dividerColor: Colors.transparent,
      labelStyle: label,
      unselectedLabelStyle: label,
      overlayColor: WidgetStatePropertyAll(Colors.transparent),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Graphite.surface,
      selectedColor: Graphite.raised,
      disabledColor: Graphite.surface,
      side: const BorderSide(color: Graphite.line),
      shape: rounded,
      showCheckmark: false,
      labelStyle: label,
    ),
    sliderTheme: const SliderThemeData(trackHeight: 2, activeTrackColor: Graphite.mint, inactiveTrackColor: Graphite.lineStrong, thumbColor: Graphite.mint),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Graphite.mint),
    textSelectionTheme: TextSelectionThemeData(cursorColor: Graphite.mint, selectionColor: Graphite.mint.withValues(alpha: .28)),
    popupMenuTheme: const PopupMenuThemeData(color: Graphite.raised, surfaceTintColor: Colors.transparent),
    expansionTileTheme: const ExpansionTileThemeData(iconColor: Graphite.muted, collapsedIconColor: Graphite.muted, shape: Border(), collapsedShape: Border()),
  );
}
