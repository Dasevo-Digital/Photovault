/// Kartenkacheln am Telefon – nur über den eigenen Server (#180, #469).
///
/// Das Telefon ist immer mit einem Server verbunden, solange es eine Karte
/// zeigt. Seine Kacheln holt es darum **nie** selbst beim Anbieter: weder
/// OpenStreetMap und OpenTopoMap, solange der Server (noch) keine liefert,
/// noch die Quellen, die er gar nicht weiterreicht – Höhendaten der
/// Landschaft, Luftbild, CARTO, eine eigene Kartenquelle, Wanderwege.
/// Sonst sähe der Anbieter mit der Adresse des Telefons die Gegenden, die
/// es ansieht, also mittelbar die Orte der Fotos.
library;

import 'package:http/http.dart' as http;
import 'package:http/retry.dart';
import 'package:kern/abgleich/kachelumleitung.dart';
import 'package:kern/abgleich/verbindung.dart';

/// Der Client, über den Karte und Landschaft am Telefon ihre Kacheln
/// holen.
///
/// [server] ist der eigene Server, solange er Kacheln liefert
/// ([serverLiefertKacheln]), sonst `null`. Was nicht über ihn kommen
/// kann, wird mit [KachelNurUeberServer] abgewiesen, ohne dass etwas
/// abgerufen wird – für die Karte ist das wie kein Netz, was im
/// Kachelspeicher des Telefons liegt, bleibt zu sehen.
///
/// [innen] nur für Tests.
http.Client handyKachelnetz({
  required Serververbindung? Function() server,
  http.Client? innen,
}) => _NurServerquellen(
  Kachelumleitung(
    innen ?? RetryClient(http.Client()),
    server: server,
    // Verbunden ist das Telefon immer, wenn es Karten zeigt.
    nurUeberServer: () => true,
  ),
);

/// Lässt nur Kacheln der [serverKartenquellen] weiter zur
/// [Kachelumleitung]; alles andere ginge dort unverändert zum Anbieter.
class _NurServerquellen extends http.BaseClient {
  _NurServerquellen(this._innen);

  final http.Client _innen;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest anfrage) async {
    if (anfrage.method != 'GET' || serverKachelpfad(anfrage.url) == null) {
      throw KachelNurUeberServer(anfrage.url);
    }
    return _innen.send(anfrage);
  }

  @override
  void close() => _innen.close();
}
