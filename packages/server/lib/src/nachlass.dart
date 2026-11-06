import 'dart:async';
import 'dart:convert';

import 'package:kern/protokoll.dart';
import 'package:shelf/shelf.dart';

import 'anmeldung_api.dart';
import 'konten/kontodienst.dart';
import 'konten/serverdatenbank.dart';

Response _antwort(Object? daten, {int status = 200}) => Response(
  status,
  body: jsonEncode(daten),
  headers: {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  },
);

/// Ein Nachlasskontakt (#300): [kontakt] darf Zugang zur Bibliothek von
/// [besitzer] verlangen. Widerspricht der Besitzer nicht binnen
/// [fristTage], sieht der Kontakt sie danach wie ein Partner – ganz, nur
/// zum Ansehen und Herunterladen.
class Nachlasskontakt {
  const Nachlasskontakt({
    required this.besitzer,
    required this.kontakt,
    required this.fristTage,
    required this.angelegt,
    this.angefordert,
    this.abgelehnt,
    this.freigegeben,
  });

  final String besitzer;
  final String kontakt;
  final int fristTage;
  final DateTime angelegt;

  /// Wann der Kontakt Zugang verlangt hat – `null`, solange er es nicht
  /// tut oder der Besitzer widersprochen hat.
  final DateTime? angefordert;

  /// Wann der Besitzer zuletzt widersprochen hat.
  final DateTime? abgelehnt;

  /// Seit wann der Kontakt die Bibliothek sieht.
  final DateTime? freigegeben;

  /// Ab wann der Zugang gilt, wenn niemand widerspricht.
  DateTime? get faellig => angefordert?.add(Duration(days: fristTage));
}

/// Nachlasskontakte in server.sqlite – wie die Partnerfreigaben neben den
/// Konten (siehe [Serverdatenbank]).
///
/// **Warum eine Frist und kein Knopf.** Wer Zugang zu den Fotos eines
/// Verstorbenen braucht, kann ihn nicht mehr fragen. Wer noch lebt, soll
/// es dagegen merken und Nein sagen können: Die Anfrage steht bei ihm in
/// Browser, Handy und Rechner, bis er widerspricht oder die Frist um ist.
/// Ohne E-Mail weiss der Server nicht, ob er gelesen wurde – deshalb sind
/// sieben Tage das Mindeste.
///
/// **Was der Zugang ist.** Eine Partnerfreigabe ohne Einschränkung: Hat
/// der Besitzer dem Kontakt schon einen Teil freigegeben, gilt solange
/// alles; nimmt er den Kontakt zurück, gilt wieder, was vorher galt.
class Nachlasskontakte {
  Nachlasskontakte(this._sdb, {DateTime Function()? uhr})
    : _uhr = uhr ?? DateTime.now;

  final Serverdatenbank _sdb;
  final DateTime Function() _uhr;

  /// Die Fristen, die zur Wahl stehen, in Tagen.
  static const fristen = [7, 14, 30, 90];
  static const vorgabeFrist = 30;

  /// So viele Kontakte darf ein Konto benennen.
  static const hoechstens = 5;

  /// Nach einem Widerspruch darf der Kontakt erst so viel später wieder
  /// fragen – sonst stünde die Anfrage gleich wieder da.
  static const pauseNachWiderspruch = Duration(days: 7);

  static DateTime? _zeit(Object? ms) =>
      ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null;

  Nachlasskontakt _aus(Map<String, Object?> z) => Nachlasskontakt(
    besitzer: z['besitzer']! as String,
    kontakt: z['kontakt']! as String,
    fristTage: z['frist_tage']! as int,
    angelegt: _zeit(z['angelegt'])!,
    angefordert: _zeit(z['angefordert']),
    abgelehnt: _zeit(z['abgelehnt']),
    freigegeben: _zeit(z['freigegeben']),
  );

  Nachlasskontakt? eintrag(String besitzer, String kontakt) {
    final z = _sdb.db.select(
      'SELECT * FROM nachlass WHERE besitzer = ? AND kontakt = ?',
      [besitzer, kontakt],
    );
    return z.isEmpty ? null : _aus(z.first);
  }

  List<Nachlasskontakt> von(String besitzer) => [
    for (final z in _sdb.db.select(
      'SELECT * FROM nachlass WHERE besitzer = ? ORDER BY angelegt',
      [besitzer],
    ))
      _aus(z),
  ];

  List<Nachlasskontakt> fuer(String kontakt) => [
    for (final z in _sdb.db.select(
      'SELECT * FROM nachlass WHERE kontakt = ? ORDER BY angelegt',
      [kontakt],
    ))
      _aus(z),
  ];

