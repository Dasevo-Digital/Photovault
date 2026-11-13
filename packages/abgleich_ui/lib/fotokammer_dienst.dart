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
    this.angelegt,
    this.schaerfe,
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
    angelegt: DateTime.tryParse('${j['angelegt']}')?.toLocal(),
    schaerfe: (j['schaerfe'] as num?)?.toDouble(),
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
    angelegt: angelegt,
    schaerfe: schaerfe,
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

  /// Seit wann es in der Kammer liegt.
  final DateTime? angelegt;

  /// Wie scharf die Bildmitte ist; nur innerhalb einer Serie vergleichbar.
  /// `null`, solange es nicht gemessen ist (#348).
  final double? schaerfe;

  bool get istVideo => art == 'VIDEO';
}

/// Was „Sichtung abschliessen“ mit dem frisch geholten [stand] tut (#345):
/// verwerfen, was abgelehnt ist, und freigeben, was es nicht ist – beides
/// nur für das, was schon in [gesehen] stand (#382). Was seit dem letzten
/// Blick hinzukam, etwa vom Handy, hat hier niemand gesichtet; es bleibt in
/// der Kammer. Auch wenn es schon abgelehnt ankam (ein Vermerk beim
/// Hochladen, ein anderes Gerät): Verworfen ist endgültig.
///
/// Verworfen wird dann mit `nurAbgelehnte`: Hebt ein anderes Gerät eine
/// Ablehnung auf, während noch freigegeben wird, bleibt das Foto.
({List<String> weg, List<String> rest}) kammerAbschluss(
  Iterable<Kammereintrag> stand,
  Set<String> gesehen,
) => (
  weg: [
    for (final e in stand)
      if (e.abgelehnt && gesehen.contains(e.id)) e.id,
  ],
  rest: [
    for (final e in stand)
      if (!e.abgelehnt && gesehen.contains(e.id)) e.id,
  ],
);

/// Fotos, die kurz nacheinander entstanden sind (#348).
class Kammerserie {
  const Kammerserie(this.fotos);

  final List<Kammereintrag> fotos;

  /// Das schärfste Foto; `null`, solange keines gemessen ist.
  Kammereintrag? get schaerfstes {
    Kammereintrag? beste;
    for (final f in fotos) {
      final s = f.schaerfe;
      if (s == null) continue;
      if (beste == null || s > beste.schaerfe!) beste = f;
    }
    return beste;
  }

  /// Die bis zu [n] schärfsten, in der Reihenfolge der Aufnahme.
  List<Kammereintrag> schaerfste(int n) {
    final sortiert = [...fotos]
      ..sort((a, b) => (b.schaerfe ?? -1).compareTo(a.schaerfe ?? -1));
    final gewaehlt = sortiert.take(n).toSet();
    return [
      for (final f in fotos)
        if (gewaehlt.contains(f)) f,
    ];
  }
}

/// Gruppiert Fotos, die höchstens [abstand] nacheinander mit derselben
/// Kamera entstanden sind. Nur Gruppen ab zwei Fotos.
///
/// Allein über die Zeit: In der Kammer gibt es keine Bildvergleiche wie in
/// der Bibliothek, sie entstehen erst nach dem Freigeben. Drei Sekunden
/// fassen, was man als Serie auslöst, und trennen die nächste Szene.
List<Kammerserie> kammerserien(
  List<Kammereintrag> eintraege, {
  Duration abstand = const Duration(seconds: 3),
}) {
  final fotos = [
    for (final e in eintraege)
      if (!e.istVideo) e,
  ]..sort((a, b) => a.datum.compareTo(b.datum));
  final serien = <Kammerserie>[];
  var laufend = <Kammereintrag>[];
  void schliesse() {
    if (laufend.length >= 2) serien.add(Kammerserie(laufend));
    laufend = [];
  }

  for (final f in fotos) {
    if (laufend.isNotEmpty &&
        (f.modell != laufend.last.modell ||
            f.datum.difference(laufend.last.datum) > abstand)) {
      schliesse();
    }
    laufend.add(f);
  }
  schliesse();
  return serien;
}

/// Wohin Fotos beim Freigeben kommen (#349).
class Kammerziel {
  const Kammerziel({
    this.album,
    this.schlagwoerter = const [],
    this.breite,
    this.laenge,
  });

  final String? album;
  final List<String> schlagwoerter;
  final double? breite;
  final double? laenge;

  bool get hatOrt => breite != null && laenge != null;
  bool get leer => album == null && schlagwoerter.isEmpty && !hatOrt;

  Map<String, Object?> get alsJson => {
    'album': ?album,
    if (schlagwoerter.isNotEmpty) 'schlagwoerter': schlagwoerter,
    'breite': ?breite,
    'laenge': ?laenge,
  };
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
  /// [stufe] 3: Sterne und Ablehnung beim Sichten (#345). [stufe] 4: Album,
  /// Schlagwörter und Ort beim Freigeben (#349).
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
  Future<void> sichten(List<String> ids, {int? sterne, bool? abgelehnt}) {
    _urteile++;
    final lauf = _sichte(ids, sterne: sterne, abgelehnt: abgelehnt);
    _urteileUnterwegs.add(lauf);
    return lauf.whenComplete(() => _urteileUnterwegs.remove(lauf));
  }

