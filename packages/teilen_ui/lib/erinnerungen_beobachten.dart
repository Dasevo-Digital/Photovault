import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kern/db/database.dart';

/// Auch ein von einem anderen Gerät übernommener Ausschluss verwirft die
/// bereits geladene Auswahl. Beim Schließen endet der Datenbankhorcher.
mixin ErinnerungenBeobachten<T extends StatefulWidget> on State<T> {
  AppDatabase get erinnerungsDb;
  void erinnerungenNeuLaden();
  late final StreamSubscription<void> _horcher;

  @override
  void initState() {
    super.initState();
    _horcher = erinnerungsDb.erinnerungsAenderungen().skip(1).listen((_) {
      if (mounted) erinnerungenNeuLaden();
    });
  }

  @override
  void dispose() {
    unawaited(_horcher.cancel());
    super.dispose();
  }
}
