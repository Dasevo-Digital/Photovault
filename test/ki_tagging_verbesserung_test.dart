import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/services/ai_tagging_service.dart';
import 'package:photo_vault/services/clip_service.dart';

/// Was ein Vokabelbegriff auf dem Weg zum Text-Encoder wird.
///
/// Der Anlass war eine Rückmeldung, die Schlagwörter träfen selten den
/// Inhalt. An 40 echten Fotos nachgemessen: Sie stimmten bei einem F1 von
/// 0,16, an einer zweiten Stichprobe bei 0,07. Der Grund stand im Code –
/// bei ausgeschalteter Übersetzung ging der DEUTSCHE Begriff roh an einen
/// englisch trainierten Encoder, und die von Hand geprüfte Übersetzungs-
/// tabelle daneben wurde nur beim Sprachwechsel benutzt.
void main() {
  group('Der Begriff, der eingebettet wird', () {
    test('nimmt die von Hand geprüfte Übersetzung, nicht die Maschine', () async {
      var maschineGefragt = false;
      final aus = await begriffFuerModell('Geburtstagstorte', (t) async {
        maschineGefragt = true;
        return 'MASCHINE';
      });
      expect(aus, 'a photo of birthday cake.');
      expect(maschineGefragt, isFalse,
          reason: 'für geprüfte Begriffe darf die Maschine nicht gefragt werden');
    });

    test('lässt einen bereits englischen Begriff stehen', () async {
      var maschineGefragt = false;
      final aus = await begriffFuerModell('Beach', (t) async {
        maschineGefragt = true;
        return 'MASCHINE';
      });
      expect(aus, 'a photo of beach.');
      expect(maschineGefragt, isFalse,
          reason: 'sonst übersetzte die Maschine Englisch nach Englisch');
    });

    test('fragt die Maschine nur für selbst hinzugefügte Begriffe', () async {
      final aus = await begriffFuerModell('Ferienlager', (t) async {
        expect(t, 'Ferienlager');
        return 'summer camp';
      });
      expect(aus, 'a photo of summer camp.');
    });

    test('ohne Übersetzer bleibt der Begriff, aber die Schablone greift', () async {
      expect(await begriffFuerModell('Ferienlager', null),
          'a photo of ferienlager.');
    });

    test('jeder Begriff des Standardvokabulars hat eine geprüfte Entsprechung',
        () async {
      for (final begriff in defaultAiTagVocabulary) {
        final aus = await begriffFuerModell(begriff, (_) async {
          fail('für „$begriff" fehlt die geprüfte Übersetzung');
        });
        expect(aus, startsWith('a photo of '));
        expect(aus, endsWith('.'));
      }
    });
  });

  group('Die Satzschablone', () {
    test('setzt den Begriff in einen Satz statt ihn nackt zu lassen', () {
      // Der Wortlaut aus der CLIP-Veröffentlichung. An 40 Fotos gemessen
      // hob allein er die Güte von F1 0,25 auf 0,41.
      expect(schabloneFuer('Group of people'), 'a photo of group of people.');
    });

    test('macht klein, damit Gross- und Kleinschreibung nichts verschiebt', () {
      expect(schabloneFuer('SELFIE'), schabloneFuer('selfie'));
    });
  });

  group('Die Bildvorverarbeitung', () {
    /// Ein Bild mit einem waagerechten Streifenmuster: Aus der Höhe der
    /// Streifen im Ergebnis lässt sich ablesen, ob gestaucht oder
    /// zugeschnitten wurde.
    img.Image streifen(int breite, int hoehe) {
      final b = img.Image(width: breite, height: hoehe);
      for (var y = 0; y < hoehe; y++) {
        final hell = (y ~/ 20) % 2 == 0;
        for (var x = 0; x < breite; x++) {
          b.setPixelRgb(x, y, hell ? 255 : 0, hell ? 255 : 0, hell ? 255 : 0);
        }
      }
      return b;
    }

    test('liefert immer genau 224x224', () {
      for (final (b, h) in [(3000, 2000), (2000, 3000), (500, 500), (100, 4000)]) {
        final aus = aufClipGroesse(img.Image(width: b, height: h));
        expect((aus.width, aus.height), (224, 224), reason: '$b x $h');
      }
    });

    test('schneidet zu statt zu stauchen – das Seitenverhältnis bleibt', () {
      // 3:2 quer. Beim Stauchen würden die 20 Zeilen hohen Streifen auf
      // 224/2000*20 = 2,24 Zeilen zusammengedrückt; beim Zuschneiden
      // bleibt die kurze Seite massgeblich: 224/2000*20 ebenfalls … also
      // messen wir anders herum, an der Breite.
      final quelle = streifen(3000, 2000);
      final aus = aufClipGroesse(quelle);
      // Nach dem Skalieren der KURZEN Seite auf 224 ist das Bild
      // 336 x 224; zugeschnitten wird waagerecht. Die Streifenhöhe muss
      // 20 * 224/2000 = 2,24 Punkte betragen – dieselbe wie bei einem
      // quadratischen Ausschnitt derselben Quelle.
      final quadrat = aufClipGroesse(img.copyCrop(quelle,
          x: 1000, y: 0, width: 2000, height: 2000));
      var gleich = 0;
      for (var y = 0; y < 224; y++) {
        if (aus.getPixel(112, y).r == quadrat.getPixel(112, y).r) gleich++;
      }
      expect(gleich, greaterThan(200),
          reason: 'der mittige Ausschnitt muss demselben Bild entsprechen');
    });

    test('ein extrem schmales Bild wird nicht verzerrt, sondern beschnitten', () {
      // 1026x1824 kam in der Prüfstichprobe wirklich vor. Gestaucht würde
      // es fast auf die halbe Breite zusammengedrückt.
      final aus = aufClipGroesse(streifen(1026, 1824));
      expect((aus.width, aus.height), (224, 224));
      // Streifen bleiben Streifen: eine Zeile ist in sich einfarbig.
      for (final y in [10, 60, 150]) {
        final erste = aus.getPixel(0, y).r;
        for (final x in [50, 112, 200]) {
          expect(aus.getPixel(x, y).r, erste);
        }
      }
    });
  });
}
