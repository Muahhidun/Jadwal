import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool confirmed = false;

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
                    onTap: idx > 0
                        ? () => setState(() {
                              confirmed = false;
                              idx--;
                            })
                        : null,
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
                    child: _ActionButton(
                      isConfirmed: confirmed,
                      topText: confirmed
                          ? s.repeatConfirmTitle.replaceAll('{n}', '${z.repeat}')
                          : countLabel(z.repeat, app.lang),
                      bottomText: confirmed
                          ? s.repeatConfirmBtn
                          : (last ? s.finishBtn : s.nextBtn),
                      onTap: () {
                        if (z.repeat > 1 && !confirmed) {
                          HapticFeedback.mediumImpact();
                          setState(() => confirmed = true);
                        } else {
                          if (last) {
                            _finish();
                          } else {
                            setState(() {
                              confirmed = false;
                              idx++;
                            });
                          }
                        }
                      },
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

/// Короткая метка повторов: ru «1 раз / 3 раза / 5 раз», kz «N рет».
String countLabel(int repeat, String lang) {
  if (lang == 'kz') return '$repeat рет';
  final mod100 = repeat % 100;
  final mod10 = repeat % 10;
  final String word;
  if (mod100 >= 11 && mod100 <= 14) {
    word = 'раз';
  } else if (mod10 == 1) {
    word = 'раз';
  } else if (mod10 >= 2 && mod10 <= 4) {
    word = 'раза';
  } else {
    word = 'раз';
  }
  return '$repeat $word';
}

class _ZikrBody extends StatelessWidget {
  const _ZikrBody({required this.z, required this.s, required this.lang});
  final Zikr z;
  final S s;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final translation = z.translation(lang);
    final faz = z.faz(lang);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(z.ar,
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: JType.arabic(26)),
        const SizedBox(height: 14),
        // Сворачиваемые блоки: транскрипция / перевод / достоинство.
        // Кому блок не нужен — сворачивает; выбор запоминается для всех зикров.
        if (z.translit != null)
          _Section(
            title: s.translitTitle,
            open: app.showTranslit,
            onToggle: () => app.showTranslit = !app.showTranslit,
            child: Text(z.translit!,
                textAlign: TextAlign.center,
                style: JType.reading(13.5,
                    color: JPaper.translit, style: FontStyle.italic, h: 1.6)),
          ),
        if (translation != null)
          _Section(
            title: s.translationTitle,
            open: app.showTranslation,
            onToggle: () => app.showTranslation = !app.showTranslation,
            child: Text(translation,
                textAlign: TextAlign.center,
                style: JType.reading(14.5, color: JPaper.ink)),
          ),
        if (faz != null)
          _Section(
            title: s.fazTitle,
            open: app.showFaz,
            onToggle: () => app.showFaz = !app.showFaz,
            plate: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(faz, style: JType.reading(13.5, color: JPaper.ink, h: 1.6)),
                const SizedBox(height: 8),
                Text(z.source, style: JType.ui(11.5, color: JPaper.source)),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(
                child: Text(z.source, style: JType.ui(11.5, color: JPaper.source))),
          ),
      ],
    );
  }
}

/// Сворачиваемый блок читалки: заголовок-капс + шеврон, тап по шапке
/// открывает/закрывает. [plate] — на подложке (для «Достоинства»).
class _Section extends StatelessWidget {
  const _Section(
      {required this.title,
      required this.open,
      required this.onToggle,
      required this.child,
      this.plate = false});
  final String title;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;
  final bool plate;

  @override
  Widget build(BuildContext context) {
    final header = GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: JType.caption(JPaper.accent, size: 10)),
            const SizedBox(width: 4),
            Icon(open ? Icons.expand_less : Icons.expand_more,
                size: 16, color: JPaper.accent),
          ],
        ),
      ),
    );
    final body = AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: open
          ? Padding(padding: const EdgeInsets.only(top: 2, bottom: 10), child: child)
          : const SizedBox(width: double.infinity),
    );
    if (!plate) return Column(children: [header, body]);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: JPaper.fazPlate,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [header, body]),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.topText,
    required this.bottomText,
    required this.isConfirmed,
    required this.onTap,
  });
  final String topText;
  final String bottomText;
  final bool isConfirmed;
  final VoidCallback onTap;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _offsetAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 6.0).chain(CurveTween(curve: Curves.easeOut)), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 6.0, end: -6.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 25),
      TweenSequenceItem(tween: Tween(begin: -6.0, end: 4.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 4.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 25),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(covariant _ActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isConfirmed && !oldWidget.isConfirmed) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _offsetAnimation,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(_offsetAnimation.value, 0),
            child: child,
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          height: 52,
          decoration: BoxDecoration(
            color: widget.isConfirmed ? JPaper.accent : JPaper.button,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: JType.ui(10.5,
                    w: FontWeight.w400,
                    color: JPaper.bg.withValues(alpha: .6)),
                child: Text(widget.topText),
              ),
              const SizedBox(height: 1),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: JType.ui(15, w: FontWeight.w700, color: JPaper.bg),
                child: Text(widget.bottomText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
