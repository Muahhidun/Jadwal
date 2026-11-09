import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/orientation_service.dart';
import 'reader_palette.dart';

/// Маленькая кнопка в углу читалки: перевернуть текст в горизонталь/вертикаль.
/// Нужна тем, у кого выключен автоповорот или телефон лежит.
class ReaderRotateButton extends StatelessWidget {
  const ReaderRotateButton({
    super.key,
    required this.palette,
    required this.kz,
    this.size = 36,
  });

  final ReaderPalette palette;
  final bool kz;
  final double size;

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final label = landscape
        ? (kz ? 'Тігінен оқу' : 'Читать вертикально')
        : (kz ? 'Көлденең оқу' : 'Читать горизонтально');
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          key: const ValueKey('reader-rotate-button'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            AppOrientation.force(landscape: !landscape);
          },
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: palette.divider),
              color: palette.fazPlate,
            ),
            child: Icon(
              Icons.screen_rotation_rounded,
              size: size * .5,
              color: palette.source,
            ),
          ),
        ),
      ),
    );
  }
}
