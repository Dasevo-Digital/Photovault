import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/tastenkuerzel.dart';
import 'einstellungen/bibliotheken.dart';
import 'einstellungen/einstellungsstand.dart';
import 'einstellungen/erscheinungsbild.dart';
import 'einstellungen/gefahrenzone.dart';
import 'einstellungen/gesperrter_ordner.dart';
import 'einstellungen/hintergrund.dart';
import 'einstellungen/karte.dart';
import 'einstellungen/modelle.dart';
import 'einstellungen/papierkorb.dart';
import 'einstellungen/sicherung.dart';
import 'einstellungen/speicherort.dart';
import 'einstellungen/sprache.dart';
import 'einstellungen/standortdaten.dart';
import 'einstellungen/ueber.dart';
import 'einstellungen/ueberwachter_ordner.dart';
import 'einstellungen/vokabular.dart';

class SettingsScreen extends StatefulWidget {
  final LibraryState library;
  const SettingsScreen({super.key, required this.library});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// Die Einstellungen: eine Suche und darunter die Gruppen.
///
/// Jede Gruppe steht in einer eigenen Datei unter einstellungen/, ihr
/// gemeinsamer Zustand in [Einstellungsstand] (#41). Hier bleibt, was den
/// Bildschirm selbst ausmacht: die Suche, die Reihenfolge der Gruppen und
/// ihre Karten.
class _SettingsScreenState extends State<SettingsScreen> {
  late final Einstellungsstand _stand;

  /// Sucheingabe über den Gruppen. Filtert nach Titel UND Beschreibung –
  /// wer „Passphrase" eingibt, soll den gesperrten Ordner auch dann finden,
  /// wenn das Wort nur in der Beschreibung steht.
  final TextEditingController _suche = TextEditingController();

  @override
  void initState() {
    super.initState();
    _stand = Einstellungsstand(
      widget.library,
      kontext: () => context,
      aktiv: () => mounted,
    )..addListener(_neu);
  }

  /// Der Stand hat sich geändert – wie früher ein setState hier.
  void _neu() => setState(() {});

  @override
  void dispose() {
    _stand
      ..removeListener(_neu)
      ..dispose();
    _suche.dispose();
    super.dispose();
  }

  /// Alle Gruppen in ihrer Reihenfolge. Die Beschreibung ist nicht nur
  /// Zierde: Sie ist das, wonach die Suche oben sucht, und der einzige
  /// Hinweis darauf, was in einer zugeklappten Gruppe steckt.
  List<_Gruppe> _gruppen(AppTexte t) => [
    _Gruppe(
      icon: Icons.contrast_outlined,
      titel: t.einstAbschnittErscheinungsbild,
      beschreibung: t.einstBeschrErscheinungsbild,
      inhalt: () => [ErscheinungsbildGruppe(_stand)],
    ),
    _Gruppe(
      icon: Icons.translate_outlined,
      titel: t.spracheTitel,
      beschreibung: t.einstBeschrSprache,
      inhalt: () => [SpracheGruppe(_stand)],
    ),
    _Gruppe(
      icon: Icons.folder_special_outlined,
      titel: t.einstUeberwachtTitel,
      beschreibung: t.einstBeschrUeberwacht,
      inhalt: () => [UeberwachterOrdnerGruppe(_stand)],
    ),
    _Gruppe(
      icon: Icons.photo_library_outlined,
      titel: t.einstBibListe,
      beschreibung: t.einstBeschrBibliotheken,
      inhalt: () => [BibliothekenGruppe(_stand)],
    ),
    _Gruppe(
      icon: Icons.sd_storage_outlined,
      titel: t.einstSpeicherortTitel,
      beschreibung: t.einstBeschrSpeicherort,
      inhalt: () => [SpeicherortGruppe(_stand)],
    ),
    _Gruppe(
      icon: Icons.memory_outlined,
      titel: t.einstAbschnittModelle,
      beschreibung: t.einstBeschrModelle,
      inhalt: () => [ModelleGruppe(_stand)],
    ),
    _Gruppe(
      icon: Icons.autorenew_outlined,
      titel: t.einstAbschnittHintergrund,
      beschreibung: t.einstBeschrHintergrund,
      inhalt: () => [HintergrundGruppe(_stand)],
    ),
    _Gruppe(
      icon: Icons.sell_outlined,
      titel: t.einstAbschnittVokabular,
      beschreibung: t.einstBeschrVokabular,
      inhalt: () => [VokabularGruppe(_stand)],
    ),
    _Gruppe(
      icon: Icons.public_outlined,
      titel: t.einstAbschnittStandortdaten,
      beschreibung: t.einstBeschrStandortdaten,
      inhalt: () => [StandortdatenGruppe(_stand)],
    ),
    _Gruppe(
      icon: Icons.map_outlined,
      titel: t.einstAbschnittKarte,
      beschreibung: t.einstBeschrKarte,
      inhalt: () => [KarteGruppe(_stand)],
    ),
    _Gruppe(
      icon: Icons.lock_outline,
      titel: t.einstAbschnittGesperrterOrdner,
      beschreibung: t.einstBeschrGesperrt,
      inhalt: () => [GesperrterOrdnerGruppe(_stand)],
    ),
    _Gruppe(
      icon: Icons.key_outlined,
      titel: t.einstBackupVerschluesselungTitel,
      beschreibung: t.einstBeschrBackupSchluessel,
      inhalt: () => [SicherungsschluesselGruppe(_stand)],
    ),
    _Gruppe(
      icon: Icons.cloud_upload_outlined,
      titel: t.einstAbschnittManuellesBackup,
      beschreibung: t.einstBeschrBackupManuell,
      inhalt: () => [SicherungVonHandGruppe(_stand)],
    ),
    _Gruppe(
      icon: Icons.schedule_outlined,
      titel: t.einstAbschnittAutoBackup,
      beschreibung: t.einstBeschrBackupAuto,
      inhalt: () => [AutomatischeSicherungGruppe(_stand)],
    ),
    _Gruppe(
      icon: Icons.delete_sweep_outlined,
      titel: t.einstAbschnittPapierkorb,
      beschreibung: t.einstBeschrPapierkorb,
      inhalt: () => [PapierkorbGruppe(_stand)],
    ),
    _Gruppe(
      icon: Icons.warning_amber_outlined,
      titel: t.einstAbschnittGefahrenzone,
      beschreibung: t.einstBeschrGefahr,
      inhalt: () => [GefahrenzoneGruppe(_stand)],
    ),
    // Die Tafel gab es schon; erreichbar war sie nur über „?" – eine
    // Taste, die nirgends stand. Hier ist sie auffindbar, und die
    // Suche oben findet sie mit (Befund der 19. Prüfrunde).
    _Gruppe(
      icon: Icons.keyboard_outlined,
      titel: t.kuerzelTitel,
      beschreibung: t.einstBeschrKuerzel,
      inhalt: _gruppeKuerzel,
    ),
    _Gruppe(
      icon: Icons.info_outline,
      titel: t.einstUeberTitel,
      beschreibung: t.einstBeschrUeber,
      inhalt: () => [UeberGruppe(_stand)],
    ),
  ];

