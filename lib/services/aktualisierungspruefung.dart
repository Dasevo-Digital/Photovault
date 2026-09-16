import 'package:dio/dio.dart';

/// Woran die Abfrage gescheitert ist.
///
/// Kein fertiger Satz, weil dieser Dienst keine Oberflächensprache kennt –
/// den Text setzt der Einstellungs-Bildschirm ein.
enum Aktualisierungsproblem { keineVeroeffentlichungen, keineVersion }

class AktualisierungsFehler implements Exception {
  final Aktualisierungsproblem problem;
  const AktualisierungsFehler(this.problem);
}

/// Ergebnis einer Prüfung auf eine neuere Fassung.
class Aktualisierungsstand {
  const Aktualisierungsstand({
    required this.installiert,
    required this.neueste,
    required this.istNeuereVerfuegbar,
    this.seitenUrl,
  });

  final String installiert;
  final String neueste;
  final bool istNeuereVerfuegbar;

  /// Seite, auf der die neue Fassung liegt – zum Selbst-Herunterladen. Die
  /// App lädt sich bewusst NICHT selbst herunter oder aktualisiert sich:
  /// Ein Programm, das sich unbeaufsichtigt ersetzt, passt nicht zu einem,
  /// dessen Kern ein verschlüsselter privater Bereich ist.
  final String? seitenUrl;
}

/// Fragt beim öffentlichen Veröffentlichungsverzeichnis nach, ob es eine
/// neuere Fassung gibt.
///
/// **Ausschliesslich auf ausdrückliche Anforderung.** Ebenso das Laden der
/// KI-Modelle und der Ortsdaten – beides nur auf Knopfdruck.
///
/// Hier stand einmal, die App spreche sonst mit keinem Server. Das gilt
/// nicht mehr, seit es die Karte gibt: Sie holt ihre Kacheln beim
/// Anzeigen von OpenStreetMap, OpenTopoMap, Esri und AWS Open Data, ohne
/// dass jemand einen Knopf drückt, und in jeder Kacheladresse steht der
/// Ausschnitt. Der Satz blieb trotzdem stehen und wurde erst in der
/// 17. Prüfrunde bemerkt; die Oberfläche sagt es jetzt unter
/// Einstellungen → Karte. Eine
/// stille Prüfung im Hintergrund würde bei jedem Start verraten, dass und
/// wann dieses Programm benutzt wird – das wäre ein Bruch mit seiner
/// Grundhaltung, für den Gegenwert einer Zahl.
///
/// Übertragen wird dabei nichts über die Bibliothek: Es ist ein einfacher
/// Abruf einer öffentlichen Liste, ohne Kennung, ohne Nutzungsdaten.
class Aktualisierungspruefung {
  Aktualisierungspruefung({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// Die vollständige Liste, nicht `/releases/latest`.
  ///
  /// `latest` überspringt grundsätzlich alles, was als Vorabversion
  /// markiert ist – und genau das sind hier alle bisherigen
  /// Veröffentlichungen. Die Abfrage lieferte deshalb 404, und die App
  /// riet fälschlich auf eine fehlende Internetverbindung
  /// (Fehlerbericht). Aus der Liste wird selbst die höchste Nummer
  /// bestimmt; Entwürfe bleiben dabei aussen vor.
  // Die numerische Repository-Kennung bleibt beim Umbenennen oder beim
  // Übertrag in eine Organisation gleich. Damit gehört keine persönliche
  // Kontokennung in den Quelltext oder in das ausgelieferte Programm.
  static const quelle =
      'https://api.github.com/repositories/1333480027/releases';

  Future<Aktualisierungsstand> pruefe(String installierteVersion) async {
    final antwort = await _dio.get<List<dynamic>>(
      quelle,
      options: Options(
        // Kurz halten: Wer offline ist, soll nicht eine Minute warten.
        // Bewusst nur receiveTimeout – sendTimeout gilt bei dio nur für
        // Anfragen mit Rumpf und wirft bei einem GET.
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    final liste = antwort.data;
    if (liste == null || liste.isEmpty) {
      throw const AktualisierungsFehler(
          Aktualisierungsproblem.keineVeroeffentlichungen);
    }

    String? hoechste;
    String? seite;
    for (final eintrag in liste) {
      if (eintrag is! Map) continue;
      if (eintrag['draft'] == true) continue;
      final markierung = (eintrag['tag_name'] as String?)?.trim();
      if (markierung == null || markierung.isEmpty) continue;
      if (hoechste == null || istNeuer(markierung, hoechste)) {
        hoechste = markierung;
        seite = eintrag['html_url'] as String?;
      }
    }
    if (hoechste == null) {
      throw const AktualisierungsFehler(Aktualisierungsproblem.keineVersion);
    }

    return Aktualisierungsstand(
      installiert: installierteVersion,
      neueste: hoechste,
      istNeuereVerfuegbar: istNeuer(hoechste, installierteVersion),
      seitenUrl: seite,
    );
  }

  /// Vergleicht zwei Versionsangaben. Ein führendes `v` und alles ab einem
  /// Bindestrich (Vorabfassungen wie `1.2.0-beta`) werden dabei ignoriert.
  ///
  /// Nicht deutbare Angaben gelten als NICHT neuer – im Zweifel lieber
  /// keine Aktualisierung melden als eine erfinden.
  static bool istNeuer(String kandidat, String vergleich) {
    final a = _teile(kandidat);
    final b = _teile(vergleich);
    if (a.isEmpty || b.isEmpty) return false;
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static List<int> _teile(String roh) {
    var s = roh.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    final bindestrich = s.indexOf('-');
    if (bindestrich >= 0) s = s.substring(0, bindestrich);
    final plus = s.indexOf('+');
    if (plus >= 0) s = s.substring(0, plus);
    final teile = s.split('.');
    final zahlen = <int>[];
    for (final t in teile) {
      final n = int.tryParse(t);
      if (n == null) return const [];
      zahlen.add(n);
    }
    return zahlen;
  }
}
