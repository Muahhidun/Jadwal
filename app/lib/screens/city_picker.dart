import 'package:flutter/material.dart';
import '../data/app_state.dart';
import '../prayer/city.dart';
import '../prayer/geo.dart';
import '../theme/tokens.dart';
import 'home.dart';

/// Выбор города (тап по названию на главном): авто-определение по GPS,
/// поиск по названию, список. Любой из 5695 пунктов Казахстана.
class CityPicker extends StatefulWidget {
  const CityPicker({super.key});

  static Future<void> open(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const CityPicker(),
      );

  @override
  State<CityPicker> createState() => _CityPickerState();
}

class _CityPickerState extends State<CityPicker> {
  final _ctrl = TextEditingController();
  List<City> _results = const [];
  bool _detecting = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final r = await CityRepository.search(q);
    if (mounted) setState(() => _results = r);
  }

  Future<void> _detect() async {
    setState(() {
      _detecting = true;
      _error = null;
    });
    final app = AppScope.of(context);
    try {
      final city = await Geo.detectCity();
      if (!mounted) return;
      if (city == null) {
        setState(() {
          _detecting = false;
          _error = app.lang == 'kz'
              ? 'Орналасқан жерді анықтау мүмкін болмады. Рұқсатты тексеріңіз.'
              : 'Не удалось определить местоположение. Проверьте разрешение геолокации.';
        });
        return;
      }
      app.setCity(city);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _detecting = false;
          _error = app.lang == 'kz' ? 'Қате шықты.' : 'Произошла ошибка.';
        });
      }
    }
  }

  void _pick(City c) {
    AppScope.of(context).setCity(c);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = jColorsOf(context);
    final app = AppScope.of(context);
    final kz = app.lang == 'kz';
    final insets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.82,
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
                width: 36,
                height: 4,
                decoration:
                    BoxDecoration(color: c.hair, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: TextField(
                controller: _ctrl,
                autofocus: false,
                onChanged: _search,
                style: JType.ui(16, color: c.ink),
                cursorColor: c.gold,
                decoration: InputDecoration(
                  hintText: kz ? 'Қала іздеу…' : 'Поиск города…',
                  hintStyle: JType.ui(16, color: c.faint),
                  prefixIcon: Icon(Icons.search, color: c.faint, size: 20),
                  filled: true,
                  fillColor: c.card,
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: c.hair)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: c.hair)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: c.gold)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: GestureDetector(
                onTap: _detecting ? null : _detect,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: c.gold),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_detecting)
                        SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: c.gold))
                      else
                        Icon(Icons.my_location, size: 18, color: c.gold),
                      const SizedBox(width: 8),
                      Text(kz ? 'Автоматты түрде анықтау' : 'Определить автоматически',
                          style: JType.ui(15, w: FontWeight.w700, color: c.gold)),
                    ],
                  ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Text(_error!,
                    style: JType.ui(12, color: c.red), textAlign: TextAlign.center),
              ),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                          _ctrl.text.isEmpty
                              ? (kz ? 'Қаланы іздеңіз немесе анықтаңыз' : 'Найдите город или определите')
                              : (kz ? 'Ештеңе табылмады' : 'Ничего не найдено'),
                          style: JType.ui(14, color: c.faint)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _results.length,
                      separatorBuilder: (_, _) => Divider(color: c.hair, height: 1),
                      itemBuilder: (_, i) {
                        final city = _results[i];
                        return InkWell(
                          onTap: () => _pick(city),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(city.name, style: JType.ui(16, color: c.ink)),
                                      if (city.region.isNotEmpty)
                                        Text(city.region,
                                            style: JType.ui(12, color: c.faint)),
                                    ],
                                  ),
                                ),
                                if (city.name == app.city.name)
                                  Icon(Icons.check, size: 18, color: c.gold),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
