import 'dart:io';
import 'package:photo_vault_server/src/gastpruefung.dart';

Future<void> main(List<String> argumente) async {
  gastProzessEinrichten();
  if (await File(argumente[1]).readAsString().catchError((_) => '') ==
      'prozessbaum') {
    await Process.start('/bin/sleep', ['57']);
    await Future<void>.delayed(const Duration(minutes: 1));
    return;
  }
  exitCode = await gastPruefen(argumente.skip(1).toList());
}
