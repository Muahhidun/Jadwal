import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Единый стиль системных индикаторов.
///
/// На iOS [statusBarBrightness] описывает яркость фона статус-бара, поэтому
/// для тёмных значков ему нужна `Brightness.light`. На Android цвет самих
/// значков задаётся через [statusBarIconBrightness].
SystemUiOverlayStyle jSystemUiStyle({required bool darkIcons}) {
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: darkIcons ? Brightness.dark : Brightness.light,
    statusBarBrightness: darkIcons ? Brightness.light : Brightness.dark,
    systemNavigationBarIconBrightness: darkIcons
        ? Brightness.dark
        : Brightness.light,
  );
}

/// Применяет нужный цвет часов и системных индикаторов к конкретному экрану.
class JSystemBars extends StatelessWidget {
  const JSystemBars({super.key, required this.darkIcons, required this.child});

  final bool darkIcons;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: jSystemUiStyle(darkIcons: darkIcons),
      sized: true,
      child: child,
    );
  }
}
