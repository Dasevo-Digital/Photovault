import 'dart:async';
import 'dart:typed_data';

import 'package:kern/abgleich/grenzen.dart';
import 'package:shelf/shelf.dart';

/// Ein Budget vor Anmeldung und JSON-Decodierung. Dateiströme behalten ihre
/// eigenen Uploadgrenzen und werden nicht gepuffert.
///
/// **Je Absender (#316).** Mit einer Grenze für alle konnte ein einziges
/// Gerät, das viel auf einmal schickt, allen anderen ein 503 bescheren.
/// [gleichzeitig] gilt jetzt je Absender, [insgesamt] bleibt als Deckel,
/// weil jede dieser Anfragen ihren Körper im Speicher hält.
///
/// **[frist] misst den Fortschritt.** Sie begann früher einmal und galt für
/// den ganzen Körper: Eine langsame Leitung, die stetig lieferte, bekam ein
/// 408. Jetzt zählt die Zeit seit dem letzten Stück. [gesamtfrist] fängt ab,
/// wer absichtlich tröpfelt und seinen Platz so ewig hielte.
Middleware anfragegrenzen({
  int gleichzeitig = 16,
  int insgesamt = 128,
  Duration frist = const Duration(seconds: 20),
  Duration gesamtfrist = const Duration(minutes: 2),
  int jsonBytes = Abgleichsgrenzen.stapelBytes,
  int anmeldungBytes = 16 * 1024,
  String Function(Request)? absender,
}) {
  var aktiv = 0;
  final jeAbsender = <String, int>{};
  Response abweisung(int status) => Response(
    status,
    body: '{"fehler":"pv_anfrage_grenze"}',
    headers: {'content-type': 'application/json', 'connection': 'close'},
  );
  return (inner) => (r) async {
    final pfad = r.url.path;
    final dateistrom =
        (r.method == 'PATCH' &&
            RegExp(r'^api/v1/(umzug/)?hochladen/[^/]+$').hasMatch(pfad)) ||
        (r.method == 'PUT' &&
            (pfad.startsWith('api/v1/dateien/') || pfad == 'api/v1/sofort')) ||
        (r.method == 'POST' &&
            RegExp(r'^api/v1/(teilen|geteilt)/[^/]+/beitrag$').hasMatch(pfad));
    if (!{'POST', 'PUT', 'PATCH', 'DELETE'}.contains(r.method) || dateistrom) {
      return inner(r);
    }
    final klein =
        pfad.startsWith('api/v1/anmelden') ||
        pfad.startsWith('api/v1/web/anmelden') ||
        pfad == 'api/v1/einrichten';
    final grenze = klein ? anmeldungBytes : jsonBytes;
    if ((r.contentLength ?? 0) > grenze) return abweisung(413);
    final wer = absender?.call(r) ?? '';
    if (aktiv >= insgesamt || (jeAbsender[wer] ?? 0) >= gleichzeitig) {
      return abweisung(503);
    }
    aktiv++;
    jeAbsender[wer] = (jeAbsender[wer] ?? 0) + 1;
    StreamSubscription<List<int>>? abo;
    Timer? timer, ganz;
    try {
      final fertig = Completer<Uint8List>();
      final bytes = BytesBuilder(copy: false);
      var anzahl = 0;
      void fehler(int status) {
        if (!fertig.isCompleted) fertig.completeError(_Grenze(status));
      }

      timer = Timer(frist, () => fehler(408));
      ganz = Timer(gesamtfrist, () => fehler(408));
      abo = r.read().listen(
        (teil) {
          if (fertig.isCompleted) return;
          timer?.cancel();
          timer = Timer(frist, () => fehler(408));
          anzahl += teil.length;
          if (anzahl > grenze) {
            fehler(413);
            return;
          }
          bytes.add(teil);
        },
        onError: (Object e, StackTrace st) {
          if (!fertig.isCompleted) fertig.completeError(e, st);
        },
        onDone: () {
          if (!fertig.isCompleted) fertig.complete(bytes.takeBytes());
        },
      );
      final inhalt = await fertig.future;
      timer?.cancel();
      ganz.cancel();
      return await inner(r.change(body: inhalt));
    } on _Grenze catch (e) {
      return abweisung(e.status);
    } finally {
      timer?.cancel();
      ganz?.cancel();
      // Ein bösartiger Stream darf auch das Beenden nicht offenhalten.
      if (abo != null) unawaited(abo.cancel());
      aktiv--;
      final rest = (jeAbsender[wer] ?? 1) - 1;
      if (rest <= 0) {
        jeAbsender.remove(wer);
      } else {
        jeAbsender[wer] = rest;
      }
    }
  };
}

class _Grenze implements Exception {
  const _Grenze(this.status);
  final int status;
}
