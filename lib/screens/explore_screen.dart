import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../db/database.dart';
import '../db/rasterzeile.dart';
import '../l10n/app_localizations.dart';
import '../services/rasterstufen.dart';
import '../services/rueckblick.dart';
import '../services/search_filters.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/asset_thumbnail_tile.dart';
import '../widgets/mini_location_map.dart'
    show Kachelschicht, Kartenstil, buildMapAttribution;
import '../widgets/pin_dialogs.dart';
import 'aktivitaet_detail_screen.dart';
import 'aktivitaeten_screen.dart';
import 'album_detail_screen.dart';
import 'albums_screen.dart';
import 'asset_viewer_screen.dart';
import 'map_screen.dart';
import 'people_screen.dart';
import 'reise_detail_screen.dart';
import 'reisen_screen.dart';
import 'person_detail_screen.dart';
import 'timeline_screen.dart';
import 'trash_screen.dart';
import '../widgets/profilbild.dart';
import '../widgets/stromhalter.dart';
import '../services/laendernamen.dart';
import '../widgets/aktivitaetsart_anzeige.dart';

/// Wie viele Kacheln ein Streifen höchstens zeigt.
///
/// Vorher waren das feste Zahlen (zehn Personen, acht Alben, zwölf
/// Fotos) – jetzt sind es Obergrenzen, und wie viele davon wirklich
/// stehen, rechnet [streifenAnzahl] aus der Fensterbreite. Ein Streifen
/// bleibt eine Vorschau; für alles gibt es „Alle anzeigen".
const _hoechstensPersonen = 24;
const _hoechstensKacheln = 16;
const _hoechstensFotos = 24;
const _previewLocationMarkerCount = 60;
const _previewLocationGroupCount = 12;

/// Übersichts-/Entdecken-Tab: bündelt kompakte Vorschauen aus den
/// spezialisierten Bereichen (Personen, Karte, Alben, Timeline) auf einer
/// Seite, statt dass man dafür einzeln durch die jeweiligen Tabs navigieren
/// muss. Jede Sektion verlinkt über "Alle anzeigen" auf die volle Ansicht.
/// Breite einer Karte in den Querlisten – zugleich die Dekodiergroesse
/// des Vorschaubilds darin.
const double _kartenKante = 120;

class ExploreScreen extends StatelessWidget {
  final LibraryState library;
  const ExploreScreen({super.key, required this.library});

