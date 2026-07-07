import 'dart:math';
import 'package:flutter/material.dart';
import '../prayer/schedule.dart';

/// Динамическое «живое небо», привязанное к реальному времени суток
/// (через времена молитв города): солнце/луна плавно идут по дуге, цвета неба
/// перетекают ночь→рассвет→день→закат→ночь, на горизонте силуэт города-мечети,
/// ниже — город, который ночью оживает (окна, фонари). Цвет текста на главном
/// экране подстраивается под яркость неба (см. [skyForeground]).
class SceneBackground extends StatelessWidget {
  const SceneBackground({
    super.key,
    required this.progress,
    required this.screenHeight,
    required this.times,
    required this.nowSec,
  });

  final double progress; // 0 — главный (небо), 1 — «день» (город внизу)
  final double screenHeight;
  final DayTimes times;
  final int nowSec;

  @override
  Widget build(BuildContext context) {
    // Сцена высотой на 2 экрана; едет 1:1 с прокруткой.
    final dy = -progress * screenHeight;
    return Positioned(
      left: 0,
      right: 0,
      top: dy,
      height: screenHeight * 2,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _ScenePainter(times: times, nowSec: nowSec),
          size: Size.infinite,
        ),
      ),
    );
  }
}

// ── Модель неба: цвета и «дневность» по времени ──────────────────────────────

class _SkyKey {
  final int min;
  final Color top, bottom;
  final double day; // 0 ночь … 1 полдень (для яркости/текста)
  const _SkyKey(this.min, this.top, this.bottom, this.day);
}

/// Ключевые кадры неба по времени дня, привязанные к молитвам города.
List<_SkyKey> _skyKeys(DayTimes t) {
  final fajr = t.times[Prayer.fajr]!;
  final sun = t.times[Prayer.sunrise]!;
  final dhuhr = t.times[Prayer.dhuhr]!;
  final asr = t.times[Prayer.asr]!;
  final magh = t.times[Prayer.maghrib]!;
  final isha = t.times[Prayer.isha]!;
  return [
    _SkyKey(0, const Color(0xFF090D1C), const Color(0xFF10182C), 0),
    _SkyKey(fajr, const Color(0xFF161A34), const Color(0xFF3A2E50), 0.06),
    _SkyKey((fajr + sun) ~/ 2, const Color(0xFF2A3560), const Color(0xFF9A6E7A), 0.18),
    _SkyKey(sun, const Color(0xFF4E74B4), const Color(0xFFE7B078), 0.4),
    _SkyKey(dhuhr, const Color(0xFF4F93D8), const Color(0xFFCFE3F2), 1.0),
    _SkyKey(asr, const Color(0xFF5A93CE), const Color(0xFFD8E0EA), 0.85),
    _SkyKey(magh - 30, const Color(0xFF3A5590), const Color(0xFFE8A768), 0.45),
    _SkyKey(magh, const Color(0xFF2A3568), const Color(0xFFDB7A50), 0.28),
    _SkyKey(isha, const Color(0xFF0E1428), const Color(0xFF1E2038), 0.05),
    _SkyKey(1440, const Color(0xFF090D1C), const Color(0xFF10182C), 0),
  ];
}

class _Sky {
  final Color top, bottom;
  final double day;
  const _Sky(this.top, this.bottom, this.day);
}

_Sky _skyAt(DayTimes t, int nowMin) {
  final keys = _skyKeys(t);
  _SkyKey a = keys.first, b = keys.last;
  for (var i = 0; i < keys.length - 1; i++) {
    if (nowMin >= keys[i].min && nowMin <= keys[i + 1].min) {
      a = keys[i];
      b = keys[i + 1];
      break;
    }
  }
  final span = (b.min - a.min);
  final x = span == 0 ? 0.0 : (nowMin - a.min) / span;
  return _Sky(
    Color.lerp(a.top, b.top, x)!,
    Color.lerp(a.bottom, b.bottom, x)!,
    a.day + (b.day - a.day) * x,
  );
}

/// Цвета текста/акцента для главного экрана — подстраиваются под яркость неба.
class SkyFg {
  final Color text, faint, accent;
  const SkyFg(this.text, this.faint, this.accent);
}

