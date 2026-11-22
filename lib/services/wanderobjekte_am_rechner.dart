import 'package:http/http.dart' as http;
import 'package:kern/services/wanderobjekte.dart';

import '../state/library_state.dart';

/// Gipfel, Hütten und Quellen für die Landschaft am Rechner.
///
/// **Ohne Server wie bisher:** aus der Bibliothek, sonst von Overpass, und
/// dann gemerkt ([wanderobjekteAusBibliothek]); [netz] ist dafür da.
///
/// **Verbunden nur über den eigenen Server** (#474), mit derselben
/// Anmeldung wie der Abgleich – so wie Browser und Handy. Bis hierher
/// fragte auch eine verbundene Bibliothek Overpass selbst, mit der Adresse
/// des Rechners und dem Ausschnitt der Tour, obwohl Karten und Höhen seit
/// #468 nur noch über den Server kommen. Antwortet der Server nicht oder
/// kennt er den Weg nicht (vor 3.38), gibt es **keinen Rückfall auf
/// Overpass**: [serverLiefertNicht] wird gerufen, damit die Oberfläche es
/// sagt, und die Landschaft bleibt ohne Schilder.
///
/// Verbunden wird die Antwort nicht in der Bibliothek gemerkt: Das tut der
/// Server. Er antwortet mit einer leeren Liste auch dann, wenn Overpass
/// ihm gerade nicht geantwortet hat; hier gemerkt, bliebe der Ausschnitt
/// für immer leer.
Future<List<Wanderobjekt>> wanderobjekteAmRechner(
  LibraryState library, {
  required double sued,
  required double west,
  required double nord,
  required double ost,
  required void Function() serverLiefertNicht,
  http.Client? netz,
}) async {
  if (!library.verbunden) {
    return wanderobjekteAusBibliothek(
      library.db,
      sued: sued,
      west: west,
      nord: nord,
      ost: ost,
      netz: netz,
    );
  }
  final server = library.abgleich?.verbindung;
  final punkte = server == null
      ? null
      : await wanderobjekteVomServer(
          server,
          sued: sued,
          west: west,
          nord: nord,
          ost: ost,
        );
  if (punkte == null) {
    serverLiefertNicht();
    return const [];
  }
  return punkte;
}
