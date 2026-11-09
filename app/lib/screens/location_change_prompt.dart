import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../prayer/city.dart';
import '../theme/tokens.dart';
import 'scene_background.dart';

/// Подсказка о смене города в визуальной системе настроек Dauam.
///
/// Названия вынесены из кнопок намеренно: так действия остаются короткими,
/// одинаковыми по размеру и не требуют склонять каждое название города.
class LocationChangePrompt extends StatelessWidget {
  const LocationChangePrompt({
    super.key,
    required this.currentCity,
    required this.detectedCity,
    this.abroad = false,
    required this.lang,
    required this.palette,
    required this.accent,
    required this.onKeepCurrent,
    required this.onUpdate,
  });

  final City currentCity;
  final City detectedCity;

  /// Новое место — за пределами Казахстана: времена будут местным расчётом.
  final bool abroad;
  final String lang;
  final DaySurfacePalette palette;
  final Color accent;
  final VoidCallback onKeepCurrent;
  final VoidCallback onUpdate;

  bool get _kz => lang == 'kz';

  @override
  Widget build(BuildContext context) {
    final c = palette.colors;
    final primaryInk = palette.isLight ? Colors.white : const Color(0xFF102028);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(palette.top, c.bg, .16)!.withValues(alpha: .995),
                Color.lerp(palette.middle, c.bg, .38)!.withValues(alpha: .998),
                Color.lerp(palette.bottom, c.bg, .54)!,
              ],
            ),
            border: Border(
              top: BorderSide(
                color: palette.border.withValues(alpha: .34),
                width: .7,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    child: Container(
                      width: 38,
                      height: 5,
                      decoration: BoxDecoration(
                        color: c.faint.withValues(alpha: .44),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(
                          CupertinoIcons.location_fill,
                          color: accent,
                          size: 21,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _kz
                                  ? (abroad
                                        ? 'Қазақстаннан тыссыз ба?'
                                        : 'Басқа қалаға келдіңіз бе?')
                                  : (abroad
                                        ? 'Похоже, вы за пределами Казахстана'
                                        : 'Похоже, вы сменили город'),
                              style: JType.ui(
                                21,
                                w: FontWeight.w700,
                                color: c.ink,
                                ls: -.3,
                                h: 1.15,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              _kz
                                  ? (abroad
                                        ? 'Бұл жерде ҚМДБ кестесі жоқ. Намаз уақыттарын жергілікті есеппен (Aladhan) көрсетейік пе?'
                                        : 'Намаз кестесі мен виджеттерді жаңа қалаға сай жаңартайық па?')
                                  : (abroad
                                        ? 'Здесь нет таблицы ДУМК. Показывать время намаза по местному расчёту (Aladhan)?'
                                        : 'Обновить расписание молитв и виджеты для нового места?'),
                              style: JType.ui(14, color: c.sub, h: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      color: palette.surface.withValues(
                        alpha: palette.isLight ? .75 : .62,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: palette.border.withValues(alpha: .28),
                        width: .7,
                      ),
                    ),
                    child: Column(
                      children: [
                        _CityRow(
                          label: _kz ? 'Қазіргі қала' : 'Сейчас',
                          city: currentCity.displayName(lang),
                          colors: c,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Divider(
                            height: 1,
                            thickness: .55,
                            color: c.hair.withValues(alpha: .7),
                          ),
                        ),
                        _CityRow(
                          label: _kz ? 'Геолокация бойынша' : 'По геолокации',
                          city: detectedCity.displayName(lang),
                          colors: c,
                          accent: accent,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      onPressed: onUpdate,
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: primaryInk,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Text(
                        _kz ? 'Қаланы жаңарту' : 'Обновить город',
                        textAlign: TextAlign.center,
                        style: JType.ui(
                          15.5,
                          w: FontWeight.w700,
                          color: primaryInk,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 54,
                    child: OutlinedButton(
                      onPressed: onKeepCurrent,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.ink,
                        side: BorderSide(
                          color: palette.border.withValues(alpha: .58),
                          width: .8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Text(
                        _kz ? 'Қазіргі қаланы сақтау' : 'Оставить текущий',
                        textAlign: TextAlign.center,
                        style: JType.ui(15.5, w: FontWeight.w600, color: c.ink),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CityRow extends StatelessWidget {
  const _CityRow({
    required this.label,
    required this.city,
    required this.colors,
    this.accent,
  });

  final String label;
  final String city;
  final JColors colors;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            if (accent != null) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 9),
            ],
            Expanded(
              child: Text(label, style: JType.ui(13.5, color: colors.sub)),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                city,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: JType.ui(14.5, w: FontWeight.w700, color: colors.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