  @override
  Widget build(BuildContext context) {
    // **Kein `ListView`.** Die Abschnitte hier sind unterschiedlich hoch
    // (ein Streifen 96 Punkte, die Kartenvorschau 200, die Papierkorbzeile
    // 72), und eine faule Liste schaetzt ihre Gesamthoehe aus dem, was
    // gerade ausgelegt ist. Wer bis zum Papierkorb scrollt, hat oben nur
    // noch die kurzen Abschnitte im Baum – und die Schaetzung bricht ein:
    //
    // ```
    // unten angekommen   1288 von max 1288
    // ein Zug zurueck     250 von max  352   <- 950 Punkte auf einmal
    // zwei Zuege spaeter    0 von max 2810   <- ganz oben
    // ```
    //
    // Die Rollposition wird auf das eingebrochene Maximum gekappt, und
    // wenn die echte Hoehe zurueckkommt, ist sie weg. Von aussen sieht es
    // aus, als springe die Seite von selbst nach oben.
    //
    // Dreizehn Abschnitte auf einmal auszulegen kostet nichts: Die Menge
    // steckt in den Vorschaubildern, und die liegen in den waagerechten
    // Listen darin, die faul bleiben. Nebenbei bauen die Abschnitte sich
    // nicht mehr staendig ab und neu auf – jeder Wiederaufbau hatte seine
    // Abfrage von vorn begonnen.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MemoriesSection(library: library),
          _Streifenabschnitt<PersonData>(
            titel: AppTexte.of(context).erkundenPersonen,
            onAlleAnzeigen: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PeopleScreen(library: library),
            )),
            hoehe: 96,
            // 64 Punkte Profilbild, der Rest ist Abstand und Name.
            textanteil: 32,
            kachelbreite: 76,
            hoechstens: _hoechstensPersonen,
            strom: (_) => library.db.watchPeople(),
            kachel: (context, gezeigt, index) =>
                _Personenkachel(library: library, person: gezeigt[index]),
          ),
          _OrteAbschnitt(library: library),
          // Reisen stehen direkt unter den Orten: Sie sind dieselbe Frage,
          // eine Ebene größer – nicht „wo war dieses Bild", sondern „wo war
          // ich, und wie lange".
          _Streifenabschnitt<ReisenData>(
            titel: AppTexte.of(context).erkundenReisen,
            onAlleAnzeigen: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ReisenScreen(library: library),
            )),
            hoehe: 92,
            // Rand, Symbol und Abstand sind fest; Name und Jahr sind Schrift.
            textanteil: 36,
            kachelbreite: 190,
            hoechstens: _hoechstensKacheln,
            strom: (_) => library.db.watchReisen(),
            kachel: (context, gezeigt, index) =>
                _Reisekachel(library: library, reise: gezeigt[index]),
          ),
          // Und die Aktivitäten direkt darunter, aus demselben Grund, aus
          // dem die Reisen unter den Orten stehen: dieselbe Frage, eine
          // Ebene kleiner. Eine Reise ist der Urlaub, eine Aktivität der
          // Tag darin – wer das eine sucht, hat das andere im Sinn.
          _Streifenabschnitt<AktivitaetenData>(
            titel: AppTexte.of(context).erkundenAktivitaeten,
            onAlleAnzeigen: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AktivitaetenScreen(library: library),
            )),
            hoehe: 92,
            // Rand, Symbol und Abstand sind fest; Name und Jahr sind Schrift.
            textanteil: 36,
            kachelbreite: 190,
            hoechstens: _hoechstensKacheln,
            strom: (_) => library.db.watchAktivitaeten(),
            kachel: (context, gezeigt, index) => _Aktivitaetskachel(library: library, k: gezeigt[index]),
          ),
          _Streifenabschnitt<AlbumData>(
            titel: AppTexte.of(context).erkundenLetzteAlben,
            onAlleAnzeigen: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AlbumsScreen(library: library),
            )),
            hoehe: 150,
            // Die Vorschau bekommt, was übrig bleibt; darunter steht der Name.
            textanteil: 26,
            kachelbreite: 120,
            hoechstens: _hoechstensKacheln,
            // Bereits nach createdAt absteigend sortiert -> die ersten N
            // sind die zuletzt angelegten Alben.
            strom: (_) => library.db.watchAlbums(),
            kachel: (context, gezeigt, index) =>
                _AlbumPreviewTile(library: library, album: gezeigt[index]),
          ),
          // Der einzige Abschnitt, der auch leer stehen bleibt: Eine
          // Bibliothek ganz ohne Fotos ist eine Auskunft, kein Zufall.
          _Streifenabschnitt<AssetData>(
            titel: AppTexte.of(context).erkundenLetzteFotos,
            onAlleAnzeigen: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => TimelineScreen(library: library),
            )),
            hoehe: 140,
            // Reine Bildkacheln, keine Schrift.
            textanteil: 0,
            kachelbreite: 140,
            abstand: 8,
            hoechstens: _hoechstensFotos,
            // Die einzige Abfrage, die die Zahl selbst begrenzen kann –
            // und deshalb die einzige, die beim Ziehen am Fenster neu
            // abonniert werden muss.
            anzahlImStrom: true,
            strom: (anzahl) => library.db.watchTimeline(limit: anzahl),
            leerHinweis: AppTexte.of(context).erkundenKeineFotos,
            kachel: (context, gezeigt, index) => _Fotokachel(
                library: library, alle: gezeigt, asset: gezeigt[index]),
          ),
          _Papierkorbzeile(library: library),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback onShowAll;
  const _SectionHeader({required this.title, required this.onShowAll});

  @override
  Widget build(BuildContext context) {
    // Beide beweglich: Bei grosser Systemschrift brauchten Überschrift und
    // Knopf zusammen 193 Punkte mehr, als die Zeile breit war – „Zuletzt
    // hinzugefügte Alben" und „Alle anzeigen" sind beide lang. Der Titel
    // gibt zuerst nach, der Knopf erst danach; abgeschnitten wird keiner
    // von beiden, sie kürzen mit Auslassungspunkten.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium),
        ),
        Flexible(
          child: TextButton(
            onPressed: onShowAll,
            child: Text(AppTexte.of(context).allgAlleAnzeigen,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  final double height;
  const _EmptyHint({required this.text, required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
    );
  }
}

/// Ein Abschnitt der Übersicht: Überschrift, ein waagerechter Streifen,
/// und der Abstand zum nächsten.
///
/// **Zwei Dinge, die er anders macht als die Streifen vorher.**
///
/// 1. **Leer heisst weg.** Ein Abschnitt ohne Inhalt zeigte einen Satz
///    („Noch keine Alben vorhanden") unter einer Überschrift mit einem
///    „Alle anzeigen"-Knopf, der in eine leere Liste führte. Fünf solche
///    Abschnitte untereinander sind eine Seite, die von sich selbst
///    handelt. Wer einen Satz braucht, bekommt ihn über [leerHinweis] –
///    die letzten Fotos etwa, denn eine Bibliothek ganz ohne Fotos ist
///    eine Auskunft und kein Zufall.
/// 2. **So viele, wie hineinpassen.** Die Zahl der Kacheln stand fest –
///    zehn Personen, acht Alben –, gleich ob das Fenster 900 oder 2000
///    Punkte breit war. Jetzt rechnet [streifenAnzahl] sie aus.
class _Streifenabschnitt<T> extends StatefulWidget {
  final String titel;
  final VoidCallback onAlleAnzeigen;

  /// Die Höhe des Streifens und die Masse einer Kachel darin.
  final double hoehe;

  /// Wie viel von [hoehe] Schrift ist – dieser Teil, und nur dieser,
  /// wächst mit der Systemschrift.
  ///
  /// **Warum nicht die ganze Höhe.** Die Bilder in den Kacheln haben
  /// feste Kanten (ein Profilbild misst 64 Punkte, eine Albumvorschau
  /// 120); sie mitzuskalieren gäbe nur Leerraum. Die Zeile darunter
  /// dagegen wird bei 1,6-facher Schrift genau 1,6-mal so hoch, und
  /// vorher lief sie über: gemessene 1,00 Punkte bei den Personen, weil
  /// die 96 an einer Schriftgrösse festgemacht waren, die der Anwender
  /// verstellen kann.
  final double textanteil;
  final double kachelbreite;
  final double abstand;

  /// Wie viele Kacheln höchstens – ein Streifen ist eine Vorschau.
  final int hoechstens;

  /// Der Datenstrom. Bekommt die Zahl, falls die Abfrage sie selbst
  /// begrenzen kann (siehe [AppDatabase.watchTimeline]).
  final Stream<List<T>> Function(int anzahl) strom;

  /// Ob der Strom von der Zahl abhängt. Wenn nicht, wird beim Ziehen am
  /// Fenster nicht neu abonniert – jedes Abo führt die Abfrage von vorn
  /// aus (siehe [Stromhalter]).
  final bool anzahlImStrom;

  final Widget Function(BuildContext, List<T> gezeigt, int index) kachel;

  /// Steht der Abschnitt auch leer da? Dann mit diesem Satz.
  final String? leerHinweis;

  const _Streifenabschnitt({
    super.key,
    required this.titel,
    required this.onAlleAnzeigen,
    required this.hoehe,
    required this.textanteil,
    required this.kachelbreite,
    required this.strom,
    required this.kachel,
    required this.hoechstens,
    this.abstand = 12,
    this.anzahlImStrom = false,
    this.leerHinweis,
  });

  @override
  State<_Streifenabschnitt<T>> createState() => _StreifenabschnittState<T>();
}

class _StreifenabschnittState<T> extends State<_Streifenabschnitt<T>> {
  final _strom = Stromhalter<List<T>>();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hoehe = widget.hoehe -
            widget.textanteil +
            MediaQuery.textScalerOf(context).scale(widget.textanteil);
        final anzahl = streifenAnzahl(
          constraints.maxWidth,
          kachelbreite: widget.kachelbreite,
          abstand: widget.abstand,
          hoechstens: widget.hoechstens,
        );
        return StreamBuilder<List<T>>(
          stream: _strom.hole(widget.anzahlImStrom ? anzahl : true,
              () => widget.strom(anzahl)),
          builder: (context, schnappschuss) {
            final alle = schnappschuss.data ?? const [];
            if (alle.isEmpty && widget.leerHinweis == null) {
              // Noch nichts geladen ist nicht dasselbe wie leer – aber der
              // Unterschied dauert einen Wimpernschlag, und ein Abschnitt,
              // der dabei kurz aufblitzt, waere unruhiger als einer, der
              // gleich steht.
              return const SizedBox.shrink();
            }
            final gezeigt = alle.take(anzahl).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionHeader(
                    title: widget.titel, onShowAll: widget.onAlleAnzeigen),
                const SizedBox(height: 8),
                SizedBox(
                  height: hoehe,
                  child: gezeigt.isEmpty
                      ? _EmptyHint(text: widget.leerHinweis!, height: hoehe)
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: gezeigt.length,
                          separatorBuilder: (_, __) =>
                              SizedBox(width: widget.abstand),
                          itemBuilder: (context, index) =>
                              widget.kachel(context, gezeigt, index),
                        ),
                ),
                const SizedBox(height: 28),
              ],
            );
          },
        );
      },
    );
  }
}

