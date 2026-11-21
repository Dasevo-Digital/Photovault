import 'package:kern/abgleich/konten.dart' show grundAus;
import 'package:kern/abgleich/verbindung.dart';

import 'l10n/app_localizations.dart';

/// Was die Oberfläche zu einem Fehler sagt – nie die rohe Ausnahme wie
/// „KeineVerbindung(ClientException with SocketException …)“ oder
/// „Serverfehler(400): {"fehler": …}“. Nennt der Server einen Grund, steht
/// der da.
String fehlertext(AppTexte t, Object fehler) => switch (fehler) {
  KeineVerbindung() => t.fehlerOhneServer,
  Serverfehler() => grundAus(fehler) ?? t.fehlerAllgemein,
  _ => t.fehlerAllgemein,
};
