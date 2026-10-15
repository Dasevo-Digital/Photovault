import 'dart:convert';

import 'verbindung.dart';

/// Ein Konto auf dem Server, wie ein Verwalter es sieht.
class Kontoeintrag {
  const Kontoeintrag({
    required this.id,
    required this.name,
    required this.verwalter,
    required this.totp,
    required this.gesperrt,
    required this.geraete,
    required this.du,
  });

  factory Kontoeintrag.ausJson(Map<String, Object?> j) => Kontoeintrag(
    id: j['id']! as String,
    name: j['name']! as String,
    verwalter: j['verwalter'] == true,
    totp: j['totp'] == true,
    gesperrt: j['gesperrt'] == true,
    geraete: (j['geraete'] as num?)?.toInt() ?? 0,
    du: j['du'] == true,
  );

  final String id;
  final String name;
  final bool verwalter;
  final bool totp;

  /// Nach zu vielen Fehlversuchen vorübergehend gesperrt.
  final bool gesperrt;

  /// Wie viele Geräte angemeldet sind.
  final int geraete;

  /// Das eigene Konto – das ändert jeder für sich, nicht hier.
  final bool du;
}

/// Die Konten des Servers verwalten (siehe dort `Kontenapi`) – nur für
/// Verwalter; sonst wirft jeder Aufruf [Serverfehler] mit 403.
class Kontenverwaltung {
  Kontenverwaltung(this.verbindung);

  final Serververbindung verbindung;

  /// Ob das angemeldete Konto Verwalter ist.
  Future<bool> binVerwalter() async =>
      (await verbindung.hole('api/v1/konto'))['verwalter'] == true;

  Future<List<Kontoeintrag>> liste() async => [
    for (final k in (await verbindung.hole('api/v1/konten'))['konten']! as List)
      Kontoeintrag.ausJson((k as Map).cast<String, Object?>()),
  ];

  Future<Kontoeintrag> legeAn(
    String name,
    String passwort, {
    bool verwalter = false,
  }) async => Kontoeintrag.ausJson(
    await verbindung.schicke('api/v1/konten', {
      'name': name.trim(),
      'passwort': passwort,
      'verwalter': verwalter,
    }),
  );

  /// Setzt ein neues Passwort; alle Geräte des Kontos sind danach
  /// abgemeldet.
  Future<void> setzePasswort(String id, String neu) =>
      verbindung.schicke('api/v1/konten/$id/passwort', {'neu': neu});

  Future<void> totpZuruecksetzen(String id) =>
      verbindung.schicke('api/v1/konten/$id/totp-zuruecksetzen', const {});

  Future<void> entsperre(String id) =>
      verbindung.schicke('api/v1/konten/$id/entsperren', const {});

  /// Entfernt das Konto; seine Bibliothek legt der Server beiseite, statt
  /// sie zu löschen.
  Future<void> entferne(String id) async {
    final r = await verbindung.anfrage(
      'DELETE',
      'api/v1/konten/${Uri.encodeComponent(id)}',
    );
    if (r.statusCode != 200) throw Serverfehler(r.statusCode, r.body);
  }
}

/// Was der Server in `fehler` als Grund nennt – oder `null`.
String? grundAus(Serverfehler f) {
  try {
    final j = jsonDecode(f.text);
    return j is Map && j['fehler'] is String ? j['fehler'] as String : null;
  } on FormatException {
    return null;
  }
}
