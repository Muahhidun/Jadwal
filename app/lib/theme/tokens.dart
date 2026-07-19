import 'package:flutter/material.dart';

/// Дизайн-токены из design_handoff_jadwal/README.md — источник правды по UI.
class JColors {
  final Color bg, ink, sub, faint, hair, gold, green, gdim, red, card, btnbg, btnink;

  const JColors({
    required this.bg,
    required this.ink,
    required this.sub,
    required this.faint,
    required this.hair,
    required this.gold,
    required this.green,
    required this.gdim,
    required this.red,
    required this.card,
    required this.btnbg,
    required this.btnink,
  });

  static const dark = JColors(
    bg: Color(0xFF0C0C0E),
    ink: Color(0xFFECE9DF),
    sub: Color(0xFF9AA49B),
    faint: Color(0xFF6F7A72),
    hair: Color(0xFF222224),
    gold: Color(0xFFC99A3F), // Премиальное золото вместо оранжевого акцента
    green: Color(0xFF5D7A66),
    gdim: Color(0xFF222B25),
    red: Color(0xFFB4544A),
    card: Color(0xFF16161A),
    btnbg: Color(0xFFECE9DF),
    btnink: Color(0xFF0C0C0E),
  );

  /// Экраны настроек: тёплый тёмно-синий (не чисто чёрный) + кремовый текст
  /// с пониженным контрастом — не «прошивает» глаза, не зависит от времени.
  static const night = JColors(
    bg: Color(0xFF10151F),
    ink: Color(0xFFE8E5DA),
    sub: Color(0xFFB0B4BE),
    faint: Color(0xFF7E8595),
    hair: Color(0xFF2A3140),
    gold: Color(0xFFC99A3F),
    green: Color(0xFF5D7A66),
    gdim: Color(0xFF222B31),
    red: Color(0xFFB4544A),
    card: Color(0xFF1A2029),
    btnbg: Color(0xFFE8E5DA),
    btnink: Color(0xFF10151F),
  );

  static const light = JColors(
    bg: Color(0xFFF7F2E7),
    ink: Color(0xFF2C2A24),
    sub: Color(0xFF7B7461),
    faint: Color(0xFF9A927E),
    hair: Color(0xFFE3DCC9),
    gold: Color(0xFF8C7A4E),
    green: Color(0xFF8C7A4E),
    gdim: Color(0xFFEFE8D6),
    red: Color(0xFFB4544A),
    card: Color(0xFFFFFFFF),
    btnbg: Color(0xFF2C2A24),
    btnink: Color(0xFFF7F2E7),
  );
}

/// Экран чтения и празднования — фиксированная «бумага», одинакова в обеих темах.
class JPaper {
  static const bg = Color(0xFFF7F2E7);
  static const ink = Color(0xFF2C2A24);
  static const arabic = Color(0xFF23211B);
  static const translit = Color(0xFF7B7461);
  static const accent = Color(0xFF8C7A4E);
  static const fazPlate = Color(0xFFEFE8D6);
  static const source = Color(0xFF9A927E);
  static const divider = Color(0xFFE3DCC9);
  static const button = Color(0xFF2C2A24);
  static const disabled = Color(0xFFD9D1BC);
}

/// Фирменный терракотовый цвет из логотипа.
const jSplash = Color(0xFFC4552D);

class JType {
  // Вариативный Manrope: вес задаём и через fontWeight, и через ось wght
  // (иначе вариативный шрифт рендерится дефолтным весом и выглядит иначе).
  static List<FontVariation> _wght(FontWeight w) =>
      [FontVariation('wght', w.value.toDouble())];

  static TextStyle ui(double size,
          {FontWeight w = FontWeight.w400, Color? color, double? ls, double? h}) =>
      TextStyle(
          fontFamily: 'Manrope',
          fontSize: size,
          fontWeight: w,
          fontVariations: _wght(w),
          color: color,
          letterSpacing: ls,
          height: h);

  /// Каптион-«шапка»: 11px/700, letter-spacing, UPPERCASE (текст подаёт вызывающий).
  static TextStyle caption(Color color, {double size = 11}) => TextStyle(
      fontFamily: 'Manrope',
      fontSize: size,
      fontWeight: FontWeight.w700,
      fontVariations: _wght(FontWeight.w700),
      color: color,
      letterSpacing: size * .15);

  /// Таймер 52–72px/300 tabular-nums.
  static TextStyle timer(double size, Color color) => TextStyle(
      fontFamily: 'Manrope',
      fontSize: size,
      fontWeight: FontWeight.w300,
      fontVariations: _wght(FontWeight.w300),
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()]);

  static TextStyle reading(double size,
          {Color? color, FontStyle? style, double h = 1.75}) =>
      TextStyle(
          fontFamily: 'Literata',
          fontSize: size,
          color: color,
          fontStyle: style,
          height: h);

  static TextStyle arabic(double size, {Color color = JPaper.arabic}) =>
      TextStyle(fontFamily: 'Amiri', fontSize: size, color: color, height: 1.95);
}
