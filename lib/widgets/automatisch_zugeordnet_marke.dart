import 'package:flutter/material.dart';

import 'package:kern/db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/meldungsdienst.dart';
import 'tippfaenger.dart';

/// Ob [gesicht] die Kennzeichnung trägt: von der Wiedererkennung ohne
/// Rückfrage einer Person zugeordnet und noch von niemandem bestätigt.
bool automatischZugeordnet(FaceData gesicht) =>
    gesicht.automatischZugeordnet &&
    gesicht.personId != null &&
    !gesicht.isIgnored;

/// Bestätigt die automatische Zuordnung von [gesichtIds] zu [personId]:
/// dieselbe Person noch einmal, von Hand zugeordnet –
/// [AppDatabase.assignFacesToPerson] nimmt dabei die Kennzeichnung weg.
/// Als Befehl, damit es verbunden auch der Server und die anderen Geräte
/// erfahren.
Future<void> bestaetigeZuordnung(
  BuildContext context,
  AppDatabase db,
  List<String> gesichtIds,
  String personId,
) async {
  final text = AppTexte.of(context).gesichtAutomatischBestaetigt;
  await db.fuehreAus(GesichterZuordnen(gesichtIds, personId));
  melde.erfolg(text);
}

/// Das kleine Zeichen an einem Gesicht, das die Wiedererkennung ohne
/// Rückfrage zugeordnet hat (PER-074).
///
/// Der Schalter „Sichere Vorschläge automatisch übernehmen“ verspricht,
/// dass solche Zuordnungen gekennzeichnet werden, damit man sie nachsehen
/// kann. Die Kennzeichnung stand bisher nur in der Datenbank.
///
/// Ein Tipp auf das Zeichen bestätigt die Zuordnung ([beiBestaetigen]).
/// Es nimmt den Tipp über einen [Tippfaenger] entgegen – im Vollbild
/// liegt es über demselben `PhotoView` wie die Gesichtsrahmen – und muss
/// deshalb **neben** anderen Tippflächen im Stapel liegen, nicht in ihnen:
/// Sonst bekämen beide den Tipp.
class AutomatischZugeordnetMarke extends StatelessWidget {
  const AutomatischZugeordnetMarke({
    super.key,
    this.beiBestaetigen,
    this.groesse = 18,
  });

  /// `null`: nur anzeigen, nicht bestätigen.
  final VoidCallback? beiBestaetigen;

  final double groesse;

  /// Bernstein: hebt sich vom Grün der benannten und vom Orange der
  /// unbenannten Rahmen ab.
  static const farbe = Colors.amberAccent;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Tooltip(
      message: beiBestaetigen == null
          ? t.gesichtAutomatisch
          : t.gesichtAutomatischBestaetigen,
      child: Tippfaenger(
        beiTipp: beiBestaetigen,
        beiMenue: null,
        child: MouseRegion(
          cursor: beiBestaetigen == null
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          child: Container(
            width: groesse,
            height: groesse,
            decoration: BoxDecoration(
              color: Colors.black87,
              shape: BoxShape.circle,
              border: Border.all(color: farbe, width: groesse / 12),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.auto_awesome, size: groesse * 0.6, color: farbe),
          ),
        ),
      ),
    );
  }
}
