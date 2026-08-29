import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_state.dart';
import '../prayer/city.dart';
import '../prayer/geo.dart';
import '../theme/tokens.dart';
import 'settings_shell.dart';

/// Поиск города в той же навигационной системе, что и остальные настройки.
/// На первом экране видны текущее место, автоопределение и быстрые города;
/// результаты поиска заменяют быстрый список без дополнительных окон.
class CityPicker extends StatefulWidget {
  const CityPicker({super.key});

  static Future<void> open(BuildContext context) =>
      DauamSettingsSheet.open<void>(
        context,
        builder: (_) => const CityPicker(),
      );

  @override
  State<CityPicker> createState() => _CityPickerState();
}

class _CityPickerState extends State<CityPicker> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  List<City> _results = const [];
  bool _searching = false;
  bool _detecting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final generation = query;
    if (query.trim().isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final results = await CityRepository.search(
      query,
      lang: AppScope.of(context).lang,
    );
    if (!mounted || _controller.text != generation) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  Future<void> _detect() async {
    final app = AppScope.of(context);
    final kz = app.lang == 'kz';
    setState(() {
      _detecting = true;
      _error = null;
    });
    try {
      final city = await Geo.detectCity();
      if (!mounted) return;
      if (city == null) {
        setState(() {
          _detecting = false;
          _error = kz
              ? 'Орналасқан жер анықталмады. Геолокация рұқсатын тексеріңіз.'
              : 'Не удалось определить местоположение. Проверьте доступ к геолокации.';
        });
        return;
      }
      app.setCity(city);
      HapticFeedback.mediumImpact();
      Navigator.of(context, rootNavigator: true).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _detecting = false;
        _error = kz
            ? 'Қате шықты. Қайта көріңіз.'
            : 'Не получилось. Попробуйте ещё раз.';
      });
    }
  }

  void _pick(City city) {
    AppScope.of(context).setCity(city);
    HapticFeedback.mediumImpact();
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final kz = app.lang == 'kz';
    final p = dauamSettingsPalette(context);
    final c = p.colors;
    final hasQuery = _controller.text.trim().isNotEmpty;
    final cities = hasQuery ? _results : kMajorCities;

    return DauamSettingsPage(
      root: true,
      title: kz ? 'Қала' : 'Город',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              onChanged: _search,
              cursorColor: c.gold,
              style: JType.ui(16, color: c.ink),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: kz ? 'Қаланы іздеу' : 'Найти город',
                hintStyle: JType.ui(15, color: c.faint),
                prefixIcon: Icon(
                  CupertinoIcons.search,
                  size: 19,
                  color: c.faint,
                ),
                suffixIcon: hasQuery
                    ? IconButton(
                        icon: Icon(
                          CupertinoIcons.xmark_circle_fill,
                          size: 18,
                          color: c.faint,
                        ),
                        onPressed: () {
                          _controller.clear();
                          _search('');
                          _focus.requestFocus();
                        },
                      )
                    : null,
                filled: true,
                fillColor: p.surface.withValues(alpha: p.isLight ? .75 : .62),
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(
                    color: p.border.withValues(alpha: .42),
                    width: .7,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(
                    color: c.gold.withValues(alpha: .8),
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (!hasQuery) ...[
                  DauamSection(
                    label: kz ? 'ҚАЗІРГІ ҚАЛА' : 'ТЕКУЩИЙ ГОРОД',
                    children: [
                      DauamSettingsRow(
                        icon: CupertinoIcons.location_fill,
                        title: app.city.displayName(app.lang),
                        subtitle: app.city.region.isEmpty
                            ? null
                            : app.city.displayRegion(app.lang),
                      ),
                      DauamSettingsRow(
                        icon: CupertinoIcons.location,
                        title: kz
                            ? 'Автоматты анықтау'
                            : 'Определить автоматически',
                        subtitle: kz
                            ? 'Құрылғының геолокациясын пайдалану'
                            : 'Использовать геолокацию устройства',
                        trailing: _detecting
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: c.gold,
                                ),
                              )
                            : null,
                        onTap: _detecting ? null : _detect,
                      ),
                    ],
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(26, 0, 26, 10),
                      child: Text(
                        _error!,
                        style: JType.ui(12.5, color: c.red, h: 1.35),
                      ),
                    ),
                ],
                if (_searching)
                  Padding(
                    padding: const EdgeInsets.all(28),
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.gold,
                      ),
                    ),
                  )
                else if (hasQuery && cities.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(34),
                    child: Column(
                      children: [
                        Icon(CupertinoIcons.search, size: 28, color: c.faint),
                        const SizedBox(height: 12),
                        Text(
                          kz ? 'Ештеңе табылмады' : 'Ничего не найдено',
                          style: JType.ui(15, w: FontWeight.w600, color: c.sub),
                        ),
                      ],
                    ),
                  )
                else
                  DauamSection(
                    label: hasQuery
                        ? (kz ? 'НӘТИЖЕЛЕР' : 'РЕЗУЛЬТАТЫ')
                        : (kz ? 'ЖИІ ТАҢДАЛАТЫН' : 'ПОПУЛЯРНЫЕ ГОРОДА'),
                    children: [
                      for (final city in cities)
                        DauamChoiceRow(
                          title: city.displayName(app.lang),
                          subtitle: city.region.isEmpty
                              ? null
                              : city.displayRegion(app.lang),
                          selected:
                              city.latStr == app.city.latStr &&
                              city.lngStr == app.city.lngStr,
                          onTap: () => _pick(city),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
