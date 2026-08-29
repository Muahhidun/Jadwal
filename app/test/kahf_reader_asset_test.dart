import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('аль-Кахф использует официальную QCF-разметку и четыре темы', () async {
    final html = await File('assets/quran/kahf_reader.html').readAsString();

    expect(html, contains('https://api.quran.com/api/v4'));
    expect(html, contains('https://verses.quran.foundation/fonts/quran'));
    expect(html, contains("page = 293; page <= 304"));
    expect(html, contains('/v4/colrv1/woff2/'));
    expect(html, isNot(contains('/v2/woff2/')));
    expect(html, isNot(contains('tajweedEnabled')));
    expect(html, contains('scroll-snap-type: x mandatory'));
    expect(html, contains('scroll-snap-stop: always'));
    expect(html, contains('#reader {\n      direction: rtl;'));
    expect(html, contains('padding: 3px 2px;'));
    expect(html, contains('border: 1px solid var(--line);'));
    expect(html, contains('border-radius: 10px;'));
    expect(html, contains('.mushaf-line.justified'));
    expect(html, contains('justify-content: space-between;'));
    expect(html, contains("line.classList.add('justified')"));
    expect(html, contains('function fitPage(page)'));
    expect(html, contains("postMessage('toggleChrome')"));
    expect(html, contains("slot.className = 'page-slot'"));
    for (final theme in const ['paper', 'monoLight', 'monoDark', 'softDark']) {
      expect(html, contains(theme));
    }
    expect(html, contains('base-palette'));
    expect(html, contains('line_number'));
  });
}