/// Днём — тёмный текст, ночью — светлый (фон и текст меняются вместе).
SkyFg skyForeground(DayTimes t, int nowSec) {
  final sky = _skyAt(t, nowSec ~/ 60);
  final k = ((sky.day - 0.35) / 0.35).clamp(0.0, 1.0); // доля «дневного» текста
  return SkyFg(
    Color.lerp(const Color(0xFFECE9DF), const Color(0xFF1B2230), k)!,
    Color.lerp(const Color(0xFF9AA49B), const Color(0xFF44556A), k)!,
    Color.lerp(const Color(0xFFD9AE52), const Color(0xFF9A6B14), k)!,
  );
}

// ── Художник сцены ───────────────────────────────────────────────────────────

class _ScenePainter extends CustomPainter {
  _ScenePainter({required this.times, required this.nowSec});
  final DayTimes times;
  final int nowSec;

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width, H = size.height;
    final horizon = H * 0.5; // низ главного экрана / линия горизонта
    final nowMin = nowSec ~/ 60;
    final sky = _skyAt(times, nowMin);
    final night = (1 - sky.day * 2).clamp(0.0, 1.0); // 1 глубокая ночь … 0 день

    // Небо
    final skyRect = Rect.fromLTRB(0, 0, W, horizon);
    canvas.drawRect(
        skyRect,
        Paint()
          ..shader = LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [sky.top, sky.bottom])
              .createShader(skyRect));

    // Звёзды и падающая звезда — ночью
    if (night > 0.15) _stars(canvas, W, horizon, night);

    // Солнце / луна по дуге
    _celestial(canvas, W, horizon, H);

    // Земля/город ниже горизонта
    final groundTop = Color.lerp(sky.bottom, const Color(0xFF0B0F1C), 0.55)!;
    final groundBot = Color.lerp(const Color(0xFF0B0F1C), const Color(0xFF05070E), 0.6)!;
    final groundRect = Rect.fromLTRB(0, horizon, W, H);
    canvas.drawRect(
        groundRect,
        Paint()
          ..shader = LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [groundTop, groundBot])
              .createShader(groundRect));

    // Силуэт города-мечети на горизонте + продолжение города вниз
    _city(canvas, W, horizon, H, sky, night);

    // Затемнение к низу — читаемость карточек «дня»
    final scrim = Rect.fromLTRB(0, horizon, W, H);
    canvas.drawRect(
        scrim,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF05070E).withValues(alpha: 0.0),
              const Color(0xFF05070E).withValues(alpha: 0.35),
            ],
          ).createShader(scrim));
  }

  void _stars(Canvas canvas, double W, double horizon, double night) {
    final rnd = Random(7);
    final p = Paint()..color = Colors.white;
    for (var i = 0; i < 90; i++) {
      final x = rnd.nextDouble() * W;
      final y = rnd.nextDouble() * horizon * 0.85;
      final tw = 0.4 + 0.6 * (0.5 + 0.5 * sin((nowSec / 3 + i) * 0.7));
      p.color = Colors.white.withValues(alpha: (0.15 + rnd.nextDouble() * 0.5) * night * tw);
      canvas.drawCircle(Offset(x, y), rnd.nextDouble() * 1.2 + 0.4, p);
    }
    // Падающая звезда: раз в ~24 c короткий след.
    final bucket = nowSec ~/ 24;
    final phase = (nowSec % 24) / 24.0;
    if (phase < 0.12) {
      final r = Random(bucket * 131 + 5);
      final sx = W * (0.2 + r.nextDouble() * 0.6);
      final sy = horizon * (0.1 + r.nextDouble() * 0.3);
      final prog = phase / 0.12;
      final len = 90.0;
      final a = (1 - prog) * night;
      final dx = sx + prog * 120, dy = sy + prog * 60;
      canvas.drawLine(
          Offset(dx, dy),
          Offset(dx - len * 0.7, dy - len * 0.35),
          Paint()
            ..strokeWidth = 2
            ..shader = LinearGradient(colors: [
              Colors.white.withValues(alpha: a),
              Colors.white.withValues(alpha: 0)
            ]).createShader(Rect.fromLTWH(dx - len, dy - len, len, len)));
    }
  }

  void _celestial(Canvas canvas, double W, double horizon, double H) {
    final nowMin = nowSec ~/ 60;
    final sun = times.times[Prayer.sunrise]!;
    final dhuhr = times.times[Prayer.dhuhr]!;
    final magh = times.times[Prayer.maghrib]!;
    final isDay = nowMin >= sun && nowMin <= magh;
    // фракция и высота: зенит приходится на Зухр
    double fracX, alt; // alt: 0 у горизонта … 1 зенит
    if (isDay) {
      if (nowMin <= dhuhr) {
        final f = (nowMin - sun) / max(1, dhuhr - sun);
        fracX = 0.12 + f * 0.38;
        alt = f;
      } else {
        final f = (nowMin - dhuhr) / max(1, magh - dhuhr);
        fracX = 0.5 + f * 0.38;
        alt = 1 - f;
      }
    } else {
      // ночь: луна восходит после Магриба, садится к Восходу
      final total = (1440 - magh) + sun;
      final nm = nowMin >= magh ? nowMin - magh : nowMin + (1440 - magh);
      final f = nm / max(1, total);
      fracX = 0.12 + f * 0.76;
      alt = sin(f * pi);
    }
    final cx = W * fracX;
    final cy = horizon * 0.92 - alt * horizon * 0.78;
    if (isDay) {
      // солнце с мягким свечением
      final glow = Paint()
        ..shader = RadialGradient(colors: [
          const Color(0xFFFFF3C8).withValues(alpha: 0.85),
          const Color(0xFFFFE29A).withValues(alpha: 0.0)
        ]).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: horizon * 0.22));
      canvas.drawCircle(Offset(cx, cy), horizon * 0.22, glow);
      canvas.drawCircle(Offset(cx, cy), horizon * 0.06, Paint()..color = const Color(0xFFFFF0C0));
    } else {
      final glow = Paint()
        ..shader = RadialGradient(colors: [
          const Color(0xFFE9E2C2).withValues(alpha: 0.35),
          const Color(0xFFE9E2C2).withValues(alpha: 0.0)
        ]).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: horizon * 0.16));
      canvas.drawCircle(Offset(cx, cy), horizon * 0.16, glow);
      final r = horizon * 0.052;
      canvas.drawCircle(Offset(cx, cy), r, Paint()..color = const Color(0xFFDCCB8E));
      // полумесяц: вырезаем тенью цвета неба
      canvas.drawCircle(Offset(cx + r * 0.55, cy - r * 0.25), r,
          Paint()..color = _skyAt(times, nowMin).top);
    }
  }

  void _city(Canvas canvas, double W, double horizon, double H, _Sky sky, double night) {
    // Цвет силуэта: темнее неба, с лёгким оттенком фазы.
    final sil = Color.lerp(sky.bottom, const Color(0xFF0A0E1A), 0.72)!;
    final silP = Paint()..color = sil;

    // Дальний силуэт-скайлайн на горизонте (мечеть по центру + дома + минареты).
    final base = horizon;
    Path skyline = Path()..moveTo(0, base);
    final rnd = Random(21);
    double x = 0;
    while (x < W) {
      final bw = 14 + rnd.nextDouble() * 26;
      final bh = 10 + rnd.nextDouble() * 34;
      skyline.lineTo(x, base - bh);
      skyline.lineTo(x + bw, base - bh);
      x += bw;
    }
    skyline.lineTo(W, base);
    skyline.close();
    canvas.drawPath(skyline, silP);
    // мечеть по центру
    _mosque(canvas, W * 0.5, base, W * 0.34, sil, night, main: true);
    // деревце слева
    _tree(canvas, W * 0.14, base, 26, sil);
    _tree(canvas, W * 0.86, base, 22, sil);

    // Ближний город ниже горизонта (экран «день»): ряды домов с окнами.
    final rows = [
      (y: horizon + (H - horizon) * 0.14, scale: 0.8, seed: 3),
      (y: horizon + (H - horizon) * 0.42, scale: 1.0, seed: 8),
      (y: horizon + (H - horizon) * 0.74, scale: 1.25, seed: 15),
    ];
    for (final row in rows) {
      _buildingRow(canvas, W, row.y, row.scale, row.seed, sil, night);
    }
  }

  void _mosque(Canvas canvas, double cx, double base, double w, Color sil,
      double night, {bool main = false}) {
    final p = Paint()..color = sil;
    final domeR = w * 0.16;
    final domeC = Offset(cx, base - w * 0.16);
    // корпус
    canvas.drawRect(Rect.fromLTRB(cx - w * 0.3, base - w * 0.14, cx + w * 0.3, base), p);
    // купол (с намёком на зелёный у главного)
    final domePaint = Paint()
      ..color = main ? Color.lerp(sil, const Color(0xFF1E4D3A), 0.5)! : sil;
    canvas.drawCircle(domeC, domeR, domePaint);
    canvas.drawRect(
        Rect.fromLTRB(cx - domeR, base - w * 0.14, cx + domeR, domeC.dy), domePaint);
    // шпиль
    final sp = Path()
      ..moveTo(cx, domeC.dy - domeR - w * 0.06)
      ..lineTo(cx - 3, domeC.dy - domeR)
      ..lineTo(cx + 3, domeC.dy - domeR)
      ..close();
    canvas.drawPath(sp, domePaint);
    // минареты по бокам
    for (final s in [-1.0, 1.0]) {
      final mx = cx + s * w * 0.34;
      canvas.drawRect(Rect.fromLTWH(mx - 3, base - w * 0.5, 6, w * 0.5), p);
      canvas.drawCircle(Offset(mx, base - w * 0.5), 5, p);
      final tip = Path()
        ..moveTo(mx, base - w * 0.5 - 12)
        ..lineTo(mx - 4, base - w * 0.5 - 3)
        ..lineTo(mx + 4, base - w * 0.5 - 3)
        ..close();
      canvas.drawPath(tip, p);
    }
  }

  void _tree(Canvas canvas, double x, double base, double h, Color sil) {
    final p = Paint()..color = sil;
    canvas.drawRect(Rect.fromLTWH(x - 2, base - h, 4, h), p);
    canvas.drawCircle(Offset(x, base - h), h * 0.5, p);
    canvas.drawCircle(Offset(x - h * 0.32, base - h * 0.8), h * 0.36, p);
    canvas.drawCircle(Offset(x + h * 0.32, base - h * 0.8), h * 0.36, p);
  }

  void _buildingRow(Canvas canvas, double W, double baseY, double scale, int seed,
      Color sil, double night) {
    final rnd = Random(seed);
    final p = Paint()..color = Color.lerp(sil, const Color(0xFF05070E), 0.35)!;
    double x = -10;
    while (x < W + 10) {
      final bw = (30 + rnd.nextDouble() * 34) * scale;
      final bh = (36 + rnd.nextDouble() * 52) * scale;
      final rect = Rect.fromLTWH(x, baseY - bh, bw, bh);
      canvas.drawRect(rect, p);
      // окна
      final cols = max(2, (bw / (10 * scale)).floor());
      final rowsN = max(2, (bh / (14 * scale)).floor());
      for (var r = 0; r < rowsN; r++) {
        for (var col = 0; col < cols; col++) {
          final wx = x + 6 * scale + col * (bw - 12 * scale) / max(1, cols - 1);
          final wy = baseY - bh + 8 * scale + r * (bh - 14 * scale) / max(1, rowsN - 1);
          final lit = rnd.nextDouble() < 0.5 * night; // ночью часть окон горит
          final wp = Paint()
            ..color = lit
                ? const Color(0xFFFFD68A).withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.05);
          canvas.drawRect(Rect.fromLTWH(wx, wy, 3.2 * scale, 4.2 * scale), wp);
        }
      }
      // уличный фонарь у основания — ночью светится
      if (night > 0.2 && rnd.nextDouble() < 0.4) {
        final lx = x + bw + 4;
        final gl = Paint()
          ..shader = RadialGradient(colors: [
            const Color(0xFFFFCC77).withValues(alpha: 0.5 * night),
            const Color(0xFFFFCC77).withValues(alpha: 0.0)
          ]).createShader(Rect.fromCircle(center: Offset(lx, baseY - 6), radius: 16));
        canvas.drawCircle(Offset(lx, baseY - 6), 16, gl);
        canvas.drawCircle(Offset(lx, baseY - 6), 2, Paint()..color = const Color(0xFFFFE0A0));
      }
      x += bw + 2;
    }
  }

  @override
  bool shouldRepaint(_ScenePainter old) => old.nowSec != nowSec || old.times != times;
}
