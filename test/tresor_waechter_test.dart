import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/tresor_waechter.dart';

void main() {
  group('sperrtBei', () {
    test('das Fenster ist weg – dann zu', () {
      expect(sperrtBei(AppLifecycleState.hidden), isTrue);
      expect(sperrtBei(AppLifecycleState.paused), isTrue);
      expect(sperrtBei(AppLifecycleState.detached), isTrue);
    });

    test('nur den Fokus verloren heisst nicht weggegangen', () {
      // `inactive` kommt bei jedem Systemdialog, jedem Blick in ein
      // anderes Fenster. Hier zu sperren hiesse, nach jedem Wechsel den
      // PIN zu verlangen – ein Schutz, den man dann abschaltet.
      expect(sperrtBei(AppLifecycleState.inactive), isFalse);
      expect(sperrtBei(AppLifecycleState.resumed), isFalse);
    });
  });

  group('Tresorwaechter', () {
    test('sperrt beim Verbergen, nicht beim blossen Fokusverlust', () {
      var gesperrt = 0;
      final waechter = Tresorwaechter(() async => gesperrt++);

      waechter.aufZustand(AppLifecycleState.inactive);
      expect(gesperrt, 0);

      waechter.aufZustand(AppLifecycleState.hidden);
      expect(gesperrt, 1);

      waechter.aufZustand(AppLifecycleState.resumed);
      expect(gesperrt, 1);

      waechter.aufZustand(AppLifecycleState.paused);
      expect(gesperrt, 2);
    });

    test('schweige nimmt den Horcher zurück, auch mehrfach', () {
      final waechter = Tresorwaechter(() async {});
      waechter.schweige();
      waechter.schweige();
    });
  });
}