/// Ein Gesicht mit Namen darunter.
class _Personenkachel extends StatelessWidget {
  final LibraryState library;
  final PersonData person;
  const _Personenkachel({required this.library, required this.person});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(32),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PersonDetailScreen(library: library, person: person),
      )),
      child: SizedBox(
        width: 76,
        child: Column(
          children: [
            Profilbild(
              datei: person.coverFaceCropPath == null
                  ? null
                  : library.paths.absolute(person.coverFaceCropPath!),
              radius: 32,
              hintergrund: Colors.grey.shade800,
              symbolgroesse: 28,
            ),
            const SizedBox(height: 6),
            Text(
              person.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ein Vorschaubild, das ins Vollbild führt.
class _Fotokachel extends StatelessWidget {
  final LibraryState library;

  /// Die ganze Reihe – im Vollbild blättert man durch sie weiter.
  final List<AssetData> alle;
  final AssetData asset;
  const _Fotokachel(
      {required this.library, required this.alle, required this.asset});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: AssetThumbnailTile(
          asset: Rasterzeile.aus(asset),
          paths: library.paths,
          onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
            builder: (_) => AssetViewerScreen(
              assets: alle,
              initialIndex: alle.indexOf(asset),
              paths: library.paths,
              db: library.db,
              library: library,
              onToggleFavorite: (a) =>
                  library.db.setFavorite(a.id, !a.isFavorite),
              onDelete: (a) => library.db.moveToTrash([a.id]),
              onLock: (a) async {
                if (await ensureVaultUnlocked(context, library)) {
                  await library.lockAsset(a);
                }
              },
            ),
          )),
        ),
      ),
    );
  }
}

