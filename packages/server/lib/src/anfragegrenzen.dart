import 'dart:async';
import 'dart:typed_data';

import 'package:kern/abgleich/grenzen.dart';
import 'package:shelf/shelf.dart';

/// Ein gemeinsames Budget vor Anmeldung und JSON-Decodierung. Dateiströme
/// behalten ihre eigenen Uploadgrenzen und werden nicht gepuffert.
Middleware anfragegrenzen({
  int gleichzeitig = 16,
  Duration frist = const Duration(seconds: 20),
  int jsonBytes = Abgleichsgrenzen.stapelBytes,
  int anmeldungBytes = 16 * 1024,
}) {
  var aktiv = 0;
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
        (r.method == 'PUT' && pfad.startsWith('api/v1/dateien/')) ||
        (r.method == 'POST' &&
            RegExp(r'^api/v1/teilen/[^/]+/beitrag$').hasMatch(pfad));
    if (!{'POST', 'PUT', 'PATCH', 'DELETE'}.contains(r.method) || dateistrom) {
      return inner(r);
    }
    final klein =
        pfad.startsWith('api/v1/anmelden') ||
        pfad.startsWith('api/v1/web/anmelden') ||
        pfad == 'api/v1/einrichten';
    final grenze = klein ? anmeldungBytes : jsonBytes;
    if ((r.contentLength ?? 0) > grenze) return abweisung(413);
    if (aktiv >= gleichzeitig) return abweisung(503);
    aktiv++;
    StreamSubscription<List<int>>? abo;
    Timer? timer;
    try {
      final fertig = Completer<Uint8List>();
      final bytes = BytesBuilder(copy: false);
      var anzahl = 0;
      void fehler(int status) {
        if (!fertig.isCompleted) fertig.completeError(_Grenze(status));
      }

      timer = Timer(frist, () => fehler(408));
      abo = r.read().listen(
        (teil) {
          if (fertig.isCompleted) return;
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
      timer.cancel();
      return await inner(r.change(body: inhalt));
    } on _Grenze catch (e) {
      return abweisung(e.status);
    } finally {
      timer?.cancel();
      // Ein bösartiger Stream darf auch das Beenden nicht offenhalten.
      if (abo != null) unawaited(abo.cancel());
      aktiv--;
    }
  };
}

class _Grenze implements Exception {
  const _Grenze(this.status);
  final int status;
}
