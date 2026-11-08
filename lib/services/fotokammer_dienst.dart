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
  );

  final String id;
  final String name;
  final int groesse;
  final DateTime datum;
  final String art;
  final String? kamera;
  final String? modell;
  final bool hatBild;

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
  Fotokammerdienst(this.verbindung, {this.nachFreigabe});

  final Serververbindung verbindung;

  /// Nach einem Freigeben, das etwas in die Bibliothek brachte – damit die
  /// Kopie hier die neuen Aufnahmen holt.
  final Future<void> Function()? nachFreigabe;

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
  Future<bool> moeglich() async {
    try {
      final z = await verbindung.hole('api/v1/zustand');
      return ((z['funktionen'] as Map?)?['fotokammer'] as int? ?? 0) >= 1;
    } on Object {
      return false;
    }
  }

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
      if (r.neu > 0) await nachFreigabe?.call();
    }
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
