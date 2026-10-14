import 'package:flutter/material.dart';

const kFontUi = 'Inter';
const kFontNum = 'BarlowCondensed';

/// Couleurs de la marque Buteo. Le thème sombre est celui par défaut.
@immutable
class ButeoColors extends ThemeExtension<ButeoColors> {
  const ButeoColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.fg,
    required this.muted,
    required this.faint,
    required this.win,
    required this.winText,
    required this.winInk,
    required this.winSoft,
    required this.gold,
    required this.goldText,
    required this.goldInk,
    required this.goldSoft,
    required this.loss,
    required this.lossText,
    required this.lossSoft,
    required this.liveText,
    required this.liveSoft,
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color line;
  final Color fg;
  final Color muted;
  final Color faint;

  /// Vert « victoire » : fond des boutons et des cotes.
  final Color win;

  /// Vert lisible sur le fond du thème.
  final Color winText;

  /// Texte posé sur [win].
  final Color winInk;
  final Color winSoft;
  final Color gold;
  final Color goldText;
  final Color goldInk;
  final Color goldSoft;
  final Color loss;
  final Color lossText;
  final Color lossSoft;
  final Color liveText;
  final Color liveSoft;

  static const dark = ButeoColors(
    bg: Color(0xFF0A1230),
    surface: Color(0xFF111A3D),
    surface2: Color(0xFF18234F),
    line: Color(0xFF243163),
    fg: Color(0xFFEEF1FB),
    muted: Color(0xFF8F9AC4),
    faint: Color(0xFF5D6894),
    win: Color(0xFF2BF59A),
    winText: Color(0xFF2BF59A),
    winInk: Color(0xFF04261A),
    winSoft: Color(0x1F2BF59A),
    gold: Color(0xFFFFC53D),
    goldText: Color(0xFFFFC53D),
    goldInk: Color(0xFF2B1D00),
    goldSoft: Color(0x21FFC53D),
    loss: Color(0xFFFF4D6A),
    lossText: Color(0xFFFF7389),
    lossSoft: Color(0x24FF4D6A),
    liveText: Color(0xFFFFAE63),
    liveSoft: Color(0x26FF9F43),
  );

  static const light = ButeoColors(
    bg: Color(0xFFF2F4FA),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEDF0F8),
    line: Color(0xFFD9DFEE),
    fg: Color(0xFF0A1230),
    muted: Color(0xFF56628C),
    faint: Color(0xFF8A94B8),
    win: Color(0xFF2BF59A),
    winText: Color(0xFF05854F),
    winInk: Color(0xFF04261A),
    winSoft: Color(0x1A05854F),
    gold: Color(0xFFFFC53D),
    goldText: Color(0xFF8F5F00),
    goldInk: Color(0xFF2B1D00),
    goldSoft: Color(0x38FFC53D),
    loss: Color(0xFFFF4D6A),
    lossText: Color(0xFFC81E40),
    lossSoft: Color(0x1AD6264A),
    liveText: Color(0xFFB35400),
    liveSoft: Color(0x1FC9620A),
  );

  @override
  ButeoColors copyWith() => this;

  @override
  ButeoColors lerp(ButeoColors? other, double t) => t < .5 ? this : (other ?? this);
}

extension ButeoContext on BuildContext {
  ButeoColors get colors => Theme.of(this).extension<ButeoColors>()!;
}

/// Chiffres de tableau d'affichage (scores, cotes, pourcentages).
TextStyle numStyle(double size, {Color? color, FontWeight weight = FontWeight.w700}) => TextStyle(
  fontFamily: kFontNum,
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: 1.05,
  fontFeatures: const [FontFeature.tabularFigures()],
);

ThemeData buildTheme(ButeoColors c, Brightness brightness) {
  final base = ThemeData(useMaterial3: true, brightness: brightness, fontFamily: kFontUi);
  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    dividerColor: c.line,
    extensions: [c],
    colorScheme: ColorScheme.fromSeed(seedColor: c.win, brightness: brightness).copyWith(
      primary: c.win,
      onPrimary: c.winInk,
      secondary: c.gold,
      onSecondary: c.goldInk,
      surface: c.surface,
      onSurface: c.fg,
      error: c.loss,
    ),
    textTheme: base.textTheme.apply(bodyColor: c.fg, displayColor: c.fg, fontFamily: kFontUi),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.fg,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: Border(bottom: BorderSide(color: c.line)),
      titleTextStyle: TextStyle(fontFamily: kFontUi, fontSize: 18, fontWeight: FontWeight.w700, color: c.fg),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.winSoft,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: kFontUi,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: s.contains(WidgetState.selected) ? c.winText : c.faint,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? c.winText : c.faint),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: c.line,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.fg,
      contentTextStyle: TextStyle(fontFamily: kFontUi, color: c.bg, fontWeight: FontWeight.w600),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.winInk : c.fg),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.win : c.line),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
  );
}