/// Der Abschnitt „Orte": die Karte und darunter die Orte als Kacheln.
///
/// Als eigener Abschnitt und nicht über [_Streifenabschnitt], weil er
/// zwei Dinge zeigt und das erste davon kein Streifen ist. Die Regel ist
/// dieselbe: Ohne eine einzige verortete Aufnahme steht hier nichts –
/// eine leere Karte unter der Überschrift „Orte" ist keine Auskunft.
class _OrteAbschnitt extends StatefulWidget {
  final LibraryState library;
  const _OrteAbschnitt({required this.library});

  @override
  State<_OrteAbschnitt> createState() => _OrteAbschnittState();
}

class _OrteAbschnittState extends State<_OrteAbschnitt> {
  late final Future<bool> _hatOrte =
      widget.library.db.countAssetsWithLocation().then((n) => n > 0);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hatOrte,
      builder: (context, schnappschuss) {
        if (schnappschuss.data != true) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(
              title: AppTexte.of(context).erkundenOrte,
              onShowAll: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MapScreen(library: widget.library),
              )),
            ),
            const SizedBox(height: 8),
            _LocationsPreview(library: widget.library),
            const SizedBox(height: 12),
            _LocationGroupsStrip(library: widget.library),
            const SizedBox(height: 28),
          ],
        );
      },
    );
  }
}

