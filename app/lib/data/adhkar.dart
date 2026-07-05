import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// Контент зикров. Генерируется из «Jadwal — сбор зикров.xlsx»
/// скриптом tools/convert_adhkar.py — руками не редактировать.
class Zikr {
  final int order;
  final String ar;
  final String? translit, ru, kz, fazRu, fazKz, note;
  final String source;
  final int repeat;
  final String status;

  const Zikr({
    required this.order,
    required this.ar,
    this.translit,
    this.ru,
    this.kz,
    this.fazRu,
    this.fazKz,
    this.note,
    required this.source,
    required this.repeat,
    required this.status,
  });

  String? translation(String lang) => lang == 'kz' ? (kz ?? ru) : ru;
  String? faz(String lang) => lang == 'kz' ? (fazKz ?? fazRu) : fazRu;

  factory Zikr.fromJson(Map<String, dynamic> j) => Zikr(
        order: j['order'] as int,
        ar: j['ar'] as String,
        translit: j['translit'] as String?,
        ru: j['ru'] as String?,
        kz: j['kz'] as String?,
        fazRu: j['fazRu'] as String?,
        fazKz: j['fazKz'] as String?,
        note: j['note'] as String?,
        source: j['source'] as String,
        repeat: j['repeat'] as int,
        status: j['status'] as String,
      );
}

class ZikrCollection {
  final String id, titleRu, titleKz;
  final List<Zikr> items;

  const ZikrCollection(
      {required this.id, required this.titleRu, required this.titleKz, required this.items});

  String title(String lang) => lang == 'kz' ? titleKz : titleRu;

  factory ZikrCollection.fromJson(Map<String, dynamic> j) => ZikrCollection(
        id: j['id'] as String,
        titleRu: j['titleRu'] as String,
        titleKz: j['titleKz'] as String,
        items: (j['items'] as List).map((e) => Zikr.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class AdhkarRepository {
  static Map<String, ZikrCollection>? _cache;

  static Future<Map<String, ZikrCollection>> load() async {
    if (_cache != null) return _cache!;
    final raw = await rootBundle.loadString('assets/data/adhkar.json');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    _cache = {
      for (final c in data['collections'] as List)
        (c as Map<String, dynamic>)['id'] as String: ZikrCollection.fromJson(c)
    };
    return _cache!;
  }
}
