import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/app_state.dart';
import '../i18n/strings.dart';
import '../notifications/notifications.dart';
import '../prayer/city.dart';
import '../prayer/geo.dart';
import '../theme/tokens.dart';
import '../theme/system_bars.dart';
import 'home.dart';

/// Онбординг, 5 шагов (README §1): язык → город → уведомления → тема → постер.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int step = 0;

  void next() => setState(() => step++);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = S.of(app.lang);
    // Для онбординга используем светлую схему в цветах песка/крема из логотипа.
    final c = JColors.light;
    final body = switch (step) {
      0 => _LangStep(
        c: c,
        onPick: (lang) {
          app.lang = lang;
          next();
        },
      ),
      1 => _CityStep(
        s: s,
        c: c,
        onPick: (city) {
          app.setCity(city);
          Future.delayed(const Duration(milliseconds: 250), next);
        },
      ),
      2 => _NotifStep(
        s: s,
        c: c,
        onAllow: () async {
          await gNotifier?.requestPermission();
          next();
        },
        onNext: next,
      ),
      _ => _PosterStep(
        s: s,
        c: c,
        onStart: () {
          app.onboardingDone = true;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        },
      ),
    };
    return JSystemBars(
      darkIcons: true,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFFFFDF9), // Теплый молочный/белый цвет
                Color(0xFFFBEFDD), // Светлый крем из логотипа
              ],
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, .02),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: KeyedSubtree(
              key: ValueKey(step),
              child: SafeArea(child: body),
            ),
          ),
        ),
      ),
    );
  }
}

class _LangStep extends StatelessWidget {
  const _LangStep({required this.c, required this.onPick});
  final JColors c;
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Spacer(flex: 2),
          Text('دوام', style: JType.arabic(56, color: c.gold)),
          const SizedBox(height: 8),
          Text(
            'Дауам',
            style: JType.ui(30, w: FontWeight.w800, color: c.ink),
          ),
          const SizedBox(height: 10),
          Text(
            'ғибадат серігі · ассистент поклонения',
            textAlign: TextAlign.center,
            style: JType.ui(14, color: c.sub),
          ),
          const Spacer(flex: 3),
          _PillButton(label: 'Қазақша', onTap: () => onPick('kz'), colors: c),
          const SizedBox(height: 12),
          _PillButton(label: 'Русский', onTap: () => onPick('ru'), colors: c),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _CityStep extends StatefulWidget {
  const _CityStep({required this.s, required this.c, required this.onPick});
  final S s;
  final JColors c;
  final void Function(City) onPick;

  @override
  State<_CityStep> createState() => _CityStepState();
}

class _CityStepState extends State<_CityStep> {
  final _ctrl = TextEditingController();
  List<City> _results = const [];
  bool _detecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _detect();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final r = await CityRepository.search(
      q,
      lang: widget.s == S.kz ? 'kz' : 'ru',
    );
    if (mounted) setState(() => _results = r);
  }