class _LocationsPreview extends StatefulWidget {
  final LibraryState library;
  const _LocationsPreview({required this.library});

  @override
  State<_LocationsPreview> createState() => _LocationsPreviewState();
}

class _LocationsPreviewState extends State<_LocationsPreview> {
  // Einmalig in initState geladen statt inline in build(): ein Future direkt
  // als `future:`-Argument eines FutureBuilder in build() zu erzeugen würde
  // bei jedem Rebuild (z.B. durch den übergeordneten Consumer<LibraryState>)
  // ein NEUES Future anstoßen – der FutureBuilder würde jedes Mal kurz in
  // den Ladezustand zurückfallen und die Abfrage unnötig wiederholen.
  late final Future<List<AssetData>> _locatedFuture = widget.library.db.assetsWithLocation();

  ll.LatLng _averageCenter(List<AssetData> assets) {
    var latSum = 0.0, lngSum = 0.0;
    for (final a in assets) {
      latSum += a.latitude!;
      lngSum += a.longitude!;
    }
    return ll.LatLng(latSum / assets.length, lngSum / assets.length);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AssetData>>(
      future: _locatedFuture,
      builder: (context, snapshot) {
        final located = snapshot.data ?? [];
        return InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => MapScreen(library: widget.library),
          )),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: SizedBox(
              height: 160,
              child: located.isEmpty
                  ? Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: Text(
                        AppTexte.of(context).ohneOrtLeer,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    )
                  // IgnorePointer: die Vorschau soll nur als Ganzes zur
                  // vollen Kartenansicht führen, nicht selbst pannbar/zoombar
                  // sein (das würde mit dem Tippen zum Öffnen kollidieren).
                  : IgnorePointer(
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: _averageCenter(located),
                          initialZoom: 4,
                          // Sonst zoomt die Karte ueber die
                          // vorhandenen Kacheln hinaus ins Leere –
                          // siehe Kartenstil.hoechsteAnzeigeStufe.
                          maxZoom: Kartenstil.dunkel.hoechsteAnzeigeStufe.toDouble(),
                        ),
                        children: [
                          const Kachelschicht(),
                          buildMapAttribution(context),
                          MarkerLayer(
                            markers: [
                              for (final a in located.take(_previewLocationMarkerCount))
                                Marker(
                                  point: ll.LatLng(a.latitude!, a.longitude!),
                                  width: 10,
                                  height: 10,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Theme.of(context).colorScheme.primary,
                                      border: Border.all(color: Colors.white, width: 1.5),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// Ein Ort (Stadt + optional Land) mit einem repräsentativen Foto (das
/// zeitlich aktuellste dieses Orts) und der Anzahl zugehöriger Fotos.
class _LocationGroup {
  final String city;
  final String? country;
  final AssetData cover;
  int count = 1;
  _LocationGroup({required this.city, required this.country, required this.cover});
}

/// Zeigt die per Umkehr-Geokodierung erkannten Orte (siehe ReverseGeocoder)
/// als Bildvorschau-Kacheln, zusätzlich zur Kartenvorschau oben – eine Zeile
/// je Ort, sortiert nach dem zeitlich aktuellsten Foto an diesem Ort.
class _LocationGroupsStrip extends StatefulWidget {
  final LibraryState library;
  const _LocationGroupsStrip({required this.library});

  @override
  State<_LocationGroupsStrip> createState() => _LocationGroupsStripState();
}

class _LocationGroupsStripState extends State<_LocationGroupsStrip> {
  late final Future<List<AssetData>> _resolvedFuture = widget.library.db.assetsWithResolvedLocation();

  /// [assets] kommt bereits absteigend nach Aufnahmedatum sortiert aus der
  /// Datenbank – das erste Vorkommen je Ort ist damit automatisch das
  /// aktuellste Foto und wird als Vorschaubild verwendet.
  List<_LocationGroup> _groupByPlace(List<AssetData> assets) {
    final groups = <String, _LocationGroup>{};
    for (final a in assets) {
      final key = '${a.locationCity}|${a.locationCountry ?? ''}';
      final existing = groups[key];
      if (existing == null) {
        groups[key] = _LocationGroup(city: a.locationCity!, country: a.locationCountry, cover: a);
      } else {
        existing.count++;
      }
    }
    return groups.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: FutureBuilder<List<AssetData>>(
        future: _resolvedFuture,
        builder: (context, snapshot) {
          final assets = snapshot.data ?? [];
          if (assets.isEmpty) {
            return _EmptyHint(
              text: AppTexte.of(context).erkundenKeineOrte,
              height: 150,
            );
          }
          final groups = _groupByPlace(assets).take(_previewLocationGroupCount).toList();
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: groups.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) =>
                _LocationGroupTile(library: widget.library, group: groups[index]),
          );
        },
      ),
    );
  }
}

class _LocationGroupTile extends StatelessWidget {
  final LibraryState library;
  final _LocationGroup group;
  const _LocationGroupTile({required this.library, required this.group});

  Future<void> _openPlace(BuildContext context) async {
    final results = await library.db.searchAssets(
      SearchFilters(locationCity: group.city, locationCountry: group.country),
    );
    if (results.isEmpty || !context.mounted) return;
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => AssetViewerScreen(
        assets: results,
        initialIndex: 0,
        paths: library.paths,
        db: library.db,
        library: library,
        onToggleFavorite: (a) => library.db.setFavorite(a.id, !a.isFavorite),
        onDelete: (a) => library.db.moveToTrash([a.id]),
        onLock: (a) async {
          if (await ensureVaultUnlocked(context, library)) {
            await library.lockAsset(a);
          }
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final thumbPath = group.cover.thumbnailRelativePath;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () => _openPlace(context),
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: thumbPath != null
                      ? Image.file(
                          library.paths.absolute(thumbPath),
                          fit: BoxFit.cover,
                          cacheWidth: (_kartenKante *
                                  MediaQuery.devicePixelRatioOf(context))
                              .round(),
                          errorBuilder: (_, __, ___) => const Icon(Icons.location_city_outlined, size: 32),
                        )
                      : const Center(child: Icon(Icons.location_city_outlined, size: 32)),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              group.city,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            if (group.country != null)
              Text(
                landAnzeige(group.country,
                    Localizations.localeOf(context).languageCode),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

class _Reisekachel extends StatelessWidget {
  final LibraryState library;
  final ReisenData reise;
  const _Reisekachel({required this.library, required this.reise});

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    final jahr = reise.von.year == reise.bis.year
        ? '${reise.von.year}'
        : '${reise.von.year}–${reise.bis.year}';
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ReiseDetailScreen(library: library, reise: reise),
      )),
      child: Container(
        width: 190,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: farben.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.luggage, color: farben.primary, size: 20),
            const SizedBox(height: AppSpacing.xs),
            Text(reise.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(jahr,
                style: TextStyle(fontSize: 12, color: farben.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _Aktivitaetskachel extends StatelessWidget {
  final LibraryState library;
  final AktivitaetenData k;
  const _Aktivitaetskachel({required this.library, required this.k});

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AktivitaetDetailScreen(library: library, aktivitaet: k),
      )),
      child: Container(
        width: 190,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: farben.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Das Symbol der Art und nicht ein Sammelzeichen: Ob da eine
            // Wanderung oder eine Radtour stand, ist das erste, was man
            // wissen will.
            Icon(symbolFuerKennung(k.art), color: farben.primary, size: 20),
            const SizedBox(height: AppSpacing.xs),
            Text(k.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(nameFuerKennung(t, k.art),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: farben.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _AlbumPreviewTile extends StatefulWidget {
  final LibraryState library;
  final AlbumData album;
  const _AlbumPreviewTile({required this.library, required this.album});

  @override
  State<_AlbumPreviewTile> createState() => _AlbumPreviewTileState();
}

class _AlbumPreviewTileState extends State<_AlbumPreviewTile> {
  // Kein eigenes Cover-Feld gepflegt – als Vorschau dient stattdessen das
  // zuletzt hinzugefügte Foto des Albums. Diese Kachel wird pro Album einmal
  // in einer horizontalen Liste erzeugt – ein inline in build() erzeugtes
  // Future würde hier bei jedem Rebuild ERNEUT pro sichtbarem Album
  // abgefragt (statt einmal beim Erzeugen der Kachel).
  late final Future<List<AssetData>> _assetsFuture = widget.library.db.assetsInAlbumOnce(widget.album.id);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            AlbumDetailScreen(library: widget.library, albumId: widget.album.id, albumName: widget.album.name),
      )),
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: FutureBuilder<List<AssetData>>(
                  future: _assetsFuture,
                  builder: (context, snapshot) {
                    final assets = snapshot.data ?? [];
                    final cover = assets.isEmpty
                        ? null
                        : assets.reduce((a, b) => a.fileCreatedAt.isAfter(b.fileCreatedAt) ? a : b);
                    final thumbPath = cover?.thumbnailRelativePath;
                    return Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: thumbPath != null
                          ? Image.file(
                              widget.library.paths.absolute(thumbPath),
                              fit: BoxFit.cover,
                              cacheWidth: (_kartenKante *
                                      MediaQuery.devicePixelRatioOf(context))
                                  .round(),
                              errorBuilder: (_, __, ___) => const Icon(Icons.photo_album_outlined, size: 32),
                            )
                          : const Center(child: Icon(Icons.photo_album_outlined, size: 32)),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoriesSection extends StatefulWidget {
  final LibraryState library;
  const _MemoriesSection({required this.library});

  @override
  State<_MemoriesSection> createState() => _MemoriesSectionState();
}

class _MemoriesSectionState extends State<_MemoriesSection> {
  static final _heute = DateTime.now();

  /// Beide Fragen werden gestellt, gezeigt wird die engere, die etwas
  /// hat (siehe [waehleRueckblick]). Der Monat kostet dieselbe Abfrage
  /// noch einmal – gemessen 31 ms – und erspart dem Abschnitt an 104
  /// Tagen im Jahr das wortlose Verschwinden.
  late final Future<Rueckblick<AssetData>> _rueckblick = _laden();

  Future<Rueckblick<AssetData>> _laden() async {
    final db = widget.library.db;
    final amTag = await db.assetsOnThisDay(_heute);
    final imMonat =
        amTag.isEmpty ? await db.assetsInDiesemMonat(_heute) : <AssetData>[];
    return waehleRueckblick(
      amTag: amTag,
      imMonat: imMonat,
      wann: (a) => a.fileCreatedAt,
      heute: _heute,
    );
  }

  void _openMemory(BuildContext context, List<AssetData> assets, AssetData asset) {
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => AssetViewerScreen(
        assets: assets,
        initialIndex: assets.indexOf(asset),
        paths: widget.library.paths,
        db: widget.library.db,
        library: widget.library,
        onToggleFavorite: (a) => widget.library.db.setFavorite(a.id, !a.isFavorite),
        onDelete: (a) => widget.library.db.moveToTrash([a.id]),
        onLock: (a) async {
          if (await ensureVaultUnlocked(context, widget.library)) {
            await widget.library.lockAsset(a);
          }
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return FutureBuilder<Rueckblick<AssetData>>(
      future: _rueckblick,
      builder: (context, snapshot) {
        final rueckblick = snapshot.data;
        if (rueckblick == null ||
            rueckblick.art == Rueckblickart.keiner) {
          return const SizedBox.shrink();
        }
        final letzte = rueckblick.gruppen.last.jahreHer;
        final monat = DateFormat.MMMM(Localizations.localeOf(context)
                .toString())
            .format(_heute);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.erkundenErinnerungen,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final gruppe in rueckblick.gruppen) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  // Der Monatsrueckblick sagt ausdruecklich Monat: „vor
                  // 13 Jahren" ueber einem Bild vom 3. September waere
                  // am 12. September eine Behauptung ueber den Tag, die
                  // niemand aufgestellt hat.
                  rueckblick.art == Rueckblickart.tag
                      ? t.erkundenVorJahren(gruppe.jahreHer)
                      : t.erkundenImMonatVorJahren(monat, gruppe.jahreHer),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              SizedBox(
                height: 140,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: gruppe.dinge.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final asset = gruppe.dinge[index];
                    return SizedBox(
                      width: 140,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: AssetThumbnailTile(
                          asset: Rasterzeile.aus(asset),
                          paths: widget.library.paths,
                          onTap: () =>
                              _openMemory(context, gruppe.dinge, asset),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (gruppe.jahreHer != letzte) const SizedBox(height: 16),
            ],
          ],
        );
      },
    );
  }
}

/// Der Weg in den Papierkorb, mit der Zahl gleich daneben.
///
/// Bis Fassung 2.2.1 gab es ihn nur über die Einstellungen – und davor
/// zwei Jahre lang gar nicht (siehe `jeder_bildschirm_erreichbar_test.dart`).
/// Er bleibt dort auch stehen: Wer die automatische Leerung einstellt,
/// will von dort hineinsehen können.
class _Papierkorbzeile extends StatefulWidget {
  final LibraryState library;
  const _Papierkorbzeile({required this.library});

  @override
  State<_Papierkorbzeile> createState() => _PapierkorbzeileState();
}

class _PapierkorbzeileState extends State<_Papierkorbzeile> {
  final _strom = Stromhalter<Papierkorbumfang>();

  @override
  Widget build(BuildContext context) {
    final library = widget.library;
    final t = AppTexte.of(context);
    // Nur die Zahl, nicht die Aufnahmen: 0,3 statt 13,0 ms je Abo, siehe
    // [AppDatabase.watchPapierkorbUmfang].
    return StreamBuilder<Papierkorbumfang>(
      stream: _strom.hole(true, () => library.db.watchPapierkorbUmfang()),
      builder: (context, schnappschuss) {
        final anzahl = schnappschuss.data?.anzahl ?? 0;
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(t.papierkorbTitel),
            subtitle: Text(anzahl == 0
                ? t.papierkorbLeer
                : t.papierkorbAnzahl(anzahl)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => TrashScreen(library: library),
            )),
          ),
        );
      },
    );
  }
}