  Future<void> _sichte(List<String> ids, {int? sterne, bool? abgelehnt}) async {
    // Der Server nimmt höchstens 500 auf einmal.
    for (var i = 0; i < ids.length; i += 200) {
      await verbindung.schicke('api/v1/kammer/sichten', {
        'ids': ids.sublist(i, (i + 200).clamp(0, ids.length)),
        'sterne': ?sterne,
        'abgelehnt': ?abgelehnt,
      });
    }
  }

  final _urteileUnterwegs = <Future<void>>{};

  /// Wie viele Urteile von hier begonnen haben – so fällt auf, wenn eines
  /// während des Holens der Liste kam.
  var _urteile = 0;

  /// Die Liste für „Sichtung abschliessen“ (#382): erst, wenn die Urteile
  /// von hier angekommen sind. Kommt während des Holens noch eines dazu,
  /// wird noch einmal geholt – sonst fehlte eine eben vergebene Ablehnung.
  Future<List<Kammereintrag>> listeNachUrteilen() async {
    var l = const <Kammereintrag>[];
    for (var runde = 0; runde < 3; runde++) {
      await urteileAngekommen();
      final vorher = _urteile;
      l = await liste();
      if (vorher == _urteile && _urteileUnterwegs.isEmpty) break;
    }
    return l;
  }

  /// Wartet, bis die Urteile von hier beim Server sind (#382). Vor dem
  /// Abschliessen: Holte die Liste den Stand davor, fehlte eine eben
  /// vergebene Ablehnung, und das Foto käme in die Bibliothek. Ein
  /// gescheitertes Urteil zählt als angekommen – die Oberfläche hat es
  /// schon zurückgenommen.
  Future<void> urteileAngekommen() async {
    for (var runde = 0; runde < 3 && _urteileUnterwegs.isNotEmpty; runde++) {
      await Future.wait([
        for (final f in [..._urteileUnterwegs]) f.catchError((Object _) {}),
      ]);
    }
  }

  Future<List<Kammereintrag>> liste() async {
    final j = await verbindung.hole('api/v1/kammer');
    final l = [
      for (final e in (j['eintraege'] as List? ?? const []))
        if (e is Map) Kammereintrag.aus(e.cast<String, Object?>()),
    ];
    anzahl.value = l.length;
    aeltester = l
        .map((e) => e.angelegt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
    return l;
  }

  /// Seit wann das älteste Foto wartet; `null`, solange niemand gefragt hat
  /// oder die Kammer leer ist.
  DateTime? aeltester;

  /// Holt die Zahl für Menü und Erinnerung, ohne etwas zu melden: Ein Server,
  /// der die Kammer nicht kennt oder gerade weg ist, ist hier kein Fehler.
  Future<void> aktualisiere() async {
    try {
      if (await moeglich()) await liste();
    } on Object {
      // Beim nächsten Mal.
    }
  }

  /// Ab wie vielen Tagen an wartende Fotos erinnert wird (#350).
  static const erinnerungNachTagen = 3;

  /// Wie viele Fotos seit wie vielen Tagen warten, wenn es Zeit für eine
  /// Erinnerung ist; sonst `null`. Erst nach [aktualisiere] sinnvoll.
  ({int anzahl, int tage})? faelligeErinnerung([DateTime? jetzt]) {
    final n = anzahl.value ?? 0;
    final seit = aeltester;
    if (n == 0 || seit == null) return null;
    final tage = (jetzt ?? DateTime.now()).difference(seit).inDays;
    return tage < erinnerungNachTagen ? null : (anzahl: n, tage: tage);
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
    Kammerziel? ziel,
  }) async {
    final r = Kammerfreigabe();
    try {
      for (var i = 0; i < ids.length; i += stapel) {
        final teil = ids.sublist(i, (i + stapel).clamp(0, ids.length));
        final j = await verbindung.schicke('api/v1/kammer/freigeben', {
          'ids': teil,
          if (ziel != null && !ziel.leer) 'ziel': ziel.alsJson,
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
  /// Mit [nurAbgelehnte] nur, was am Server noch abgelehnt ist (#358): Ein
  /// anderes Gerät kann die Ablehnung inzwischen aufgehoben haben.
  Future<int> verwerfen(List<String> ids, {bool nurAbgelehnte = false}) async {
    var n = 0;
    // Der Server nimmt höchstens 500 auf einmal.
    for (var i = 0; i < ids.length; i += 200) {
      final teil = ids.sublist(i, (i + 200).clamp(0, ids.length));
      final j = await verbindung.schicke('api/v1/kammer/verwerfen', {
        'ids': teil,
        if (nurAbgelehnte) 'nurAbgelehnte': true,
      });
      _vergiss(teil);
      n += (j['verworfen'] as num?)?.toInt() ?? 0;
    }
    return n;
  }

  void _vergiss(Iterable<String> ids) {
    for (final id in ids) {
      _bilder
        ..remove('$id/miniatur')
        ..remove('$id/vorschau');
    }
  }
}
