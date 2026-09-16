import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/familienorte.dart';
import 'package:photo_vault/services/verwandtschaftsgrad.dart';

/// Die Einfärbung der Familienkarte.
///
/// Ein Foto kann mehrere Verwandte zeigen. Welche Farbe der Marker
/// bekommt, ist deshalb eine Entscheidung – und die lässt sich am
/// fertigen Bild nicht prüfen, weil dort nur eine Farbe zu sehen ist.
void main() {
  const grade = {
    'mutter': Grad(Gradart.vorfahre, aufwaerts: 1),
    'uropa': Grad(Gradart.vorfahre, aufwaerts: 3),
    'onkel': Grad(Gradart.vorfahrengeschwister, aufwaerts: 2, abwaerts: 1),
    'sohn': Grad(Gradart.nachkomme, abwaerts: 1),
    'neffe': Grad(Gradart.geschwisterkind, aufwaerts: 1, abwaerts: 2),
    'bruder': Grad(Gradart.geschwister, aufwaerts: 1, abwaerts: 1),
    'cousine': Grad(Gradart.cousin, aufwaerts: 2, abwaerts: 2),
    'gattin': Grad(Gradart.partner),
    'schwager': Grad(Gradart.schwager),
  };

  group('gruppeFuer', () {
    test('ordnet jede Richtung ihrer Gruppe zu', () {
      expect(gruppeFuer(grade['mutter']!), Ortsgruppe.vorfahren);
      expect(gruppeFuer(grade['onkel']!), Ortsgruppe.vorfahren,
          reason: 'Geschwister eines Vorfahren gehören nach oben');
      expect(gruppeFuer(grade['sohn']!), Ortsgruppe.nachkommen);
      expect(gruppeFuer(grade['neffe']!), Ortsgruppe.nachkommen);
      expect(gruppeFuer(grade['bruder']!), Ortsgruppe.seitenlinie);
      expect(gruppeFuer(grade['cousine']!), Ortsgruppe.seitenlinie);
      expect(gruppeFuer(grade['gattin']!), Ortsgruppe.angeheiratet);
      expect(gruppeFuer(grade['schwager']!), Ortsgruppe.angeheiratet);
    });
  });

  group('gruppeFuerFoto', () {
    test('die nächste Verwandtschaft gewinnt', () {
      // Ein Foto mit der Urgroßmutter UND dem eigenen Kind ist in erster
      // Linie eines vom eigenen Kind.
      expect(gruppeFuerFoto(['uropa', 'sohn'], grade, fokus: 'ich'),
          Ortsgruppe.nachkommen);
      expect(gruppeFuerFoto(['cousine', 'mutter'], grade, fokus: 'ich'),
          Ortsgruppe.vorfahren);
    });

    test('die Person selbst schlägt alles', () {
      expect(gruppeFuerFoto(['ich', 'sohn'], grade, fokus: 'ich'),
          Ortsgruppe.ich);
    });

    test('Unbekannte auf dem Foto ändern nichts', () {
      expect(gruppeFuerFoto(['fremd', 'mutter'], grade, fokus: 'ich'),
          Ortsgruppe.vorfahren);
    });

    test('ohne Verwandte gibt es keine Gruppe', () {
      // Das Foto gehört dann nicht auf die Familienkarte.
      expect(gruppeFuerFoto(['fremd'], grade, fokus: 'ich'), isNull);
      expect(gruppeFuerFoto([], grade, fokus: 'ich'), isNull);
    });
  });
}