  Future<void> _detect() async {
    setState(() {
      _detecting = true;
      _error = null;
    });
    final kz = widget.s == S.kz;
    try {
      final city = await Geo.detectCity();
      if (!mounted) return;
      if (city == null) {
        setState(() {
          _detecting = false;
          _error = kz
              ? 'Анықтау мүмкін болмады. Тізімнен таңдаңыз.'
              : 'Не удалось определить. Выберите из списка.';
        });
        return;
      }
      HapticFeedback.mediumImpact();
      widget.onPick(city);
    } catch (_) {
      if (mounted) setState(() => _detecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final c = widget.c;
    final list = _ctrl.text.isEmpty ? kMajorCities : _results;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${s.step} 1/2', style: JType.caption(c.gold)),
          const SizedBox(height: 12),
          Text(
            s.cityTitle,
            style: JType.ui(30, w: FontWeight.w800, color: c.ink),
          ),
          const SizedBox(height: 8),
          Text(s.citySub, style: JType.ui(14, color: c.sub, h: 1.5)),
          const SizedBox(height: 20),
          _OutlineButton(
            label: _detecting ? '…' : s.geo,
            color: c.gold,
            onTap: _detect,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: JType.ui(12, color: c.red)),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            onChanged: _search,
            style: JType.ui(16, color: c.ink),
            cursorColor: c.gold,
            decoration: InputDecoration(
              hintText: s == S.kz ? 'Қала іздеу…' : 'Поиск города…',
              hintStyle: JType.ui(15, color: c.faint),
              prefixIcon: Icon(Icons.search, color: c.faint, size: 20),
              isDense: true,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: c.hair),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: c.gold),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, _) => Divider(color: c.hair, height: 1),
              itemBuilder: (_, i) => InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onPick(list[i]);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        list[i].displayName(s == S.kz ? 'kz' : 'ru'),
                        style: JType.ui(16, color: c.ink),
                      ),
                      if (list[i].region.isNotEmpty &&
                          list[i].region != list[i].name)
                        Text(
                          list[i].displayRegion(s == S.kz ? 'kz' : 'ru'),
                          style: JType.ui(12, color: c.faint),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotifStep extends StatelessWidget {
  const _NotifStep({
    required this.s,
    required this.c,
    required this.onAllow,
    required this.onNext,
  });
  final S s;
  final JColors c;
  final VoidCallback onAllow, onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${s.step} 2/2', style: JType.caption(c.gold)),
          const SizedBox(height: 12),
          Text(
            s.notifTitle,
            style: JType.ui(30, w: FontWeight.w800, color: c.ink),
          ),
          const SizedBox(height: 8),
          Text(s.notifSub, style: JType.ui(14, color: c.sub, h: 1.5)),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.hair),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('دوام', style: JType.arabic(20, color: c.gold)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.notifDemoTitle,
                        style: JType.ui(14, w: FontWeight.w700, color: c.ink),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.notifDemoBody,
                        style: JType.ui(13, color: c.sub, h: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          _PillButton(label: s.allow, onTap: onAllow, colors: c),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                onNext();
              },
              child: Text(s.later, style: JType.ui(14, color: c.faint)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PosterStep extends StatelessWidget {
  const _PosterStep({required this.s, required this.c, required this.onStart});
  final S s;
  final JColors c;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Spacer(flex: 2),
          Text(
            'فَاذْكُرُونِي أَذْكُرْكُمْ',
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: JType.arabic(34, color: c.gold),
          ),
          const SizedBox(height: 16),
          Text(
            s.posterAyat,
            textAlign: TextAlign.center,
            style: JType.reading(16, color: c.ink, style: FontStyle.italic),
          ),
          const SizedBox(height: 6),
          Text(s.posterAyatSrc, style: JType.ui(12, color: c.faint)),
          const SizedBox(height: 32),
          Container(width: 40, height: 1, color: c.hair),
          const SizedBox(height: 32),
          Text(
            s.posterQuote,
            textAlign: TextAlign.center,
            style: JType.reading(
              23,
              color: c.ink,
              style: FontStyle.italic,
              h: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(s.posterSrc, style: JType.ui(12, color: c.faint)),
          const Spacer(flex: 3),
          _PillButton(label: s.start, onTap: onStart, colors: c),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap, this.colors});
  final String label;
  final VoidCallback onTap;
  final JColors? colors;

  @override
  Widget build(BuildContext context) {
    final c = colors ?? JColors.dark;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: c.btnbg,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Center(
          child: Text(
            label,
            style: JType.ui(15, w: FontWeight.w700, color: c.btnink),
          ),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.label,
    required this.color,
    required this.onTap,
  });
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Center(
          child: Text(
            label,
            style: JType.ui(15, w: FontWeight.w700, color: color),
          ),
        ),
      ),
    );
  }
}
