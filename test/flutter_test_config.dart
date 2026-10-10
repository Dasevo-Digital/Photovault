import 'dart:async';

import 'package:photo_vault/widgets/mini_location_map.dart';

/// Gilt für jeden Test unter test/.
///
/// Die Kartenschicht bekommt einen Kachel-Host, den flutter_map nicht als
/// OpenStreetMap erkennt – sonst druckt es bei jedem Aufbau seinen Hinweis
/// zur Nutzungsrichtlinie in die Ausgabe (#42, siehe [osmHostFuerTest]).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  osmHostFuerTest = 'osm.kacheln.test';
  await testMain();
}
