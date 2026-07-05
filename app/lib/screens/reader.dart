import 'package:flutter/material.dart';
import '../data/adhkar.dart';
import '../data/app_state.dart';
import '../i18n/strings.dart';
import '../prayer/schedule.dart';
import '../prayer/schedule_service.dart';
import '../theme/tokens.dart';
import 'celebration.dart';

/// Чтение зикров — «книга» (README §4). Фон-«бумага» в обеих темах,
/// один зикр на экран, сегментированный прогресс. Никаких счётчиков нажатий.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.collectionId});
  final String collectionId;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  ZikrCollection? collection;
  int idx = 0;

  @override
  void initState() {
    super.initState();
    AdhkarRepository.load().then((all) {
      if (mounted) setState(() => collection = all[widget.collectionId]);
    });
  }

  void _finish() {
    final app = AppScope.of(context);
    app.markDone(widget.collectionId);
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => CelebrationScreen(collectionId: widget.collectionId)));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = S.of(app.lang);
    final col = collection;
    if (col == null) {
      return const Scaffold(
        backgroundColor: JPaper.bg,
        body: Center(child: CircularProgressIndicator(color: JPaper.accent)),
      );
    }
    final z = col.items[idx];
    final last = idx == col.items.length - 1;
    final schedule = ScheduleScope.of(context);
    final now = schedule.now();
    final nowMin = now.hour * 60 + now.minute;
    final t = schedule.timesFor(app.city, now);
    final endPrayer =
        widget.collectionId == 'morning' ? Prayer.sunrise : Prayer.maghrib;
    final title = widget.collectionId == 'morning' ? s.readerMorning : s.readerEvening;
    final timerCaption = widget.collectionId == 'morning' ? s.toSunrise : s.toMaghrib;
    final remainingMin = t == null ? 0 : t.times[endPrayer]! - nowMin;
    final remaining = DayTimes.fmtDuration(remainingMin);

    return Scaffold(
      backgroundColor: JPaper.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.close, size: 22, color: JPaper.source),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(title, style: JType.caption(JPaper.accent)),
                        const SizedBox(height: 2),
                        if (remainingMin > 0)
                          Text('$timerCaption · $remaining',
                              style: JType.ui(11, color: JPaper.source)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 34),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  for (var i = 0; i < col.items.length; i++) ...[
                    Expanded(
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: i <= idx ? JPaper.accent : JPaper.divider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    if (i < col.items.length - 1) const SizedBox(width: 4),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text('${idx + 1} ${s.of_} ${col.items.length}',
                style: JType.ui(11, color: JPaper.source)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                child: _ZikrBody(z: z, s: s, lang: app.lang),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: idx > 0 ? () => setState(() => idx--) : null,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: idx > 0 ? JPaper.button : JPaper.disabled),
                      ),
                      child: Icon(Icons.arrow_back,
                          size: 20, color: idx > 0 ? JPaper.button : JPaper.disabled),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: last ? _finish : () => setState(() => idx++),
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: JPaper.button,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Center(
                          child: Text(last ? s.finishBtn : s.nextBtn,
                              style:
                                  JType.ui(15, w: FontWeight.w700, color: JPaper.bg)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZikrBody extends StatelessWidget {
  const _ZikrBody({required this.z, required this.s, required this.lang});
  final Zikr z;
  final S s;
  final String lang;

  String _repeatLabel() {
    if (lang == 'kz') return s.repeatTimes.replaceFirst('{n}', '${z.repeat}');
    final word = z.repeat >= 5 ? 'РАЗ' : 'РАЗА';
    return 'ПРОИЗНОСИТСЯ ${z.repeat} $word';
  }

  @override
  Widget build(BuildContext context) {
    final translation = z.translation(lang);
    final faz = z.faz(lang);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(z.ar,
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: JType.arabic(26)),
        const SizedBox(height: 18),
        if (z.repeat > 1) ...[
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: JPaper.accent),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(_repeatLabel(),
                  style: JType.caption(JPaper.accent, size: 10)),
            ),
          ),
          const SizedBox(height: 18),
        ],
        if (z.translit != null) ...[
          Text(z.translit!,
              textAlign: TextAlign.center,
              style: JType.reading(13.5,
                  color: JPaper.translit, style: FontStyle.italic, h: 1.6)),
          const SizedBox(height: 16),
        ],
        if (translation != null)
          Text(translation,
              textAlign: TextAlign.center,
              style: JType.reading(14.5, color: JPaper.ink)),
        const SizedBox(height: 22),
        if (faz != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: JPaper.fazPlate,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.fazTitle, style: JType.caption(JPaper.accent, size: 10)),
                const SizedBox(height: 8),
                Text(faz, style: JType.reading(13.5, color: JPaper.ink, h: 1.6)),
                const SizedBox(height: 8),
                Text(z.source, style: JType.ui(11.5, color: JPaper.source)),
              ],
            ),
          )
        else
          Center(child: Text(z.source, style: JType.ui(11.5, color: JPaper.source))),
      ],
    );
  }
}