  /// Benennt [kontakt] oder ändert seine Frist. Eine laufende Anfrage
  /// bleibt, mit der neuen Frist.
  void benenne(String besitzer, String kontakt, int fristTage) {
    if (besitzer == kontakt) throw ArgumentError('sich selbst');
    if (!fristen.contains(fristTage)) throw ArgumentError('Frist');
    final da = von(besitzer);
    if (da.length >= hoechstens && !da.any((k) => k.kontakt == kontakt)) {
      throw StateError('höchstens $hoechstens Nachlasskontakte');
    }
    _sdb.db.execute(
      'INSERT INTO nachlass (besitzer, kontakt, frist_tage, angelegt) '
      'VALUES (?, ?, ?, ?) ON CONFLICT (besitzer, kontakt) '
      'DO UPDATE SET frist_tage = excluded.frist_tage',
      [besitzer, kontakt, fristTage, _uhr().millisecondsSinceEpoch],
    );
  }

  /// Nimmt [kontakt] zurück – samt Anfrage und Zugang. Eine Freigabe,
  /// die erst mit dem Zugang entstand, geht mit; eine ältere bleibt, mit
  /// ihrer Einschränkung.
  bool entferne(String besitzer, String kontakt) {
    _sdb.db.execute('DELETE FROM nachlass WHERE besitzer = ? AND kontakt = ?', [
      besitzer,
      kontakt,
    ]);
    final weg = _sdb.db.updatedRows > 0;
    _sdb.db.execute(
      'DELETE FROM partnerfreigaben WHERE besitzer = ? AND partner = ? '
      'AND nachlass = 1',
      [besitzer, kontakt],
    );
    return weg;
  }

  /// [kontakt] verlangt Zugang zur Bibliothek von [besitzer]. Gibt den
  /// Eintrag zurück; [StateError], wenn er gerade erst abgewiesen wurde.
  Nachlasskontakt fordereAn(String besitzer, String kontakt) {
    final e = eintrag(besitzer, kontakt);
    if (e == null) throw ArgumentError('kein Nachlasskontakt');
    if (e.freigegeben != null || e.angefordert != null) return e;
    final jetzt = _uhr();
    if (e.abgelehnt case final a?
        when jetzt.isBefore(a.add(pauseNachWiderspruch))) {
      throw StateError('gerade erst abgelehnt');
    }
    _sdb.db.execute(
      'UPDATE nachlass SET angefordert = ? WHERE besitzer = ? AND kontakt = ?',
      [jetzt.millisecondsSinceEpoch, besitzer, kontakt],
    );
    return eintrag(besitzer, kontakt)!;
  }

  /// Der Kontakt zieht seine Anfrage zurück.
  void zieheZurueck(String besitzer, String kontakt) => _sdb.db.execute(
    'UPDATE nachlass SET angefordert = NULL '
    'WHERE besitzer = ? AND kontakt = ? AND freigegeben IS NULL',
    [besitzer, kontakt],
  );

  /// Der Besitzer widerspricht. `false`, wenn nichts offen war.
  bool lehneAb(String besitzer, String kontakt) {
    _sdb.db.execute(
      'UPDATE nachlass SET angefordert = NULL, abgelehnt = ? '
      'WHERE besitzer = ? AND kontakt = ? AND angefordert IS NOT NULL '
      'AND freigegeben IS NULL',
      [_uhr().millisecondsSinceEpoch, besitzer, kontakt],
    );
    return _sdb.db.updatedRows > 0;
  }

  /// Gibt frei, was ohne Widerspruch fällig ist. Liefert die neu
  /// freigegebenen Einträge.
  List<Nachlasskontakt> gibFaelligeFrei() {
    final jetzt = _uhr();
    final frei = <Nachlasskontakt>[];
    for (final z in _sdb.db.select(
      'SELECT * FROM nachlass WHERE angefordert IS NOT NULL '
      'AND freigegeben IS NULL',
    )) {
      final e = _aus(z);
      if (jetzt.isBefore(e.faellig!)) continue;
      _sdb.db.execute(
        'UPDATE nachlass SET freigegeben = ? WHERE besitzer = ? AND kontakt = ?',
        [jetzt.millisecondsSinceEpoch, e.besitzer, e.kontakt],
      );
      // Sichtbar wird es über die Partnerfreigabe; die bestehende bleibt,
      // wie sie war – solange der Zugang gilt, ohne ihre Einschränkung.
      _sdb.db.execute(
        'INSERT OR IGNORE INTO partnerfreigaben (besitzer, partner, angelegt, '
        'nachlass) VALUES (?, ?, ?, 1)',
        [e.besitzer, e.kontakt, jetzt.millisecondsSinceEpoch],
      );
      frei.add(eintrag(e.besitzer, e.kontakt)!);
    }
    return frei;
  }
}

/// Gibt frei, was fällig ist – stündlich, damit der Zugang auch kommt,
/// wenn niemand nachsieht.
class Nachlassablauf {
  Nachlassablauf(this.konten, {this.takt = const Duration(hours: 1)});

  final Kontodienst konten;
  final Duration takt;
  Timer? _wecker;

