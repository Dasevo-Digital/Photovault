import 'package:flutter/foundation.dart';
import 'package:kern/abgleich/verbindung.dart';

/// Ein Foto in der Fotokammer des Servers (#336).
class Kammereintrag {
  const Kammereintrag({
    required this.id,
    required this.name,
    required this.groesse,
    required this.datum,
    required this.art,
    this.kamera,
    this.modell,
    this.hatBild = true,
    this.sterne = 0,
    this.abgelehnt = false,
  });

  factory Kammereintrag.aus(Map<String, Object?> j) => Kammereintrag(
    id: j['id']! as String,
    name: j['name']! as String,
    groesse: (j['groesse'] as num?)?.toInt() ?? 0,
    datum: DateTime.tryParse('${j['datum']}')?.toLocal() ?? DateTime(1970),
    art: j['art'] as String? ?? 'IMAGE',
    kamera: j['kamera'] as String?,
    modell: j['modell'] as String?,
    // Ohne Masse hat der Server keine Vorschau machen können.
    hatBild: j['breite'] != null,
    sterne: (j['sterne'] as num?)?.toInt() ?? 0,
    abgelehnt: j['abgelehnt'] == true,
  );

  /// Dasselbe Foto mit einem neuen Urteil.
  Kammereintrag mit({int? sterne, bool? abgelehnt}) => Kammereintrag(
    id: id,
    name: name,
    groesse: groesse,
    datum: datum,
    art: art,
    kamera: kamera,
    modell: modell,
    hatBild: hatBild,
    sterne: sterne ?? this.sterne,
    abgelehnt: abgelehnt ?? this.abgelehnt,
  );

  final String id;
  final String name;
  final int groesse;
  final DateTime datum;
  final String art;
  final String? kamera;
  final String? modell;
  final bool hatBild;

  /// Was beim Sichten vergeben wurde (#345).
  final int sterne;
  final bool abgelehnt;

  bool get istVideo => art == 'VIDEO';
}

/// Was ein Freigeben ergab.
class Kammerfreigabe {
  int neu = 0;
  int schonDa = 0;
  final gescheitert = <String, String?>{};
}

/// Spricht mit der Fotokammer des Servers (siehe dort `Fotokammer`).
///
/// Die Kammer liegt nur am Server: Ihre Fotos sind nicht in der Kopie der
/// Bibliothek auf diesem Rechner, darum holt dieser Dienst Liste und Bilder
/// jedes Mal von dort.
class Fotokammerdienst {
  Fotokammerdienst(this.verbindung, {this.abgleichen});

  final Serververbindung verbindung;

  /// Nach allem, was die Bibliothek änderte – Freigeben bringt Aufnahmen
  /// hinein, Hineinlegen legt sie in den Papierkorb –, damit die Kopie hier
  /// es gleich erfährt.
  final Future<void> Function()? abgleichen;

  /// Wie viele Fotos gerade darin liegen; `null`, solange es niemand
  /// gefragt hat. Für die Zahl in der Seitenleiste.
  final anzahl = ValueNotifier<int?>(null);

  final _bilder = <String, Uint8List>{};

  /// Wie viele auf einmal freigegeben werden: Der Server importiert sie
  /// nacheinander, ein RAW braucht Sekunden – und ein Proxy davor wartet
  /// nicht ewig auf die Antwort.
  static const stapel = 4;

  /// Ob der Server die Kammer kennt. Ein älterer würde `kammer` beim
  /// Hochladen übergehen und das Foto gleich in die Bibliothek legen.
  /// [stufe] 2: Fotos der Bibliothek lassen sich hineinlegen (#337).
  /// [stufe] 3: Sterne und Ablehnung beim Sichten (#345).
  Future<bool> moeglich({int stufe = 1}) async => await this.stufe() >= stufe;

  /// Was der Server von der Kammer kennt; 0, wenn gar nichts.
  Future<int> stufe() async {
    try {
      final z = await verbindung.hole('api/v1/zustand');
      return (z['funktionen'] as Map?)?['fotokammer'] as int? ?? 0;
    } on Object {
      return 0;
    }
  }

  /// Merkt das Urteil über [ids] am Server.
  Future<void> sichten(List<String> ids, {int? sterne, bool? abgelehnt}) =>
      verbindung.schicke('api/v1/kammer/sichten', {
        'ids': ids,
        'sterne': ?sterne,
        'abgelehnt': ?abgelehnt,
      });

  Future<List<Kammereintrag>> liste() async {
    final j = await verbindung.hole('api/v1/kammer');
    final l = [
      for (final e in (j['eintraege'] as List? ?? const []))
        if (e is Map) Kammereintrag.aus(e.cast<String, Object?>()),
    ];
    anzahl.value = l.length;
    return l;
  }

