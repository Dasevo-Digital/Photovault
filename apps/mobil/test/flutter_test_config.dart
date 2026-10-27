import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Für alle Tests der Handy-App: Ein Tipp, der nicht dort ankommt, wo der
/// Sucher hinzeigt, ist ein Fehler und keine Warnung im Protokoll (#238).
/// Zwei solche Tipps liefen hier monatelang mit, weil der Eintrag
/// zufällig unter dem Text lag.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  WidgetController.hitTestWarningShouldBeFatal = true;
  await testMain();
}