  List<Widget> _gruppeKuerzel() => const [
    Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Tastenkuerzeltafel(),
    ),
  ];

  @override
  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final suche = _suche.text.trim().toLowerCase();
    final alle = _gruppen(t);
    final sichtbar = suche.isEmpty
        ? alle
        : [
            for (final g in alle)
              if (g.titel.toLowerCase().contains(suche) ||
                  g.beschreibung.toLowerCase().contains(suche))
                g,
          ];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        SearchBar(
          controller: _suche,
          hintText: t.einstSuche,
          leading: const Icon(Icons.search),
          trailing: [
            if (suche.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: t.allgAbbrechen,
                onPressed: () => setState(_suche.clear),
              ),
          ],
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (sichtbar.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxxl),
            child: Text(t.einstNichtsGefunden, textAlign: TextAlign.center),
          ),
        for (final gruppe in sichtbar)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _GruppenKarte(
              // Der Schlüssel enthält, ob gesucht wird: Bei einem Treffer
              // soll die Gruppe offen erscheinen, und das entscheidet sich
              // beim Neuaufbau. Ohne diesen Teil im Schlüssel behielte sie
              // ihren vorherigen Zustand bei.
              key: ValueKey('${gruppe.titel}|${suche.isNotEmpty}'),
              gruppe: gruppe,
              anfangsOffen: suche.isNotEmpty,
            ),
          ),
      ],
    );
  }
}

/// Eine zusammenklappbare Gruppe von Einstellungen.
///
/// Der Bildschirm hatte sechzehn Abschnitte hintereinander – über 900
/// Zeilen Oberfläche, durch die man scrollen musste, um an die
/// Gefahrenzone ganz unten zu kommen. Als Gruppen ist zugeklappt der
/// Normalfall: Man sieht sechzehn Zeilen und öffnet die eine, die man
/// braucht.
class _Gruppe {
  final IconData icon;
  final String titel;
  final String beschreibung;

  /// Als Funktion, nicht als fertige Liste: Der Inhalt einer zugeklappten
  /// Gruppe soll gar nicht erst gebaut werden. Bei sechzehn Gruppen mit
  /// StreamBuildern, Dateigrössen-Abfragen und Modell-Listen ist das der
  /// Unterschied zwischen „alles immer" und „nur das Geöffnete".
  final List<Widget> Function() inhalt;

  const _Gruppe({
    required this.icon,
    required this.titel,
    required this.beschreibung,
    required this.inhalt,
  });
}

class _GruppenKarte extends StatelessWidget {
  final _Gruppe gruppe;
  final bool anfangsOffen;

  const _GruppenKarte({
    super.key,
    required this.gruppe,
    required this.anfangsOffen,
  });

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    final rand = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      side: BorderSide(color: farben.outlineVariant),
    );
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: farben.surface,
      shape: rand,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        // Ohne diese beiden hat ExpansionTile im geöffneten Zustand eigene
        // Trennlinien oben und unten, die quer zur Kartenkontur laufen.
        shape: const Border(),
        collapsedShape: const Border(),
        initiallyExpanded: anfangsOffen,
        leading: Icon(gruppe.icon, color: farben.primary),
        title: Text(
          gruppe.titel,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: farben.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          gruppe.beschreibung,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: gruppe.inhalt(),
      ),
    );
  }
}