  /// Miniatur oder Vorschau; `null`, wenn der Server keine hat.
  Future<Uint8List?> bild(String id, {required bool klein}) {
    final schluessel = '$id/${klein ? 'miniatur' : 'vorschau'}';
    if (_bilder[schluessel] case final b?) return Future.value(b);
    // Vorladen und Anzeigen fragen oft gleichzeitig – einmal holen.
    // Ein Block, kein Pfeil: `remove` gäbe diese Future selbst zurück, und
    // whenComplete wartete dann auf sich – für immer.
    return _unterwegs[schluessel] ??= _hole(schluessel, klein).whenComplete(() {
      _unterwegs.remove(schluessel);
    });
  }

  final _unterwegs = <String, Future<Uint8List?>>{};

  /// Das Foto in voller Auflösung (#342); `null`, wenn der Server es nicht
  /// liefern kann. Nicht im Zwischenspeicher: So ein Bild hat 20 MB und
  /// mehr, und gebraucht wird es nur für das Foto, das gerade offen ist.
  Future<Uint8List?> vollbild(String id) async {
    final r = await verbindung.anfrage(
      'GET',
      'api/v1/kammer/$id/vollbild',
      // Ein RAW zu wandeln kann dauern, wenn andere davor warten.
      zeitlimit: const Duration(minutes: 5),
    );
    if (r.statusCode == 404 || r.statusCode == 422) return null;
    if (r.statusCode != 200) throw Serverfehler(r.statusCode, r.body);
    return r.bodyBytes;
  }

  Future<Uint8List?> _hole(String schluessel, bool klein) async {
    final r = await verbindung.anfrage(
      'GET',
      'api/v1/kammer/$schluessel',
      zeitlimit: const Duration(minutes: 1),
    );
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) throw Serverfehler(r.statusCode, r.body);
    // Die Miniaturen alle, die Vorschauen nur ein paar: Eine ist bis zu
    // einem Megabyte gross.
    if (!klein) {
      final vorschauen = _bilder.keys.where((k) => k.endsWith('/vorschau'));
      if (vorschauen.length >= 12) _bilder.remove(vorschauen.first);
    }
    return _bilder[schluessel] = r.bodyBytes;
  }

  /// Gibt [ids] frei, in kleinen Stapeln; [fortschritt] bekommt, wie
  /// viele schon durch sind.
  Future<Kammerfreigabe> freigeben(
    List<String> ids, {
    void Function(int erledigt, int gesamt)? fortschritt,
  }) async {
    final r = Kammerfreigabe();
    try {
      for (var i = 0; i < ids.length; i += stapel) {
        final teil = ids.sublist(i, (i + stapel).clamp(0, ids.length));
        final j = await verbindung.schicke('api/v1/kammer/freigeben', {
          'ids': teil,
        }, zeitlimit: const Duration(minutes: 5));
        for (final e in (j['ergebnisse'] as List? ?? const [])) {
          if (e is! Map) continue;
          switch (e['ausgang']) {
            case 'imported':
              r.neu++;
            case 'duplicateSkipped':
              r.schonDa++;
            default:
              r.gescheitert['${e['id']}'] = e['fehler'] as String?;
          }
        }
        fortschritt?.call(i + teil.length, ids.length);
      }
    } finally {
      _vergiss(ids);
      if (r.neu > 0) await abgleichen?.call();
    }
    return r;
  }

  /// Legt Aufnahmen der Bibliothek zurück in die Kammer (#337): Sie gehen
  /// in den Papierkorb, und Freigeben holt sie samt Alben und Bearbeitungen
  /// zurück. In [Kammerfreigabe.neu] steht, wie viele jetzt dort liegen; in
  /// `gescheitert` der Grund der übrigen (`unbekannt`, `gesperrt` oder ein
  /// Fehlertext).
  Future<Kammerfreigabe> aufnehmen(List<String> aufnahmen) async {
    final r = Kammerfreigabe();
    try {
      for (var i = 0; i < aufnahmen.length; i += 2 * stapel) {
        final teil = aufnahmen.sublist(
          i,
          (i + 2 * stapel).clamp(0, aufnahmen.length),
        );
        final j = await verbindung.schicke('api/v1/kammer/aufnehmen', {
          'ids': teil,
        }, zeitlimit: const Duration(minutes: 5));
        for (final e in (j['ergebnisse'] as List? ?? const [])) {
          if (e is! Map) continue;
          if (e['ausgang'] == 'kammer') {
            r.neu++;
          } else {
            r.gescheitert['${e['aufnahme']}'] =
                (e['fehler'] ?? e['ausgang']) as String?;
          }
        }
      }
    } finally {
      if (r.neu > 0) await abgleichen?.call();
    }
    if (anzahl.value case final n?) anzahl.value = n + r.neu;
    return r;
  }

  /// Löscht [ids] endgültig vom Server; gibt zurück, wie viele es waren.
  Future<int> verwerfen(List<String> ids) async {
    final j = await verbindung.schicke('api/v1/kammer/verwerfen', {'ids': ids});
    _vergiss(ids);
    return (j['verworfen'] as num?)?.toInt() ?? 0;
  }

  void _vergiss(Iterable<String> ids) {
    for (final id in ids) {
      _bilder
        ..remove('$id/miniatur')
        ..remove('$id/vorschau');
    }
  }
}