  /// Fängt alles ab: Im Takt liefe ein Fehler in keine Anfrage, sondern
  /// beendete den ganzen Server.
  void pruefe() {
    try {
      for (final e in konten.nachlass.gibFaelligeFrei()) {
        protokoll(
          'Nachlass: ${konten.konto(e.kontakt)?.name ?? e.kontakt} sieht jetzt '
          'die Bibliothek von ${konten.konto(e.besitzer)?.name ?? e.besitzer}',
        );
      }
    } catch (e) {
      protokoll('Nachlass nicht geprüft: $e');
    }
  }

  void starte() {
    pruefe();
    _wecker = Timer.periodic(takt, (_) => pruefe());
  }

  void beende() => _wecker?.cancel();
}

/// Die Wege zum Nachlasskontakt (#300).
class Nachlassapi {
  Nachlassapi(this.konten);

  final Kontodienst konten;
  Nachlasskontakte get _dienst => konten.nachlass;

  String? _iso(DateTime? t) => t?.toUtc().toIso8601String();

  Map<String, Object?> _eintrag(Nachlasskontakt e, String konto) => {
    'konto': konto,
    'name': konten.konto(konto)?.name ?? '',
    'frist': e.fristTage,
    'angefordert': ?_iso(e.angefordert),
    'faellig': ?_iso(e.faellig),
    'freigegeben': ?_iso(e.freigegeben),
    'abgelehnt': ?_iso(e.abgelehnt),
  };

  /// `{kontakte: [...], fuerMich: [...], fristen}` – wen dieses Konto
  /// benannt hat, und für wen es benannt ist. Was fällig ist, gilt vorher.
  Response liste(Request r) {
    _dienst.gibFaelligeFrei();
    final ich = kontoVon(r).id;
    return _antwort({
      'kontakte': [
        for (final e in _dienst.von(ich))
          if (konten.konto(e.kontakt) != null) _eintrag(e, e.kontakt),
      ],
      'fuerMich': [
        for (final e in _dienst.fuer(ich))
          if (konten.konto(e.besitzer) != null) _eintrag(e, e.besitzer),
      ],
      'fristen': Nachlasskontakte.fristen,
    });
  }

  /// `{frist?}` → benennt [konto] als Nachlasskontakt oder ändert die
  /// Frist.
  Future<Response> benennen(Request r, String konto) async {
    final ich = kontoVon(r).id;
    if (konto == ich || konten.konto(konto) == null) {
      return _antwort({'fehler': 'Konto unbekannt'}, status: 404);
    }
    var frist = Nachlasskontakte.vorgabeFrist;
    final text = await r.readAsString();
    if (text.trim().isNotEmpty) {
      try {
        final k = jsonDecode(text);
        if (k is Map && k['frist'] != null) {
          final f = k['frist'];
          if (f is! int || !Nachlasskontakte.fristen.contains(f)) {
            return _antwort({'fehler': 'Frist unbekannt'}, status: 400);
          }
          frist = f;
        }
      } on FormatException {
        return _antwort({'fehler': 'kein JSON'}, status: 400);
      }
    }
    try {
      _dienst.benenne(ich, konto, frist);
    } on StateError catch (e) {
      return _antwort({'fehler': e.message}, status: 409);
    }
    return Response(204);
  }

  /// Nimmt [konto] als Nachlasskontakt zurück – samt Anfrage und Zugang.
  Response entfernen(Request r, String konto) {
    _dienst.entferne(kontoVon(r).id, konto);
    return Response(204);
  }

  /// Der Besitzer widerspricht der Anfrage von [konto].
  Response ablehnen(Request r, String konto) {
    final ich = kontoVon(r).id;
    if (!_dienst.lehneAb(ich, konto)) {
      return _antwort({'fehler': 'nichts offen'}, status: 404);
    }
    protokoll(
      'Nachlass: ${kontoVon(r).name} hat der Anfrage von '
      '${konten.konto(konto)?.name ?? konto} widersprochen',
    );
    return Response(204);
  }

  /// Der Kontakt verlangt Zugang zur Bibliothek von [besitzer] →
  /// `{faellig}`.
  Response anfordern(Request r, String besitzer) {
    final ich = kontoVon(r);
    final Nachlasskontakt e;
    try {
      e = _dienst.fordereAn(besitzer, ich.id);
    } on ArgumentError {
      return _antwort({'fehler': 'unbekannt'}, status: 404);
    } on StateError {
      return _antwort({
        'fehler': 'Gerade erst abgelehnt – später wieder.',
      }, status: 409);
    }
    if (e.freigegeben == null) {
      protokoll(
        'Nachlass: ${ich.name} verlangt Zugang zur Bibliothek von '
        '${konten.konto(besitzer)?.name ?? besitzer} – ohne Widerspruch ab '
        '${e.faellig!.toIso8601String().substring(0, 10)}',
      );
    }
    return _antwort(_eintrag(e, besitzer));
  }

  /// Der Kontakt zieht seine Anfrage zurück.
  Response zurueckziehen(Request r, String besitzer) {
    _dienst.zieheZurueck(besitzer, kontoVon(r).id);
    return Response(204);
  }
}
