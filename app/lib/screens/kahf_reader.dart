import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../data/app_state.dart';
import '../theme/system_bars.dart';
import '../theme/tokens.dart';
import 'celebration.dart';
import 'reader_palette.dart';

PageRoute<void> kahfReaderRoute() => PageRouteBuilder<void>(
  settings: const RouteSettings(name: 'kahf-reader'),
  opaque: false,
  barrierColor: Colors.transparent,
  transitionDuration: const Duration(milliseconds: 260),
  reverseTransitionDuration: const Duration(milliseconds: 220),
  pageBuilder: (_, _, _) => const KahfReaderScreen(),
  transitionsBuilder: (_, animation, _, child) => FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
    child: child,
  ),
);

/// Постраничная читалка суры аль-Кахф в раскладке мединского мусхафа.
///
/// Коранический текст и построчная разметка загружаются напрямую с
/// Quran Foundation во время чтения. Мы намеренно не копируем и не правим
/// текст внутри приложения: локально хранятся только оболочка и настройки.
class KahfReaderScreen extends StatefulWidget {
  const KahfReaderScreen({super.key});

  @override
  State<KahfReaderScreen> createState() => _KahfReaderScreenState();
}

class _KahfReaderScreenState extends State<KahfReaderScreen>
    with TickerProviderStateMixin {
  late final WebViewController _controller;
  late final AnimationController _handleHintController;
  late final AnimationController _finalHintController;
  late final Animation<double> _handleHintOffset;
  late final Animation<double> _finalHintOffset;
  Timer? _chromeTimer;
  bool _pageReady = false;
  bool _chromeVisible = true;
  bool _dismissDragging = false;
  bool _finishing = false;
  double _dismissOffset = 0;
  int _pageIndex = 0;
  int _pageCount = 0;

  @override
  void initState() {
    super.initState();
    _handleHintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    );
    _handleHintOffset =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0, end: 8), weight: 22),
          TweenSequenceItem(tween: Tween(begin: 8, end: 0), weight: 28),
          TweenSequenceItem(tween: Tween(begin: 0, end: 5), weight: 18),
          TweenSequenceItem(tween: Tween(begin: 5, end: 0), weight: 32),
        ]).animate(
          CurvedAnimation(
            parent: _handleHintController,
            curve: Curves.easeInOut,
          ),
        );
    _finalHintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1650),
    );
    _finalHintOffset =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0, end: 10), weight: 22),
          TweenSequenceItem(tween: Tween(begin: 10, end: 0), weight: 28),
          TweenSequenceItem(tween: Tween(begin: 0, end: 7), weight: 18),
          TweenSequenceItem(tween: Tween(begin: 7, end: 0), weight: 32),
        ]).animate(
          CurvedAnimation(
            parent: _finalHintController,
            curve: Curves.easeInOut,
          ),
        );
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'DauamReader',
        onMessageReceived: _handleReaderMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _pageReady = true);
            _syncAppearance();
          },
        ),
      )
      ..loadFlutterAsset('assets/quran/kahf_reader.html');
  }

  @override
  void dispose() {
    _chromeTimer?.cancel();
    _handleHintController.dispose();
    _finalHintController.dispose();
    super.dispose();
  }

  void _handleReaderMessage(JavaScriptMessage message) {
    if (!mounted) return;
    if (message.message == 'toggleChrome') {
      _toggleChrome();
      return;
    }

    try {
      final payload = jsonDecode(message.message) as Map<String, dynamic>;
      switch (payload['type']) {
        case 'contentReady':
          _showChromeTemporarily();
          return;
        case 'page':
          final index = payload['index'] as int? ?? 0;
          final count = payload['count'] as int? ?? 0;
          if (index != _pageIndex || count != _pageCount) {
            final reachedLastPage = count > 0 && index == count - 1;
            setState(() {
              _pageIndex = index;
              _pageCount = count;
            });
            if (reachedLastPage) {
              _finalHintController.forward(from: 0);
            } else {
              _finalHintController.reset();
            }
          }
          return;
        case 'complete':
          _finishReading();
          return;
      }
    } catch (_) {
      // Игнорируем неизвестные сообщения из локальной оболочки WebView.
    }
  }

  void _toggleChrome() {
    _chromeTimer?.cancel();
    final show = !_chromeVisible;
    setState(() => _chromeVisible = show);
    if (show) {
      _scheduleChromeHide();
    } else {
      _runHandleHint();
    }
  }

  void _showChromeTemporarily() {
    _chromeTimer?.cancel();
    if (!_chromeVisible) setState(() => _chromeVisible = true);
    _scheduleChromeHide();
  }

  void _scheduleChromeHide() {
    _chromeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _chromeVisible && !_dismissDragging) {
        setState(() => _chromeVisible = false);
        _runHandleHint();
      }
    });
  }

  void _runHandleHint() {
    if (!mounted || _dismissDragging || _finishing) return;
    _handleHintController.forward(from: 0);
  }

  void _restoreAfterDismissGesture() {
    if (!_dismissDragging && _dismissOffset == 0) return;
    setState(() {
      _dismissDragging = false;
      _dismissOffset = 0;
    });
  }

  void _startDismissGesture(DragStartDetails details) {
    if (_finishing) return;
    _chromeTimer?.cancel();
    _handleHintController.stop();
    setState(() {
      _dismissDragging = true;
      _dismissOffset = 0;
    });
  }

  void _updateDismissGesture(DragUpdateDetails details) {
    if (!_dismissDragging || _finishing) return;
    final delta = details.primaryDelta ?? 0;
    final height = MediaQuery.sizeOf(context).height;
    final nextOffset = (_dismissOffset + delta).clamp(0.0, height);
    if ((nextOffset - _dismissOffset).abs() < .1) return;
    setState(() => _dismissOffset = nextOffset);
  }

  void _completeDismissGesture(DragEndDetails details) {
    if (!_dismissDragging || _finishing) return;
    _endDismissGesture(_dismissOffset, details.primaryVelocity ?? 0);
  }

  Future<void> _endDismissGesture(double offset, double velocity) async {
    if (_finishing) return;
    final height = MediaQuery.sizeOf(context).height;
    final shouldDismiss =
        offset >= height * .22 || (offset >= 48 && velocity >= 800);
    if (!shouldDismiss) {
      _restoreAfterDismissGesture();
      return;
    }

    _chromeTimer?.cancel();
    setState(() {
      _finishing = true;
      _dismissDragging = false;
      _dismissOffset = height;
    });
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (mounted) Navigator.of(context).pop();
  }

  void _finishReading() {
    if (_finishing || !mounted) return;
    _finishing = true;
    _chromeTimer?.cancel();
    final app = AppScope.of(context);
    app.markDone('kahf');
    HapticFeedback.mediumImpact();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        settings: const RouteSettings(name: 'kahf-complete'),
        transitionDuration: const Duration(milliseconds: 360),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, _, _) => const CelebrationScreen(collectionId: 'kahf'),
        transitionsBuilder: (_, animation, _, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: child,
        ),
      ),
    );
  }

  Future<void> _syncAppearance() async {
    if (!_pageReady || !mounted) return;
    final app = AppScope.of(context);
    await _controller.runJavaScript(
      'window.setReaderAppearance('
      '${jsonEncode(app.readerPalette)}, ${jsonEncode(app.lang)});',
    );
  }

  void _selectPalette(AppState app, ReaderPalette selected) {
    app.readerPalette = selected.id;
    _syncAppearance();
    _showChromeTemporarily();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final palette = ReaderPalette.fromId(app.readerPalette);
    final kz = app.lang == 'kz';
    final height = MediaQuery.sizeOf(context).height;
    final dismissProgress = height == 0
        ? 0.0
        : (_dismissOffset / height).clamp(0.0, 1.0);
    final backdropOpacity = (.18 * (1 - dismissProgress / .55)).clamp(0.0, .18);
    _syncAppearance();

    return JSystemBars(
      darkIcons: !_dismissDragging && !palette.isDark,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: backdropOpacity),
              ),
            ),
            AnimatedContainer(
              duration: _dismissDragging
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(0, _dismissOffset, 0),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: palette.bg,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(_dismissOffset > 0 ? 18 : 0),
                ),
                boxShadow: _dismissOffset > 0
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .22),
                          blurRadius: 20,
                          offset: const Offset(0, -5),
                        ),
                      ]
                    : const [],
              ),
              child: SafeArea(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    WebViewWidget(controller: _controller),
                    if (!_pageReady)
                      ColoredBox(
                        color: palette.bg,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: palette.accent,
                          ),
                        ),
                      ),
                    if (_pageCount > 0)
                      Positioned(
                        left: 18,
                        right: 18,
                        bottom: 5,
                        child: IgnorePointer(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              key: const ValueKey('kahf-page-progress'),
                              // Последний незаполненный шаг — осознанный
                              // финальный свайп вправо для завершения чтения.
                              value: (_pageIndex + 1) / (_pageCount + 1),
                              minHeight: 2.5,
                              color: palette.accent.withValues(alpha: .82),
                              backgroundColor: palette.divider.withValues(
                                alpha: .72,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_pageCount > 0 && _pageIndex == _pageCount - 1)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 13,
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _finalHintController,
                            builder: (context, child) => Transform.translate(
                              offset: Offset(_finalHintOffset.value, 0),
                              child: child,
                            ),
                            child: Center(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: palette.bg.withValues(alpha: .9),
                                  borderRadius: BorderRadius.circular(100),
                                  border: Border.all(
                                    color: palette.divider.withValues(
                                      alpha: .7,
                                    ),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                    vertical: 5,
                                  ),
                                  child: Text(
                                    kz
                                        ? 'Аяқтау үшін оңға сырғытыңыз  →'
                                        : 'Ещё свайп вправо — завершить  →',
                                    style: JType.ui(
                                      10.5,
                                      w: FontWeight.w600,
                                      color: palette.source,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    AnimatedSlide(
                      offset: _chromeVisible
                          ? Offset.zero
                          : const Offset(0, -1.08),
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Material(
                          color: palette.bg,
                          elevation: 10,
                          shadowColor: Colors.black.withValues(alpha: .2),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    IconButton(
                                      tooltip: kz ? 'Жабу' : 'Закрыть',
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      icon: Icon(
                                        Icons.close,
                                        color: palette.source,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        kz
                                            ? '«әл-Кәһф» сүресі'
                                            : 'Сура аль-Кахф',
                                        textAlign: TextAlign.center,
                                        style: JType.ui(
                                          17,
                                          w: FontWeight.w700,
                                          color: palette.ink,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      key: const ValueKey(
                                        'kahf-complete-action',
                                      ),
                                      tooltip: app.isDone('kahf')
                                          ? (kz ? 'Оқылды' : 'Прочитано')
                                          : (kz
                                                ? 'Оқылды деп белгілеу'
                                                : 'Отметить прочитанной'),
                                      onPressed: app.isDone('kahf')
                                          ? null
                                          : () => app.markDone('kahf'),
                                      icon: Icon(
                                        app.isDone('kahf')
                                            ? Icons.check_circle
                                            : Icons.check_circle_outline,
                                        color: app.isDone('kahf')
                                            ? palette.accent
                                            : palette.source,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (final option in ReaderPalette.values)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                        ),
                                        child: Tooltip(
                                          message: option.title(app.lang),
                                          child: Semantics(
                                            button: true,
                                            selected: option.id == palette.id,
                                            label: option.title(app.lang),
                                            child: InkResponse(
                                              key: ValueKey(
                                                'kahf-palette-${option.id}',
                                              ),
                                              radius: 24,
                                              onTap: () =>
                                                  _selectPalette(app, option),
                                              child: AnimatedContainer(
                                                duration: const Duration(
                                                  milliseconds: 160,
                                                ),
                                                width: 34,
                                                height: 34,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: option.bg,
                                                  border: Border.all(
                                                    color:
                                                        option.id == palette.id
                                                        ? palette.accent
                                                        : option.divider,
                                                    width:
                                                        option.id == palette.id
                                                        ? 3
                                                        : 1,
                                                  ),
                                                ),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  'ا',
                                                  style: TextStyle(
                                                    color: option.arabic,
                                                    fontFamily: 'Amiri',
                                                    fontSize: 20,
                                                    height: 1,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Semantics(
                          label: kz
                              ? 'Оқу экранын жабу үшін төмен сырғытыңыз'
                              : 'Потяните вниз, чтобы закрыть читалку',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onVerticalDragStart: _startDismissGesture,
                            onVerticalDragUpdate: _updateDismissGesture,
                            onVerticalDragEnd: _completeDismissGesture,
                            onVerticalDragCancel: _restoreAfterDismissGesture,
                            child: SizedBox(
                              width: 116,
                              height: 34,
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: AnimatedBuilder(
                                  animation: _handleHintController,
                                  builder: (context, child) =>
                                      Transform.translate(
                                        offset: Offset(
                                          0,
                                          _handleHintOffset.value,
                                        ),
                                        child: child,
                                      ),
                                  child: AnimatedContainer(
                                    margin: const EdgeInsets.only(top: 6),
                                    duration: const Duration(milliseconds: 180),
                                    width: _dismissDragging ? 38 : 30,
                                    height: 3.5,
                                    decoration: BoxDecoration(
                                      color: palette.source.withValues(
                                        alpha: _dismissDragging ? .5 : .28,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
