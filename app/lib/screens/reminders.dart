import 'package:flutter/material.dart';
import '../data/app_state.dart';
import '../notifications/notifications.dart';
import '../theme/tokens.dart';

/// Экран «Напоминания»: вкл/выкл окон поклонения, оповещений по каждому
/// намазу и конструктор своих напоминаний (смещение от намаза).
class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  static const _prayersRu = ['Фаджр', 'Восход', 'Зухр', 'Аср', 'Магриб', 'Иша'];
  static const _prayersKz = ['Таң', 'Күн шығуы', 'Бесін', 'Екінті', 'Ақшам', 'Құптан'];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final kz = app.lang == 'kz';
    const c = JColors.dark;
    final prayers = kz ? _prayersKz : _prayersRu;

    void sync() => syncNotifications(app);

    Widget header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 6),
        child: Text(t, style: JType.caption(c.faint)));

    Widget row(String title, bool value, void Function(bool) onChanged,
        {String? sub, Widget? trailing}) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: JType.ui(15, color: c.ink)),
                if (sub != null) Text(sub, style: JType.ui(12, color: c.faint)),
              ]),
            ),
            trailing ?? const SizedBox.shrink(),
            Switch(
                value: value,
                activeTrackColor: c.gold.withValues(alpha: .5),
                thumbColor: WidgetStatePropertyAll(value ? c.gold : c.faint),
                onChanged: (v) {
                  onChanged(v);
                  sync();
                }),
          ]),
        );

    final windows = [
      ('morning', kz ? 'Таңғы зікірлер' : 'Утренние зикры'),
      ('evening', kz ? 'Кешкі зікірлер' : 'Вечерние зикры'),
      ('kahf', kz ? '«әл-Кәһф» сүресі (жұма)' : 'Сура аль-Кахф (пятница)'),
      ('dua', kz ? 'Дұға сағаты (жұма)' : 'Час дуа (пятница)'),
    ];
    const fivePrayers = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];
    const fiveIdx = [0, 2, 3, 4, 5];

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        foregroundColor: c.ink,
        title: Text(kz ? 'Еске салулар' : 'Напоминания',
            style: JType.ui(17, w: FontWeight.w700, color: c.ink)),
      ),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: 90),
          children: [
            header(kz ? 'ҒИБАДАТ УАҚЫТТАРЫ' : 'ОКНА ПОКЛОНЕНИЯ'),
            for (final (id, title) in windows)
              row(title, app.notifWindow(id), (v) => app.setNotifWindow(id, v)),
            header(kz ? 'НАМАЗ УАҚЫТЫ КІРГЕНДЕ' : 'НАСТУПЛЕНИЕ ВРЕМЕНИ НАМАЗА'),
            for (var i = 0; i < 5; i++)
              row(prayers[fiveIdx[i]], app.notifPrayer(fivePrayers[i]),
                  (v) => app.setNotifPrayer(fivePrayers[i], v)),
            header(kz ? 'МЕНІҢ ЕСКЕ САЛУЛАРЫМ' : 'МОИ НАПОМИНАНИЯ'),
            if (app.customReminders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                child: Text(
                    kz
                        ? 'Өз еске салуыңызды қосыңыз: намазға дейін/кейін N минут.'
                        : 'Добавьте своё: за N минут до намаза или после него.',
                    style: JType.ui(13, color: c.faint, h: 1.4)),
              ),
            for (final r in app.customReminders)
              Dismissible(
                key: ValueKey(r.id),
                direction: DismissDirection.endToStart,
                background: Container(
                    color: c.red.withValues(alpha: .25),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: Icon(Icons.delete_outline, color: c.red)),
                onDismissed: (_) {
                  app.removeReminder(r.id);
                  sync();
                },
                child: row(
                  r.title,
                  r.enabled,
                  (v) => app.toggleReminder(r.id, v),
                  sub: _offsetLabel(kz, prayers[r.prayer], r.offsetMin),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: c.gold,
        foregroundColor: c.bg,
        onPressed: () => _addDialog(context, app, kz, prayers),
        icon: const Icon(Icons.add),
        label: Text(kz ? 'Қосу' : 'Добавить',
            style: JType.ui(14, w: FontWeight.w700, color: c.bg)),
      ),
    );
  }

  static String _offsetLabel(bool kz, String prayer, int off) {
    final m = off.abs();
    if (off == 0) return kz ? '$prayer уақытында' : 'в момент: $prayer';
    if (off < 0) return kz ? '$prayer — $m мин бұрын' : 'за $m мин до: $prayer';
    return kz ? '$prayer — $m мин кейін' : 'через $m мин после: $prayer';
  }

  Future<void> _addDialog(
      BuildContext context, AppState app, bool kz, List<String> prayers) async {
    const c = JColors.dark;
    final titleCtrl = TextEditingController();
    final minCtrl = TextEditingController(text: '15');
    var prayer = 0;
    var before = true;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: c.card,
          title: Text(kz ? 'Жаңа еске салу' : 'Новое напоминание',
              style: JType.ui(17, w: FontWeight.w700, color: c.ink)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                style: JType.ui(15, color: c.ink),
                cursorColor: c.gold,
                decoration: InputDecoration(
                  hintText: kz ? 'Атауы (мыс.: Дұға)' : 'Название (напр.: Дуа)',
                  hintStyle: JType.ui(14, color: c.faint),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButton<int>(
                value: prayer,
                isExpanded: true,
                dropdownColor: c.card,
                style: JType.ui(15, color: c.ink),
                items: [
                  for (var i = 0; i < prayers.length; i++)
                    DropdownMenuItem(value: i, child: Text(prayers[i])),
                ],
                onChanged: (v) => setSt(() => prayer = v ?? 0),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: true, label: Text(kz ? 'дейін' : 'до')),
                      ButtonSegment(value: false, label: Text(kz ? 'кейін' : 'после')),
                    ],
                    selected: {before},
                    onSelectionChanged: (s) => setSt(() => before = s.first),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 56,
                  child: TextField(
                    controller: minCtrl,
                    keyboardType: TextInputType.number,
                    style: JType.ui(15, color: c.ink),
                    cursorColor: c.gold,
                    decoration:
                        InputDecoration(suffixText: kz ? 'мин' : 'мин'),
                  ),
                ),
              ]),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(kz ? 'Болдырмау' : 'Отмена',
                    style: JType.ui(14, color: c.faint))),
            TextButton(
              onPressed: () {
                final m = int.tryParse(minCtrl.text) ?? 0;
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                app.addReminder(CustomReminder(
                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                  title: title,
                  prayer: prayer,
                  offsetMin: before ? -m : m,
                ));
                syncNotifications(app);
                Navigator.pop(ctx);
              },
              child: Text(kz ? 'Қосу' : 'Добавить',
                  style: JType.ui(14, w: FontWeight.w700, color: c.gold)),
            ),
          ],
        ),
      ),
    );
  }
}