// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppTexteEn extends AppTexte {
  AppTexteEn([String locale = 'en']) : super(locale);

  @override
  String get allgAbbrechen => 'Cancel';

  @override
  String get allgSpeichern => 'Save';

  @override
  String get allgSchliessen => 'Close';

  @override
  String get allgErstellen => 'Create';

  @override
  String get allgStarten => 'Start';

  @override
  String get allgName => 'Name';

  @override
  String get allgMehr => 'More';

  @override
  String get allgAlleAnzeigen => 'Show all';

  @override
  String get navTimeline => 'Timeline';

  @override
  String get navErkunden => 'Explore';

  @override
  String get navKalender => 'Calendar';

  @override
  String get navReisen => 'Trips';

  @override
  String get kuerzelReisenOhne =>
      'Trips have no shortcut – all ten digits were taken, and renumbering would have moved every shortcut you already know.';

  @override
  String get navKarte => 'Map';

  @override
  String get navSuche => 'Search';

  @override
  String get navPersonen => 'People';

  @override
  String get navAlben => 'Albums';

  @override
  String get navWerkzeuge => 'Tools';

  @override
  String get navEinstellungen => 'Settings';

  @override
  String get importierenTooltip => 'Import photos and videos';

  @override
  String geoeffneteBibliothek(String name) {
    return 'Open library: $name';
  }

  @override
  String get restaurierungWirdVorbereitet => 'Preparing restoration …';

  @override
  String restaurierungWartend(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl photos queued for restoration',
      one: '1 photo queued for restoration',
    );
    return '$_temp0';
  }

  @override
  String analyseLaeuft(
      String stufe, int nummer, int gesamt, String fortschritt) {
    return 'Computing $stufe (step $nummer of $gesamt$fortschritt)';
  }

  @override
  String get kuerzelTitel => 'Keyboard shortcuts';

  @override
  String get kuerzelRaster => 'Grid (timeline, calendar, album, search)';

  @override
  String get kuerzelUmschaltKlick => 'Shift-click';

  @override
  String get kuerzelStrgKlick => 'Ctrl/⌘-click';

  @override
  String get kuerzelUmschaltPfeil => 'Shift + arrow';

  @override
  String get kuerzelBereichWaehlen => 'Add everything up to here';

  @override
  String get kuerzelEinzelnWaehlen => 'Toggle a single tile';

  @override
  String get kuerzelRahmenBewegen => 'Move the frame through the grid';

  @override
  String get kuerzelAuswahlZiehen => 'Extend the selection along';

  @override
  String get kuerzelFarbmarkeSetzen => 'Set colour label';

  @override
  String get kuerzelAuswahlLeeren => 'Clear the selection';

  @override
  String get kuerzelFotoOeffnen => 'Open the photo';

  @override
  String get kuerzelWirktAuf =>
      'The keys act on the selection. If there is none, they act on the tile the frame is on.';

  @override
  String get einstBeschrKuerzel => 'Every keyboard shortcut at a glance';

  @override
  String get kuerzelNavigation => 'Navigation';

  @override
  String get kuerzelVollbild => 'Full screen';

  @override
  String get kuerzelSichtung => 'Culling mode';

  @override
  String get kuerzelBereicheWechseln => 'Switch between the main sections';

  @override
  String get kuerzelUebersichtOeffnen => 'Open this list';

  @override
  String get kuerzelVorherigesNaechstes => 'Previous / next photo';

  @override
  String get kuerzelLeertaste => 'Space';

  @override
  String get kuerzelNaechstesFoto => 'Next photo';

  @override
  String get kuerzelBewertungSetzen => 'Set star rating';

  @override
  String get kuerzelFavoritUmschalten => 'Toggle favourite';

  @override
  String get kuerzelPapierkorbMitBestaetigung => 'Move to trash (asks first)';

  @override
  String get kuerzelSofortAblehnen => 'Reject and move on (no confirmation)';

  @override
  String get kuerzelZoomWischen => '⌘/Ctrl + swipe';

  @override
  String get kuerzelZoomImBild =>
      'Zoom into and out of the photo (works with a Magic Mouse too)';

  @override
  String get timelineLeer => 'No photos in this library yet.';

  @override
  String loeschenTitel(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: 'Delete $anzahl photos?',
      one: 'Delete photo?',
    );
    return '$_temp0';
  }

  @override
  String loeschenHinweis(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: 'They will be moved to the trash.',
      one: 'It will be moved to the trash.',
    );
    return '$_temp0';
  }

  @override
  String get albumNeu => 'New album';

  @override
  String get albumName => 'Album name';

  @override
  String get albenLeer => 'No albums yet.';

  @override
  String get albenIntelligente => 'Smart albums';

  @override
  String get albenGewoehnliche => 'Albums';

  @override
  String get albumIntelligentLoeschen => 'Delete smart album';

  @override
  String albumIntelligentLoeschenFrage(String name) {
    return 'Remove “$name”? The photos stay; only the saved search disappears.';
  }

  @override
  String get albenIntelligentWoher =>
      'A smart album is a saved search: it does not collect photos, it shows whatever currently matches. You create one in Search, via the bookmark next to the search field.';

  @override
  String get erkundenPersonen => 'People';

  @override
  String get erkundenOrte => 'Places';

  @override
  String get erkundenLetzteAlben => 'Recently added albums';

  @override
  String get erkundenLetzteFotos => 'Recently added photos';

  @override
  String get erkundenErinnerungen => 'Memories';

  @override
  String get ohneOrtLeer => 'No photos with a known location yet.';

  @override
  String get karteTitel => 'Map';

  @override
  String get karteAnsicht => 'Map view';

  @override
  String get karteTexturNachweis =>
      'Earth/star textures: Solar System Scope (CC BY 4.0)';

  @override
  String get kalenderLeer => 'Not enough photos for a year overview yet.';

  @override
  String get kalenderJahrLeer => 'No photos in this year.';

  @override
  String kalenderAnzahlFotos(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl photos/videos',
      one: '$anzahl photo/video',
    );
    return '$_temp0';
  }

  @override
  String get sucheSpeichernTitel => 'Save search';

  @override
  String get sucheModellFehlt =>
      'Context search needs the image search model. You can download it in Settings under “AI models”.';

  @override
  String get sucheModellLaedt => 'Loading the image search model …';

  @override
  String get sucheOhneEmbeddings =>
      'No photo has been analysed for AI image search yet. The run is under Tools → Tasks (“CLIP embeddings”).';

  @override
  String get sucheOhneTexterkennung =>
      'No text has been recognised on any photo yet. The run is under Tools → Tasks (“Recognise text (OCR)”).';

  @override
  String sucheModellUnbrauchbar(String datei) {
    return 'The model $datei is on disk but cannot be opened. Download it again under Settings - AI models; search and AI tags need it.';
  }

  @override
  String sucheFehlgeschlagen(String fehler) {
    return 'Search failed: $fehler';
  }

  @override
  String get suchePlatzhalterKontext =>
      'e.g. “sunset over the sea”, “dog in the snow” …';

  @override
  String get suchePlatzhalterDateiname => 'File name …';

  @override
  String get suchePlatzhalterBeschreibung => 'Description …';

  @override
  String get suchePlatzhalterText => 'Text in the photo …';

  @override
  String get suchePlatzhalterBildunterschrift => 'e.g. “dog”, “sunset” …';

  @override
  String get werkzStaubText =>
      'Examines a sample of one camera\'s shots for a dark speck that keeps sitting in the same place.';

  @override
  String get staubTitel => 'Find sensor dust';

  @override
  String get staubErklaerung =>
      'Sensor dust sits in the same spot on every shot from the same camera. That is exactly how it is recognised: the app examines a sample spread across the whole period and reports only what keeps appearing in the same place. A single dark speck can be anything.';

  @override
  String get staubKeineKameras => 'No camera is recorded in this library.';

  @override
  String get staubSuchen => 'Search';

  @override
  String staubFortschritt(int erledigt, int gesamt) {
    return '$erledigt of $gesamt shots examined';
  }

  @override
  String staubNichtsGefunden(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: 'No sensor dust was found on $anzahl examined shots.',
      one: 'No sensor dust was found on the examined shot.',
    );
    return '$_temp0';
  }

  @override
  String staubGefunden(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl spots that keep appearing',
      one: '1 spot that keeps appearing',
    );
    return '$_temp0';
  }

  @override
  String staubAufWievielen(int treffer, int gesamt) {
    return 'on $treffer of $gesamt examined shots';
  }

  @override
  String staubUebersprungen(int anzahl, int gesamt) {
    return '$anzahl of $gesamt photos could not be read and were skipped.';
  }

  @override
  String get staubImEditorOeffnen =>
      'Open an affected shot in the image editor';

  @override
  String get allgKamera => 'Camera';

  @override
  String get sucheSatzVerwerfen => 'Undo interpretation and search literally';

  @override
  String get sucheOptionen => 'Search options';

  @override
  String get sucheAusloesen => 'Search';

  @override
  String get sucheAnleitung =>
      'Type something to search for, or pick search options.';

  @override
  String get sucheKeineTreffer => 'Nothing found.';

  @override
  String get viewerInfo => 'Info';

  @override
  String get viewerTeilen => 'Share';

  @override
  String get viewerExportieren => 'Export';

  @override
  String get viewerEntwickeln => 'Develop';

  @override
  String get viewerBearbeiten => 'Edit';

  @override
  String get viewerZuschneiden => 'Trim';

  @override
  String get viewerDiaschauStarten => 'Start slideshow';

  @override
  String get viewerDiaschauStoppen => 'Stop slideshow';

  @override
  String get viewerFavoritSetzen => 'Mark as favourite (F)';

  @override
  String get viewerFavoritEntfernen => 'Remove from favourites (F)';

  @override
  String get viewerInGesperrtenOrdner =>
      'Move to the locked folder (encrypted)';

  @override
  String get viewerInPapierkorb => 'Move to trash (⌫)';

  @override
  String get viewerVorherigesFoto => 'Previous photo';

  @override
  String get viewerNaechstesFoto => 'Next photo';

  @override
  String get viewerInTimelineZeigen => 'Show this photo in the timeline';

  @override
  String get viewerAehnlicheZeigen => 'Show similar photos';

  @override
  String get viewerMetadatenBearbeiten => 'Edit metadata';

  @override
  String get viewerGesichterBearbeiten => 'Edit faces';

  @override
  String get viewerGesichterZeigen => 'Show faces';

  @override
  String get viewerGesichterVerbergen => 'Hide faces';

  @override
  String get viewerKeineGesichter => 'No face detected in this photo.';

  @override
  String get viewerGesichtBenennen => 'Name this face';

  @override
  String get viewerEntwicklungAnwenden => 'Paste develop settings';

  @override
  String get viewerEntwicklungAnwendenLang =>
      'Paste the copied develop settings onto this photo';

  @override
  String get viewerFokusPeaking => 'Focus peaking (highlight sharp edges)';

  @override
  String get viewerGesichtUnscharf => 'Even the sharpest face is soft';

  @override
  String get viewerTextZeigen => 'Highlight recognised text';

  @override
  String get viewerTextVerbergen => 'Hide text highlighting';

  @override
  String get viewerKeinText => 'No text was recognised in this photo.';

  @override
  String get viewerTextNochNicht =>
      'No text areas stored for this photo yet – a text recognition run will add them.';

  @override
  String viewerZeileKopiert(String text) {
    return '“$text” copied';
  }

  @override
  String get viewerFlachesSchwenken => 'Pan flat instead of on a sphere';

  @override
  String get viewerFlacheVorschau => 'Flat preview instead of 360° view';

  @override
  String get viewerExportZielordner => 'Choose a folder to export to';

  @override
  String viewerExportiert(String dateien) {
    return 'Exported: $dateien';
  }

  @override
  String viewerExportFehlgeschlagen(String fehler) {
    return 'Export failed: $fehler';
  }

  @override
  String viewerTeilenFehlgeschlagen(String fehler) {
    return 'Sharing failed: $fehler';
  }

  @override
  String get personenTab => 'People';

  @override
  String get personenUnbenannteTab => 'Unnamed faces';

  @override
  String get personenLeer =>
      'No people yet. Switch to the “Unnamed faces” tab, pick a few faces and assign them to a new person.';

  @override
  String get personenLangeDruecken => 'press and hold: merge';

  @override
  String get personenKeineUnbenannten =>
      'No unnamed faces (left). New ones appear here automatically as you import more photos or run another face scan. You can also mark individual ones yourself: open a photo, right-click → “Edit faces”, then use “Add face manually” at the top right.';

  @override
  String get personenOhneGesichtsmodell =>
      'Without a face-detection model Photo Vault cannot find any faces.';

  @override
  String personenNochNichtDurchsucht(int offen) {
    String _temp0 = intl.Intl.pluralLogic(
      offen,
      locale: localeName,
      other: '$offen photos have not been scanned for faces yet.',
      one: 'One photo has not been scanned for faces yet.',
    );
    return '$_temp0 Until that is done, nothing can appear here.';
  }

  @override
  String get personenJetztSuchen => 'Scan for faces now';

  @override
  String get personenSucheLaeuft =>
      'The face scan is running. The first results will appear here once it is done.';

  @override
  String get personenSchwellenHinweis =>
      'The similarity threshold lives in Tools → Face recognition.';

  @override
  String get personenDoppelklickHinweis =>
      'Double-click a face to open the whole photo and check it.';

  @override
  String get personenAutomatischGruppieren => 'Group automatically';

  @override
  String get personenAehnlicheAuswaehlen => 'Also select similar';

  @override
  String get personenAehnlicheAbwaehlen => 'Deselect similar';

  @override
  String personenZuordnen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: 'Assign $anzahl faces',
      one: 'Assign face',
    );
    return '$_temp0';
  }

  @override
  String get personenModellFehlt =>
      'Finding similar faces needs the SFace model (see Settings → Models).';

  @override
  String personenKeineAehnlichen(String schwelle) {
    return 'No faces found above the $schwelle similarity threshold.';
  }

  @override
  String get personenZuWenigeFuerClustering =>
      'Not enough unnamed faces with an embedding to group them.';

  @override
  String get personenKeineGruppen => 'No similar groups found.';

  @override
  String get personenDauertTitel => 'This may take a while';

  @override
  String personenDauertText(int anzahl) {
    return 'Found $anzahl unnamed faces. Grouping compares every face with every other one, which takes a while at this many (the app stays usable meanwhile). Start anyway?';
  }

  @override
  String personenZusammenfuehrenMit(String name) {
    return 'Merge “$name” into …';
  }

  @override
  String get personenZusammenfuehrenTitel => 'Confirm merge';

  @override
  String personenZusammenfuehrenText(String quelle, String ziel) {
    return 'Every photo of “$quelle” will be assigned to “$ziel”. “$quelle” is then deleted. This cannot be undone.';
  }

  @override
  String get personenZusammenfuehren => 'Merge';

  @override
  String get spracheTitel => 'Language';

  @override
  String get spracheSystem => 'System language';

  @override
  String get spracheDeutsch => 'Deutsch';

  @override
  String get spracheEnglisch => 'English';

  @override
  String get spracheHinweis =>
      'Affects the interface only. Your albums, tags and people\'s names stay as they are.';

  @override
  String get spracheVokabularTitel => 'Translate the tag vocabulary too?';

  @override
  String spracheVokabularText(int bekannt, int gesamt) {
    return '$bekannt of the $gesamt terms come from the vocabulary shipped with the app and can be translated reliably. Tags you have already assigned come along; nothing is lost.';
  }

  @override
  String spracheVokabularSelbstAngelegt(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl terms you added yourself stay unchanged.',
      one: 'One term you added yourself stays unchanged.',
      zero: '',
    );
    return '$_temp0';
  }

  @override
  String get spracheVokabularUebersetzen => 'Translate';

  @override
  String get spracheVokabularBehalten => 'Leave unchanged';

  @override
  String spracheVokabularFertig(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl terms translated.',
      one: 'One term translated.',
    );
    return '$_temp0';
  }

  @override
  String get erkundenKeineOrte =>
      'No places resolved yet (see Tools → Places).';

  @override
  String get erkundenKeineFotos => 'No photos imported yet.';

  @override
  String get karteKeineOrteLang =>
      'No photos with a known location yet.\n\nLocations come from a photo\'s GPS data during import, if it has any. You can also set one by hand in a photo\'s info panel (full screen → ⓘ).';

  @override
  String einstOrdnerNichtGeoeffnet(String pfad) {
    return 'Could not open the folder: $pfad';
  }

  @override
  String einstBibWechselnTitel(String name) {
    return 'Switch to “$name”?';
  }

  @override
  String get einstBibWechselnText =>
      'The app closes afterwards and opens the chosen library on the next start.\n\nNo photos are moved or deleted – both libraries stay exactly where they are.';

  @override
  String get einstBibGewechselt =>
      'The library has been switched. Nothing was moved. The app is closing now – please open it again.';

  @override
  String get einstBibHinzufuegenAuswahl =>
      'Pick the folder of an existing library – or an empty folder for a new one. Nothing is moved.';

  @override
  String get einstBibBestehendHinzugefuegt => 'Existing library added.';

  @override
  String get einstBibLeerHinzugefuegt =>
      'Empty folder added – switching to it creates a new, empty library.';

  @override
  String einstBibEntfernenTitel(String name) {
    return 'Remove “$name” from the list?';
  }

  @override
  String get einstBibEntfernenText =>
      'The library only disappears from this list. Photos, database and folder stay untouched, and you can add it back at any time.';

  @override
  String get einstBibNichtEntfernbar => 'This entry cannot be removed.';

  @override
  String get einstBibListe => 'Libraries';

  @override
  String get einstBibHinzufuegen => 'Add library…';

  @override
  String get einstBibAusListeEntfernen =>
      'Remove from the list (deletes no photos)';

  @override
  String get einstBibNichtGefunden =>
      'Folder not found – is the drive connected?';

  @override
  String get einstBibWechselHinweis =>
      'Switching only changes which library opens – no photos are moved. To move the current library somewhere else, use “Change location” further down.';

  @override
  String get einstSpeicherortTitel => 'Location of the active library';

  @override
  String get einstSpeicherortWaehlen =>
      'Photos, videos, thumbnails and the database move into this folder. Pick a folder that already exists (create it in Finder first if needed).';

  @override
  String get einstSpeicherortZuruecksetzenTitel => 'Reset the location?';

  @override
  String get einstSpeicherortZuruecksetzenText =>
      'The library moves back into the standard app support folder. The app closes afterwards – please open it again.';

  @override
  String get einstSpeicherortZuruecksetzenLaeuft => 'Resetting the location …';

  @override
  String get einstSpeicherortGeaendert =>
      'The location has changed. The app is closing now – please open it again so it loads the library from its new place.';

  @override
  String get einstImFinderAnzeigen => 'Show in Finder';

  @override
  String get einstAendern => 'Change…';

  @override
  String get einstZuruecksetzen => 'Reset';

  @override
  String get einstWirdBerechnet => 'calculating …';

  @override
  String get einstUeberwachtTitel => 'Watched folder';

  @override
  String get einstUeberwachtKeiner => 'No folder set up';

  @override
  String get einstUeberwachtErklaerung =>
      'Anything that turns up in a chosen folder is taken into the library by itself – every five minutes and on every start.';

  @override
  String get einstUeberwachtAktiv =>
      'Checked every five minutes. The files stay where they are.';

  @override
  String get einstUeberwachtWaehlen => 'Choose folder…';

  @override
  String get einstUeberwachtAndererWaehlen => 'Choose another folder…';

  @override
  String get einstUeberwachtBeenden => 'Stop watching';

  @override
  String get einstUeberwachtAuswahl =>
      'Choose a folder to keep an eye on for new photos. The files stay there; they are only added to the library as well.';

  @override
  String einstUeberwachtUebernommen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: 'Took $anzahl new photos from the folder.',
      one: 'Took 1 new photo from the folder.',
    );
    return '$_temp0';
  }

  @override
  String get einstKiHinweis =>
      'As in digiKam, every AI feature runs offline on this machine. The model files are not bundled with the app but downloaded on demand from official open-source sources – once, after which everything works offline.';

  @override
  String get einstAutoAnalyseTitel =>
      'Run AI analysis automatically after importing';

  @override
  String get einstAutoAnalyseText =>
      'Importing only files the photos away, which keeps it fast. Faces, text recognition, image search and descriptions follow in the background. Switched off, you can start them by hand under Tools at any time.';

  @override
  String get einstNurErkennung =>
      'Detection only (recognition still needs the SFace model)';

  @override
  String get einstAufgabenTitel => 'Task overview';

  @override
  String get einstAufgabenText =>
      'Every analysis with the number of photos still waiting, each one startable on its own';

  @override
  String get einstModellLoeschen => 'Delete model';

  @override
  String einstModellNichtGeladen(String beschreibung) {
    return '$beschreibung\n\nThe model this needs is not downloaded yet.';
  }

  @override
  String get einstVokabularText =>
      'Terms the image search model (CLIP) applies automatically to newly imported photos. Changes here only affect future photos – to apply them to the existing library, see Tools → “Compute AI tags” → “All photos”.';

  @override
  String get einstBegriffHinzufuegenFeld => 'Add a term …';

  @override
  String get einstBegriffHinzufuegen => 'Add term';

  @override
  String get einstOrteText =>
      'Turns a photo\'s GPS position into country, state or province and city – entirely locally, via the nearest known city (GeoNames data), without asking an online map service. Needed for the country, state and city filters in the search options.';

  @override
  String get einstGeoTitel => 'GeoNames – cities, countries, states';

  @override
  String einstGeoText(String lizenz) {
    return 'Cities from 1000 inhabitants worldwide (~10 MB). Licence: $lizenz.';
  }

  @override
  String get einstGeoLoeschen => 'Delete the GeoNames data';

  @override
  String get einstGesperrtText =>
      'Encrypts private photos with AES-256 – real encryption, not just a display filter – and hides them everywhere else (timeline, search, albums, people, map, backup). Without the PIN there is no way back.';

  @override
  String get einstGesperrtEntsperrt =>
      'PIN set up – already unlocked for this session.';

  @override
  String get einstGesperrtOeffnen => 'Open';

  @override
  String get einstPinAendern => 'Change PIN';

  @override
  String get einstGesperrtAufloesenText =>
      'Every photo in the locked folder is decrypted and becomes visible again everywhere (timeline, search, albums, people, map, backup). This cannot be undone.';

  @override
  String get einstBackupVerschluesselungTitel => 'Backup encryption';

  @override
  String get einstBackupVerschluesselungText =>
      'Lets you encrypt manual and automatic backups with AES-256. Its own passphrase, separate from the locked folder\'s PIN – a backup often ends up elsewhere and has to be decryptable without this machine.';

  @override
  String get einstBackupEntsperrt =>
      'Set up – already unlocked for this session.';

  @override
  String get einstBackupGesperrt =>
      'Set up – you will be asked at the next backup.';

  @override
  String get einstBackupAendern => 'Change';

  @override
  String get einstBackupNieGesichert => 'Never backed up.';

  @override
  String get einstBackupVerschluesseln => 'Encrypt backup';

  @override
  String get einstBackupPassphraseAbfrage =>
      'Asks for the backup passphrase above when needed.';

  @override
  String get einstBackupZielWaehlen =>
      'Choose a backup destination (e.g. your Dropbox or Google Drive folder)';

  @override
  String get einstBackupOrdnerWaehlen =>
      'Choose the backup folder (the one containing “PhotoVault-Backup” or “originals”)';

  @override
  String get einstBackupEntschluesselnTitel => 'Turn off backup encryption?';

  @override
  String get einstBackupEntschluesselnText =>
      'New backups will no longer be encrypted. Encrypted backups already at the destination stay as they are and remain decryptable only with the previous passphrase.';

  @override
  String get einstBackupLaeuft => 'Automatic backup running …';

  @override
  String get einstBackupKeineNeuen =>
      'No new files – refreshing the database snapshot.';

  @override
  String get einstBackupZielHinweis =>
      'Point this at your local Dropbox or Google Drive folder, for instance – that provider\'s desktop app then uploads the files to the cloud for you.';

  @override
  String get einstBackupAutoHinweis =>
      'Runs only while the app is open (there is no background service) – it checks at start-up and every 30 minutes afterwards whether the interval has elapsed. Always encrypted, and alongside the original files it saves a snapshot of the whole database (faces, places, tags, albums, favourites, …) so the complete state can be restored after data loss. It never deletes anything at the destination – local deletions are deliberately not mirrored.';

  @override
  String get einstBackupZuerstZiel => 'Choose a destination folder first.';

  @override
  String get einstBackupKeinOrdner => 'No folder chosen.';

  @override
  String get einstBackupAutoZielWaehlen =>
      'Choose the destination for automatic backups';

  @override
  String get einstWaehlen => 'Choose…';

  @override
  String get einstStuendlich => 'Hourly';

  @override
  String get einstTaeglich => 'Daily';

  @override
  String get einstWoechentlich => 'Weekly';

  @override
  String get einstBackupGrenzeText =>
      'Caps how much each run writes to the destination. Worth setting for cloud folders: otherwise the upload falls behind for days. The rest follows at the next interval.';

  @override
  String get einstNieAusgefuehrt => 'Never run.';

  @override
  String get einstBackupPassphraseGesperrt =>
      'The backup passphrase still needs unlocking for this session before the automatic backup can run – via “Sync now”, for instance.';

  @override
  String get einstPapierkorbText =>
      'Permanently deletes photos and videos once the chosen period has passed since they went to the trash – irreversibly, including from the locked folder\'s PIN-protected trash. Off by default.';

  @override
  String get einstPapierkorbAus => 'Trash expiry is switched off by default.';

  @override
  String get einstResetText =>
      'Irreversibly deletes ALL photos, videos and the entire database of this library, then starts over with an empty one. Downloaded AI models and geo data are kept, so nothing needs downloading again.';

  @override
  String get einstResetTitel => 'Reset the database';

  @override
  String get einstResetKurz =>
      'Deletes all media and metadata – cannot be undone.';

  @override
  String get einstResetKnopf => 'Reset…';

  @override
  String get einstResetBestaetigenTitel => 'Really reset the database?';

  @override
  String get einstResetBestaetigenText =>
      'IRREVERSIBLY deletes all photos, videos, thumbnails and the entire database of this library (albums, people, tags, places, favourites, locked folder, trash, saved searches, …). Downloaded AI models and geo data are kept. Make a backup first if you are unsure – this CANNOT be undone.';

  @override
  String get einstResetWort => 'RESET';

  @override
  String get einstResetEndgueltig => 'Reset for good';

  @override
  String get einstResetLaeuft => 'Deleting the library …';

  @override
  String get einstResetFertig =>
      'The library has been deleted completely. The app is closing now – please open it again to start with an empty library.';

  @override
  String get einstResetFehlgeschlagen => 'Reset failed';

  @override
  String get einstUeberTitel => 'About this app';

  @override
  String get einstKeineModelle => 'No AI models downloaded';

  @override
  String einstModelleGeladen(int geladen, int gesamt) {
    return '$geladen of $gesamt AI models downloaded';
  }

  @override
  String get einstModelleUnbenutzt =>
      'The AI features stay unused without them.';

  @override
  String get einstAktualisierungHinweis =>
      'The check asks the public release list once for the latest version number. Nothing about your library is sent, and it happens only when you press this button – never on its own.';

  @override
  String einstAktualisierungNeuer(String version) {
    return 'A newer version is available: $version';
  }

  @override
  String get einstAktualisierungAktuell => 'This version is up to date.';

  @override
  String einstAktualisierungFehler(String fehler) {
    return 'Check failed: $fehler';
  }

  @override
  String get einstVerschiebenFehlgeschlagen => 'Moving failed';

  @override
  String get einstWechselnFehlgeschlagen => 'Switching failed';

  @override
  String get einstNeustartTitel => 'Restart required';

  @override
  String get einstUebersetzeBeschreibungTitel =>
      'Translate image descriptions into the interface language';

  @override
  String get einstUebersetzeBeschreibungText =>
      'The description model only produces English, and there is no comparably small German one. With the “Translation English → German” model downloaded, every new description is translated as well. The English original is kept, and search finds both.';

  @override
  String get einstUebersetzeSucheTitel => 'Translate search terms and tags';

  @override
  String get einstUebersetzeSucheText =>
      'The text side of the image search model only understands English, while the tag vocabulary is German. Switched on, search terms and vocabulary go through the translation first. Measured across 103 photos it is more precise for 33 of 56 terms and worse for 19 – and it assigns noticeably fewer tags. Worth trying, not worth defaulting to.';

  @override
  String get allgEntfernen => 'Remove';

  @override
  String get allgEinrichten => 'Set up';

  @override
  String get allgHerunterladen => 'Download';

  @override
  String get allgAktiv => 'On';

  @override
  String get einstAbschnittErscheinungsbild => 'Appearance';

  @override
  String get einstAbschnittModelle => 'AI models (local & open source)';

  @override
  String get einstAbschnittHintergrund => 'Background tasks';

  @override
  String get einstAbschnittVokabular => 'AI tagging vocabulary';

  @override
  String get einstAbschnittStandortdaten =>
      'Location data (local & open source)';

  @override
  String get einstAbschnittGesperrterOrdner => 'Locked folder';

  @override
  String get einstAbschnittManuellesBackup => 'Manual cloud backup';

  @override
  String get einstAbschnittAutoBackup => 'Automatic backup';

  @override
  String get einstAbschnittPapierkorb => 'Trash';

  @override
  String get einstAbschnittGefahrenzone => 'Danger zone';

  @override
  String get einstDesign => 'Theme';

  @override
  String get einstDesignHell => 'Light';

  @override
  String get einstDesignDunkel => 'Dark';

  @override
  String get einstDesignSystem => 'System';

  @override
  String get einstUeberwachtNichtsNeues => 'Folder set up – nothing new found.';

  @override
  String get einstBibWechselnAktion => 'Switch';

  @override
  String get einstBibWechselnLaeuft => 'Switching library …';

  @override
  String get einstBibAktiv => 'open';

  @override
  String get einstBibImmerVorhanden => 'always present';

  @override
  String get einstSpeicherort => 'Storage location';

  @override
  String get einstSpeicherortVerschiebenLaeuft => 'Moving library …';

  @override
  String einstSpeicherortFortschritt(
      String kopiert, String gesamt, int dateien, int dateienGesamt) {
    return '$kopiert of $gesamt · $dateien of $dateienGesamt files';
  }

  @override
  String get einstSpeicherbedarf => 'Space used';

  @override
  String get belegung_originals => 'Originals';

  @override
  String get belegung_previews => 'Previews';

  @override
  String get belegung_thumbnails => 'Thumbnails';

  @override
  String get belegung_developed => 'Developed versions';

  @override
  String get belegung_restored => 'Restored versions';

  @override
  String get belegung_trimmed => 'Trimmed videos';

  @override
  String get belegung_masks => 'Masks';

  @override
  String get belegung_faces => 'Face crops';

  @override
  String get belegung_luts => 'Colour tables';

  @override
  String get belegung_trash => 'Trash';

  @override
  String get belegung_datenbank => 'Database';

  @override
  String get belegung_sonstiges => 'Other';

  @override
  String einstModellLaedt(String titel) {
    return 'Downloading “$titel” …';
  }

  @override
  String get einstModellePruefenTitel => 'Verify models';

  @override
  String get einstModellePruefenText =>
      'Recomputes the checksum of every installed model file and compares it with the catalogue. Takes a few seconds. Finds files that changed after they were downloaded – the download itself is always checked.';

  @override
  String einstModellePruefenLaeuft(String datei) {
    return 'Verifying: $datei';
  }

  @override
  String einstModellePruefenAlleGut(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl model files checked, all match.',
      one: 'One model file checked, it matches.',
    );
    return '$_temp0';
  }

  @override
  String get einstModellePruefenNichtsDa => 'No model is installed.';

  @override
  String get einstModellePruefenBefundTitel => 'Model files that stand out';

  @override
  String get einstModellePruefenBefundText =>
      'These files are not the ones the catalogue names. Delete the affected model and download it again – only then is what it produces trustworthy.';

  @override
  String get einstModellZustandFehlt => 'missing';

  @override
  String get einstModellZustandZuKurz => 'wrong length';

  @override
  String get einstModellZustandWeichtAb => 'content differs';

  @override
  String einstModelleBelegterPlatz(String groesse) {
    return 'Space used by all models: $groesse';
  }

  @override
  String einstModellLizenzZeile(String lizenz) {
    return 'Licence: $lizenz';
  }

  @override
  String get einstGesichtserkennungAktiv => 'Face detection active';

  @override
  String get einstGesichtserkennungBeides =>
      'Detection + recognition embeddings active';

  @override
  String get einstGesichtserkennungInaktiv =>
      'Inactive – download the YuNet model above';

  @override
  String get einstGeoLaedt => 'Downloading location data …';

  @override
  String get einstPinEinrichten => 'Set up a PIN';

  @override
  String get einstGesperrterOrdner => 'Locked folder';

  @override
  String get einstPinEingerichtet => 'PIN is set.';

  @override
  String get einstPinEntfernen => 'Remove PIN';

  @override
  String get einstGesperrtAufloesenTitel => 'Remove PIN protection?';

  @override
  String get einstSitzungSperren => 'Lock this session now';

  @override
  String get einstPassphraseEinrichten => 'Set up a passphrase';

  @override
  String get einstBackupPassphrase => 'Backup passphrase';

  @override
  String get einstBackupPassphraseEingeben => 'Enter the backup passphrase';

  @override
  String get einstBackupSichertLaeuft => 'Backing up the library …';

  @override
  String get einstBackupWiederherstellenLaeuft => 'Restoring the library …';

  @override
  String get einstLetztesBackup => 'Last backup';

  @override
  String einstBackupZusammenfassung(String datum, int anzahl, String ziel) {
    return '$datum – $anzahl file(s) to $ziel';
  }

  @override
  String get einstJetztSichern => 'Back up now';

  @override
  String get einstWiederherstellen => 'Restore';

  @override
  String get einstBackupPruefen => 'Verify backup';

  @override
  String get einstBackupPruefungLaeuft => 'Checking recoverability …';

  @override
  String einstBackupPruefungErfolgreich(int anzahl) {
    return '$anzahl file(s) can be fully restored.';
  }

  @override
  String einstBackupPruefungFehler(int gueltig, int fehlend, int beschaedigt) {
    return '$gueltig valid, $fehlend missing, $beschaedigt corrupted.';
  }

  @override
  String get einstZielordner => 'Destination folder';

  @override
  String get einstIntervall => 'Interval';

  @override
  String get einstIntervallSechsStunden => 'Every 6 hours';

  @override
  String get einstMengeJeLauf => 'Amount per run';

  @override
  String get einstUnbegrenzt => 'Unlimited';

  @override
  String get einstLetzterLauf => 'Last run';

  @override
  String get einstJetztSynchronisieren => 'Synchronise now';

  @override
  String get einstNachTagen => 'After';

  @override
  String einstTageDropdown(int tage) {
    return '$tage days';
  }

  @override
  String get einstDatenbank => 'Database';

  @override
  String einstDatenbankStand(int version) {
    return 'Version $version';
  }

  @override
  String einstBauZeile(String bau, String system, String systemversion) {
    return 'Build $bau · $system $systemversion';
  }

  @override
  String get einstLizenzen => 'Licences';

  @override
  String get einstLizenzenText =>
      'The licences of the bundled fonts and of every library in use.';

  @override
  String get einstNachAktualisierungSuchen => 'Check for updates';

  @override
  String get modellYunetTitel => 'Face detection – YuNet';

  @override
  String get modellYunetText =>
      'Finds faces (bounding boxes) in photos. A lightweight CNN, part of the OpenCV Zoo.';

  @override
  String get modellYunetLizenz => 'Apache-2.0';

  @override
  String get modellSfaceTitel => 'Face recognition – SFace';

  @override
  String get modellSfaceText =>
      'Computes one embedding per face so that similar or identical faces group together while you assign them by hand. Part of the OpenCV Zoo.';

  @override
  String get modellSfaceLizenz => 'Apache-2.0';

  @override
  String get modellClipTitel => 'AI image search – CLIP ViT-B/32';

  @override
  String einstAlleModelleLaden(int anzahl) {
    return 'Download all missing ($anzahl)';
  }

  @override
  String get einstAlleModelleDa => 'All models are ready';

  @override
  String einstAlleModelleLaeuft(int nummer, int gesamt) {
    return 'Model $nummer of $gesamt';
  }

  @override
  String get modellClipText =>
      'Lets you search for photos in plain language (for example “sunset over the sea”). Original OpenAI weights, exported as separate image and text encoder ONNX graphs.';

  @override
  String get modellClipLizenz => 'MIT (weights: OpenAI CLIP, see source)';

  @override
  String get modellSamTitel => 'AI object masks – SAM ViT-Base';

  @override
  String get modellSamText =>
      'Lets you adjust one chosen area instead of the whole picture in the develop screen – brightening only the sky, say. You place foreground and background points, and a promptable segmentation model proposes the matching mask.';

  @override
  String get modellSamLizenz =>
      'Apache-2.0 (weights: Meta Segment Anything, see source)';

  @override
  String get modellCaptionTitel => 'AI image captions – Florence-2 (English)';

  @override
  String get modellCaptionText =>
      'Generates a caption for each photo – for search and as a quick overview. It also reads text in the image, such as shop signs or place names. Output is English; the app can translate it into your language with a separate model. There is no comparably small multilingual model – the multilingual ones are gigabytes in size.';

  @override
  String get modellCaptionLizenz =>
      'MIT (base: microsoft/Florence-2-base-ft, ONNX port: onnx-community)';

  @override
  String get modellOcecTitel => 'Closed-eye detection – OCEC';

  @override
  String get modellOcecText =>
      'Marks faces with closed eyes while you cull – a quicker way to weed out blinks from portrait and group series.';

  @override
  String get modellOcecLizenz => 'MIT';

  @override
  String get modellEsrganTitel => 'AI restoration – Real-ESRGAN x4';

  @override
  String get modellEsrganText =>
      'Scales a photo up by a factor of four and removes noise along the way. Runs as a background queue (Settings/Develop) and takes several minutes depending on the size of the photo.';

  @override
  String get modellEsrganLizenz =>
      'BSD-3-Clause (original Real-ESRGAN weights)';

  @override
  String get modellEnDeTitel => 'Translation English → German – OPUS-MT';

  @override
  String get modellEnDeText =>
      'Translates the automatically generated captions into German. The captioning model itself only produces English, so without this you have to search in English for what you see in German. About 100 MB.';

  @override
  String get modellEnDeLizenz =>
      'Apache-2.0 (base: Helsinki-NLP/opus-mt-en-de, ONNX port: Xenova)';

  @override
  String get modellDeEnTitel => 'Translation German → English – OPUS-MT';

  @override
  String get modellDeEnText =>
      'Translates German search terms and tags before they reach the AI image search, whose text encoder only understands English. About 100 MB.';

  @override
  String get modellDeEnLizenz =>
      'Apache-2.0 (base: Helsinki-NLP/opus-mt-de-en, ONNX port: Xenova)';

  @override
  String get werkzKeineUnbewerteten => 'No unrated photos found.';

  @override
  String get werkzKeinePassenden => 'No matching photos found.';

  @override
  String get werkzGesichterScannenTitel => 'Scan for faces';

  @override
  String get werkzScanneNeue => 'Scanning new photos …';

  @override
  String get werkzScanneAlle => 'Scanning all photos again …';

  @override
  String get werkzErstelleFehlende => 'Creating the missing previews …';

  @override
  String get werkzErstelleAlle => 'Rebuilding all previews …';

  @override
  String get werkzRendereNeu => 'Re-rendering developed photos …';

  @override
  String get werkzKeineEntwickelten => 'No developed photos found.';

  @override
  String get werkzPruefeLivePhotos => 'Looking for Live Photo pairs …';

  @override
  String get werkzKeineUnverknuepften => 'No unlinked photos found.';

  @override
  String get werkzBerechneEmbeddings => 'Computing CLIP embeddings …';

  @override
  String get werkzAlleHabenEmbedding => 'Every photo already has an embedding.';

  @override
  String get werkzBerechneKiTags => 'Computing AI tags …';

  @override
  String get werkzLeseOrte => 'Reading locations from photos …';

  @override
  String get werkzAlleHabenOrt =>
      'Every photo already has a location (or no EXIF GPS data).';

  @override
  String get werkzLoeseOrteAuf => 'Resolving country/region/city …';

  @override
  String get werkzAlleAufgeloest =>
      'Every photo with a known location has already been resolved.';

  @override
  String get werkzLeseKameradaten => 'Reading camera data from photos …';

  @override
  String get werkzAlleHabenKameradaten =>
      'Every photo already has camera data (or no matching EXIF data).';

  @override
  String get werkzSchreibeXmp => 'Writing XMP sidecars …';

  @override
  String get werkzKeineFotosGesperrt =>
      'No photos found (locked photos are skipped).';

  @override
  String get werkzErkenneText => 'Recognising text in photos …';

  @override
  String get werkzAlleTextDurchsucht =>
      'Every photo has already been searched for text.';

  @override
  String get werkzErzeugeBeschreibungen => 'Generating image captions …';

  @override
  String get werkzAlleHabenBeschreibung =>
      'Every photo already has an AI caption.';

  @override
  String get werkzBerechneUnschaerfe => 'Computing blur scores …';

  @override
  String get werkzAlleHabenUnschaerfe =>
      'A blur score has already been computed for every photo.';

  @override
  String get werkzAbschnittStatistik => 'Statistics';

  @override
  String get werkzAnalyseseiteTitel => 'Analysis page';

  @override
  String get werkzAnalyseseiteText =>
      'Number of photos and videos, disk space, shots per year and month, most-used cameras';

  @override
  String get werkzAbschnittGesichtserkennung => 'Face detection';

  @override
  String get werkzSchwelleLabel =>
      'Similarity threshold for\n\"Select similar as well\"';

  @override
  String get werkzSchwelleErklaerung =>
      'Higher values mean a stricter match: fewer hits, but safer ones. It applies to the \"Select similar as well\" button under \"Unnamed faces\" in the People tab.';

  @override
  String get werkzAbschnittVorschau => 'Previews';

  @override
  String get werkzHeicTitel => 'HEIC/HEIF & RAW support';

  @override
  String get werkzHeicAktiv =>
      'Active – iPhone photos (HEIC) and RAW files (DNG, CR2/CR3, NEF, ARW, RAF, ORF, RW2 and the rest) go through native macOS image conversion.';

  @override
  String get werkzHeicInaktiv =>
      'Inactive – the native Swift file still has to be added to the Xcode project (see the README). JPG/PNG/WebP/GIF/BMP/TIFF work without it.';

  @override
  String get werkzHeicWerkzeugeAktiv =>
      'Active – iPhone photos (HEIC) and RAW files (DNG, CR2/CR3, NEF, ARW, RAF, ORF, RW2 and the rest) go through the bundled tools.';

  @override
  String werkzHeicWerkzeugeFehlen(String namen) {
    return 'Limited – missing: $namen. The formats that depend on them stay without a preview; JPG/PNG/WebP/GIF/BMP/TIFF keep working.';
  }

  @override
  String get werkzNeuRendernTitel => 'Re-render developed photos';

  @override
  String get werkzAbschnittOrte => 'Locations';

  @override
  String get werkzOrteAufloesenTitel => 'Resolve country/region/city';

  @override
  String get werkzAbschnittKamera => 'Camera';

  @override
  String get werkzPresetsTitel => 'Manage camera presets';

  @override
  String get werkzPresetsText =>
      'Automatically put photos from a particular camera into an album or tag, or mark them as favourites, as they are imported – digiKam\'s \"preset the camera for import\" by another name.';

  @override
  String get werkzRegelnTitel => 'Manage automation rules';

  @override
  String get werkzRegelnText =>
      'Automatically put photos into an album or tag, or mark them as favourites, based on location, AI tag or capture date – like camera presets, but for other conditions.';

  @override
  String get werkzAllesNachholenTitel => 'Catch up on all analysis now';

  @override
  String get werkzAllesNachholenText =>
      'Starts every expensive step one after another in the background: blur, faces, text recognition, image search, tags and captions. Each step skips what it already has, and the app stays usable throughout.';

  @override
  String get werkzAbschnittBibliothek => 'Library';

  @override
  String get werkzSichtenTitel => 'Cull unrated photos';

  @override
  String get werkzSichtenText =>
      'Opens every photo and video that is still unrated in full-screen culling mode, for going through and rating them quickly.';

  @override
  String get werkzDuplikateTitel => 'Find duplicates & similar photos';

  @override
  String get werkzDuplikateText => 'Based on the CLIP image embeddings';

  @override
  String get werkzStapelTitel => 'Group burst shots';

  @override
  String get werkzStapelText =>
      'Finds similar photos taken close together in time – burst shots, typically – and, if you want, collapses them into one stack with a cover image.';

  @override
  String get werkzIntegritaetTitel => 'Library integrity check';

  @override
  String get werkzIntegritaetText =>
      'Compares the database against the files actually on disk: missing files, orphaned files and, if you like, checksum mismatches.';

  @override
  String get werkzAbschnittInterop => 'Interoperability';

  @override
  String get werkzXmpSchreibenTitel => 'Write XMP sidecars';

  @override
  String get werkzXmpLesenTitel => 'Read XMP sidecars';

  @override
  String get werkzXmpLesenText =>
      'Reads existing .xmp files – edited externally in Lightroom, darktable or digiKam, say – and shows where they differ from the database: rating, colour label, description, tags, location.';

  @override
  String sichtungHilfeleiste(int aktuell, int gesamt) {
    return '$aktuell / $gesamt   ·   0–5 rating   ·   ⌫ reject   ·   ← → next';
  }

  @override
  String get ansicht360 => '360° view';

  @override
  String personenZuordnenKnopf(int anzahl) {
    return 'Assign $anzahl';
  }

  @override
  String get aufgStatus => 'Status';

  @override
  String get aufgBereit => 'Ready';

  @override
  String get aufgLaeuft => 'Analysis is running in the background.';

  @override
  String get aufgJetztStarten => 'Start now';

  @override
  String get aufgWartend => 'Waiting';

  @override
  String get aufgWenigerGleichzeitig => 'One fewer';

  @override
  String get aufgMehrGleichzeitig => 'One more';

  @override
  String get aufgBetrifft => 'Affects';

  @override
  String aufgStufe(
      String stufe, int erledigt, int gesamt, int nummer, int stufenGesamt) {
    return '$stufe ($erledigt/$gesamt) – step $nummer of $stufenGesamt';
  }

  @override
  String aufgModellNoetig(String modell, String wo) {
    return 'This needs $modell first ($wo).';
  }

  @override
  String get aufgYunetModell => 'the YuNet model';

  @override
  String get aufgClipModell => 'the CLIP model';

  @override
  String get aufgBeschreibungsmodell => 'the image captioning model';

  @override
  String get aufgGeoDatensatz => 'the GeoNames dataset';

  @override
  String get aufgWoModelle => 'Settings → AI models';

  @override
  String get aufgWoStandortdaten => 'Settings → Location data';

  @override
  String get aufgGesichterText =>
      'Finds faces and assigns them, as long as the YuNet model is installed.';

  @override
  String get aufgVorschauText =>
      'Creates thumbnails and previews for photos and videos. For a video this produces a still frame from the first second – only then can it be analysed at all (description, tags, faces, text). A pass over the other tasks pays off afterwards.';

  @override
  String get aufgFehlende => 'Missing';

  @override
  String get aufgGesichtsschaerfeTitel => 'Face sharpness';

  @override
  String get aufgGesichtsschaerfeText =>
      'Measures how sharp each recognised face is – on the crop that is already stored, without decoding the photos again. When culling, the app then warns if even the sharpest face in a shot is soft.';

  @override
  String get werkzBerechneGesichtsschaerfe => 'Measure face sharpness';

  @override
  String get aufgOcrTitel => 'Recognise text (OCR)';

  @override
  String get aufgOcrText =>
      'Finds visible text in photos, entirely locally through Apple\'s Vision framework.';

  @override
  String get aufgBeschreibungenTitel => 'Image captions';

  @override
  String get aufgBeschreibungenText =>
      'Writes one short English AI caption per photo.';

  @override
  String get aufgEmbeddingsTitel => 'CLIP embeddings';

  @override
  String get aufgEmbeddingsText =>
      'The basis for AI image search and duplicate detection.';

  @override
  String get aufgKiTagsTitel => 'AI tags';

  @override
  String get aufgKiTagsText =>
      'Automatically assigns photos fitting tags from the vocabulary, using CLIP.';

  @override
  String get aufgUnschaerfeTitel => 'Blur';

  @override
  String get aufgUnschaerfeText =>
      'What the \"Show blurry photos only\" search filter needs.';

  @override
  String get aufgOrteTitel => 'Read locations';

  @override
  String get aufgOrteText =>
      'Reads EXIF GPS data from photos after the fact. The number counts photographs without a place; how many carry one in the file only the run itself can tell.';

  @override
  String get aufgOrteAufloesenText =>
      'Works out the country, state or province and city behind a photo\'s GPS position.';

  @override
  String get aufgKameraTitel => 'Read camera data';

  @override
  String get aufgKameraText =>
      'Reads camera, lens, focal length, aperture, ISO and shutter speed from the metadata - from EXIF for photographs, from the container for videos. The number counts items without a camera; those carrying no metadata at all stay in it.';

  @override
  String get aufgDateiartTitel => 'Check file kinds';

  @override
  String get aufgDateiartText =>
      'Some stills arrive under a video name. Treated as a video they drop out of every analysis, get no thumbnail and no location. This run looks at the bytes and corrects the kind. A pass over the other tasks pays off afterwards.';

  @override
  String get werkzPruefeDateiarten => 'Checking file kinds …';

  @override
  String get werkzAlleArtenStimmen => 'Every photo is filed correctly.';

  @override
  String get aufgLivePhotoTitel => 'Check Live Photo pairs';

  @override
  String get aufgLivePhotoText =>
      'Links HEIC/JPG stills with MOV videos of the same name. The number counts photographs without a partner; most have none and never will.';

  @override
  String get aufgRendernText =>
      'Renders photos with saved develop adjustments again, unchanged.';

  @override
  String get aufgXmpText =>
      'Puts an .xmp file next to every photo for Lightroom, darktable or digiKam.';

  @override
  String get auswAufheben => 'Clear selection';

  @override
  String auswAnzahl(int anzahl) {
    return '$anzahl selected';
  }

  @override
  String get auswFavorisieren => 'Mark as favourite';

  @override
  String get auswZuAlbum => 'Add to album';

  @override
  String get auswTagHinzufuegen => 'Add a tag';

  @override
  String get auswBewertungSetzen => 'Set rating';

  @override
  String get auswFarbeSetzen => 'Set colour label';

  @override
  String get auswMetadaten => 'Edit metadata';

  @override
  String get auswEntwicklungUebertragen => 'Paste copied develop settings';

  @override
  String get auswExportieren => 'Export';

  @override
  String get allgLoeschen => 'Delete';

  @override
  String get allgHinzufuegen => 'Add';

  @override
  String get allgWaehlen => 'Choose';

  @override
  String auswBewertungTitel(int anzahl) {
    return 'Rating for $anzahl photo(s)';
  }

  @override
  String get auswKeineBewertung => 'No rating';

  @override
  String auswFarbeTitel(int anzahl) {
    return 'Colour label for $anzahl photo(s)';
  }

  @override
  String get auswKeineFarbe => 'No colour';

  @override
  String auswMetadatenTitel(int anzahl) {
    return 'Edit metadata for $anzahl photo(s)';
  }

  @override
  String get auswBeschreibungFeld => 'Description (overwrites existing ones)';

  @override
  String get auswDatumUnveraendert => 'Leave the date unchanged';

  @override
  String auswDatumGesetzt(String datum) {
    return 'Date: $datum';
  }

  @override
  String get auswOrtHinweis => 'Location (to leave it unchanged, do not tap)';

  @override
  String get auswOrtEntfernen => 'Remove location';

  @override
  String auswTagTitel(int anzahl) {
    return 'Add a tag to $anzahl photo(s)';
  }

  @override
  String get auswTagFeld => 'Tag';

  @override
  String auswExportTitel(int anzahl) {
    return 'Export $anzahl photo(s)';
  }

  @override
  String get auswVorgabeAnwenden => 'Apply preset';

  @override
  String auswVorgabeAnwendenTitel(int anzahl) {
    return 'Apply preset to $anzahl photo(s)';
  }

  @override
  String auswUebertragenTitel(int anzahl) {
    return 'Paste develop settings onto $anzahl photo(s)?';
  }

  @override
  String get auswUebertragenText =>
      'The copied values for exposure, white balance, contrast and shadows are applied, and each photo is re-rendered.\n\nMasks are not carried over. Each photo\'s previous state stays in its history.';

  @override
  String get auswUebertragen => 'Paste';

  @override
  String get auswUebertrageLaeuft => 'Pasting develop settings …';

  @override
  String get auswKeineGeeigneten =>
      'No suitable photos – locked photos and videos are left out.';

  @override
  String auswZielordner(int anzahl) {
    return 'Choose a destination folder for $anzahl photo(s)';
  }

  @override
  String auswExportiereLaeuft(int erledigt, int gesamt) {
    return 'Exporting … ($erledigt / $gesamt)';
  }

  @override
  String auswExportFertig(int erledigt, int gesamt, String ziel) {
    return 'Exported $erledigt of $gesamt photo(s) to $ziel';
  }

  @override
  String get exportOriginal => 'Original';

  @override
  String get exportGross => 'Large – 4096 px';

  @override
  String get exportWeb => 'Web – 2048 px';

  @override
  String get exportEmail => 'E-mail – 1024 px';

  @override
  String get exportUnveraendert => 'File unchanged, with an XMP file alongside';

  @override
  String exportJpegKante(int kante) {
    return 'As JPEG, long edge at most $kante px';
  }

  @override
  String get allgUebernehmen => 'Apply';

  @override
  String get allgAlle => 'All';

  @override
  String get suchoptTagsWaehlen => 'Choose tags';

  @override
  String get suchoptTagsFiltern => 'Filter tags …';

  @override
  String get suchoptKeineTags => 'No tags found.';

  @override
  String get suchoptTitel => 'Search options';

  @override
  String get suchoptKeineTreffer =>
      'No photos found – this combination of filters returns 0 results.';

  @override
  String get suchoptAllesLeeren => 'Clear everything';

  @override
  String get suchoptSuchen => 'Search';

  @override
  String get suchoptPersonenFiltern => 'Filter people';

  @override
  String get suchoptKeinePersonenBenannt => 'No one has been named yet.';

  @override
  String get suchoptKeinePersonenGefunden => 'No people found.';

  @override
  String get suchoptTypTitel => 'Search by type';

  @override
  String get suchoptTypKontext => 'Context';

  @override
  String get suchoptTypDateiname => 'File name';

  @override
  String get suchoptTypBeschreibung => 'Description';

  @override
  String get suchoptTypOcr => 'Text in the photo (OCR)';

  @override
  String get suchoptTypCaption => 'AI caption (English)';

  @override
  String get suchoptNachKontext => 'Search by context';

  @override
  String get suchoptNachDateiname => 'Search by file name';

  @override
  String get suchoptNachBeschreibung => 'Search by description';

  @override
  String get suchoptNachOcr => 'Search text recognised in the photo';

  @override
  String get suchoptNachCaption => 'Search by AI caption (English)';

  @override
  String get suchoptHintKontext =>
      'e.g. \"sunrise on the beach\", \"dog in the snow\" …';

  @override
  String get suchoptHintDateiname => 'File name …';

  @override
  String get suchoptHintBeschreibung => 'Description …';

  @override
  String get suchoptHintOcr => 'Text in the photo …';

  @override
  String get suchoptHintCaption => 'e.g. \"dog\", \"sunset\" …';

  @override
  String get suchoptClipFehlt =>
      'AI image search is unavailable – the model is missing (see Settings → AI models).';

  @override
  String get suchoptCaptionFehlt =>
      'AI captions are unavailable – the model is missing (see Settings → AI models).';

  @override
  String get suchoptTagsTitel => 'Tags';

  @override
  String get suchoptTagsHint => 'Search for tags …';

  @override
  String get suchoptOhneTag => 'Without a tag';

  @override
  String get suchoptMindestbewertung => 'Minimum rating';

  @override
  String get suchoptFarbmarkierung => 'Colour label';

  @override
  String get suchoptDateiformat => 'File format';

  @override
  String get suchoptNurRaw => 'RAW only';

  @override
  String get farbeRot => 'Red';

  @override
  String get farbeGelb => 'Yellow';

  @override
  String get farbeGruen => 'Green';

  @override
  String get farbeBlau => 'Blue';

  @override
  String get farbeLila => 'Purple';

  @override
  String get suchoptAufnahmewerte => 'Capture settings';

  @override
  String get suchoptIsoVon => 'ISO from';

  @override
  String get suchoptIsoBis => 'ISO to';

  @override
  String get suchoptBlendeVon => 'Aperture from (f/…)';

  @override
  String get suchoptBlendeBis => 'Aperture to (f/…)';

  @override
  String get suchoptBrennweiteVon => 'Focal length from (mm)';

  @override
  String get suchoptBrennweiteBis => 'Focal length to (mm)';

  @override
  String get suchoptNurUnscharfe => 'Show blurry photos only';

  @override
  String get suchoptMarke => 'Make';

  @override
  String get suchoptModell => 'Model';

  @override
  String get suchoptObjektiv => 'Lens';

  @override
  String get suchoptOrtTitel => 'Location';

  @override
  String get suchoptLand => 'Country';

  @override
  String get suchoptBundesland => 'State/province';

  @override
  String get suchoptStadt => 'City';

  @override
  String get suchoptGeoFehlt =>
      'No locations resolved yet – download the GeoNames dataset and resolve your photos (see Settings → Location data, Tools → Locations).';

  @override
  String get suchoptAnfangsdatum => 'Start date';

  @override
  String get suchoptEnddatum => 'End date';

  @override
  String get suchoptDatumEntfernen => 'Clear the date';

  @override
  String get suchoptDatumPlatzhalter => 'dd/mm/yyyy';

  @override
  String get suchoptMedientyp => 'Media type';

  @override
  String get suchoptBild => 'Image';

  @override
  String get suchoptVideo => 'Video';

  @override
  String get suchoptAnzeigeoptionen => 'Display options';

  @override
  String get suchoptInKeinemAlbum => 'In no album';

  @override
  String get suchoptFavoriten => 'Favourites';

  @override
  String get entwTitel => 'Develop';

  @override
  String get entwVerlaufSitzung => 'This session';

  @override
  String get entwVerlaufGespeichert => 'Saved';

  @override
  String get entwVerlaufAusgangsstand => 'State when opened';

  @override
  String get entwVerlaufOhneAenderung => 'No change';

  @override
  String get entwVerlaufJetzt => 'Current state';

  @override
  String get entwWerkzBelichtung => 'Exposure';

  @override
  String get entwWerkzWeissabgleich => 'White balance';

  @override
  String get entwWerkzTemperatur => 'Temperature';

  @override
  String get entwWerkzTint => 'Tint';

  @override
  String get entwWerkzKontrast => 'Contrast';

  @override
  String get entwWerkzLichter => 'Highlights';

  @override
  String get entwWerkzSchatten => 'Shadows';

  @override
  String get entwWerkzSchaerfe => 'Sharpness';

  @override
  String get entwWerkzRauschen => 'Noise reduction';

  @override
  String get entwWerkzKlarheit => 'Clarity';

  @override
  String get entwWerkzVignettierung => 'Vignette';

  @override
  String get entwWerkzKurve => 'Tone curve';

  @override
  String get entwWerkzFarbmischer => 'Colour mixer';

  @override
  String get entwWerkzFarbtabelle => 'Colour table';

  @override
  String get entwWerkzObjektiv => 'Lens correction';

  @override
  String get entwKeinVerlauf =>
      'No history yet – an entry appears once you save again after a first adjustment.';

  @override
  String get entwKopiert =>
      'Settings copied. You can now paste them onto other photos, even without saving this one.';

  @override
  String get entwEingesetzt => 'Copied settings applied – not saved yet.';

  @override
  String get entwSpeichernFehlgeschlagen =>
      'Saving failed: the image could not be rendered.';

  @override
  String get entwRestaurierungLaeuft => 'AI restoration';

  @override
  String get entwRestaurierungEingereiht =>
      'Added to the AI restoration queue.';

  @override
  String entwRestaurierungFehler(String fehler) {
    return 'Could not be added to the queue: $fehler';
  }

  @override
  String entwKiAuswahlLadefehler(String fehler) {
    return 'AI selection could not be loaded: $fehler';
  }

  @override
  String get entwVorschauNichtDekodiert =>
      'The preview image could not be decoded for masking.';

  @override
  String entwKiAuswahlFehler(String fehler) {
    return 'AI selection failed: $fehler';
  }

  @override
  String entwMaskeNummer(int nummer) {
    return 'Mask $nummer';
  }

  @override
  String get entwAufloesungUnbekannt =>
      'Image resolution unknown – the mask cannot be saved.';

  @override
  String get entwRestaurierungEntfernen => 'Remove AI restoration';

  @override
  String get entwRestaurierungModellFehlt =>
      'Needs the restoration model (Settings → AI models)';

  @override
  String get entwRestaurierungAnwenden =>
      'Apply AI restoration (runs in the background, takes several minutes)';

  @override
  String get entwMaskeHinzufuegen => 'Add a mask';

  @override
  String get entwVerlauf => 'History';

  @override
  String get entwEinstellungenKopieren =>
      'Copy settings (to paste onto other photos)';

  @override
  String get entwEinstellungenEinsetzen =>
      'Put the copied settings into the sliders';

  @override
  String get entwOriginal => 'Original';

  @override
  String get entwVergleichen => 'Press and hold to compare';

  @override
  String get entwVorher => 'Before';

  @override
  String get entwNachher => 'After';

  @override
  String get entwTrennstrich =>
      'Before and after side by side (drag the divider)';

  @override
  String get entwTrennstrichWartet =>
      'The unedited image is still being rendered – one moment.';

  @override
  String get entwMaskeErstellen => 'Create a mask';

  @override
  String get entwFormKi => 'AI';

  @override
  String get entwFormKiFehlt =>
      'Needs the segmentation model (Settings → AI models)';

  @override
  String get entwFormPinsel => 'Brush';

  @override
  String get entwFormEllipse => 'Ellipse';

  @override
  String get entwFormVerlauf => 'Gradient';

  @override
  String get allgFertig => 'Done';

  @override
  String get entwKiHinweis =>
      'Tap the area you want to adjust. Several taps refine the selection.';

  @override
  String get entwPunktHinzufuegen => 'Add';

  @override
  String get entwPunktEntfernen => 'Remove';

  @override
  String get entwLetztenPunktEntfernen => 'Remove the last point';

  @override
  String get entwPinselHinweis => 'Drag across the area you want to adjust.';

  @override
  String get entwNeuZeichnen => 'Draw again';

  @override
  String get entwEllipseHinweis =>
      'Drag across the area to pull open the ellipse.';

  @override
  String get entwVerlaufHinweis =>
      'Drag from one edge to the other to set the gradient.';

  @override
  String get entwAnpassungFuer => 'Adjusting';

  @override
  String get entwGanzesBild => 'The whole image';

  @override
  String get entwFormBearbeiten => 'Edit the shape';

  @override
  String get entwAutoWeissabgleich => 'Automatic white balance';

  @override
  String get entwObjektivkorrektur => 'Lens correction';

  @override
  String get entwObjektivkorrekturHinweis =>
      'Only takes effect on RAW photos whose camera and lens are supported.';

  @override
  String get entwMaskenHinweis =>
      'These adjustments apply only inside the selected mask.';

  @override
  String get entwBelichtung => 'Exposure';

  @override
  String get entwTemperatur => 'Temperature (K)';

  @override
  String get entwTint => 'Tint';

  @override
  String get entwKontrast => 'Contrast';

  @override
  String get entwBeschneidungWarnung =>
      'Show clipping (red = blown, blue = crushed)';

  @override
  String get entwBeschneidungMitMasken =>
      'Clipping cannot be shown while masks are on the photo – the marks come from the shader preview, and it cannot draw masks.';

  @override
  String get entwBeschneidungVorschauHinweis =>
      'Clipping preview – sharpness, noise, clarity and vignette are not shown here';

  @override
  String get entwVorgabeSichern => 'Save as preset';

  @override
  String get entwVorgabeAnwenden => 'Apply preset';

  @override
  String get entwVorgabeWaehlen => 'Choose a preset';

  @override
  String get entwVorgabeName => 'Preset name';

  @override
  String get entwKeineVorgaben => 'There is no develop preset yet.';

  @override
  String entwVorgabeGesichert(String name) {
    return 'Preset “$name” saved';
  }

  @override
  String entwVorgabeNameVergeben(String name) {
    return 'A preset named “$name” already exists.';
  }

  @override
  String get entwAutomatisch => 'Auto exposure and contrast';

  @override
  String get entwAutomatikOhneHistogramm => 'No histogram yet – one moment.';

  @override
  String get entwTiefenmaske => 'Mask from depth map';

  @override
  String get entwTiefenmaskeName => 'Depth';

  @override
  String get entwTiefenKeine =>
      'This photo carries no depth map. Only portrait shots from newer iPhones do.';

  @override
  String get entwTiefenNichtLesbar => 'The depth map could not be evaluated.';

  @override
  String get entwTiefenNurMacos =>
      'This photo may carry a depth map – only the macOS build can read it. There the depth data comes from Apple\'s ImageIO; on Linux and Windows the path runs through LibRaw and libheif, which do not expose the auxiliary image.';

  @override
  String get entwLichter => 'Highlights';

  @override
  String get entwSchatten => 'Shadows';

  @override
  String get entwSchaerfe => 'Sharpness';

  @override
  String get entwRauschunterdrueckung => 'Noise reduction';

  @override
  String get entwStrichbreite => 'Stroke width';

  @override
  String get entwRotation => 'Rotation (°)';

  @override
  String get entwWeichzeichnung => 'Feather';

  @override
  String get entwGesperrt =>
      'Develop is not available for photos in the locked folder.';

  @override
  String get entwVorschauFehlt =>
      'The preview could not be created – is native image conversion unavailable?';

  @override
  String get entwModellLaedt => 'Loading the model for AI selection …';

  @override
  String get entwBildWirdVorbereitet => 'Preparing the image for masking …';

  @override
  String get allgOder => '— or —';

  @override
  String get albumBestehendes => 'Existing album';

  @override
  String get albumNeuAnlegen => 'Create a new album';

  @override
  String get personZuordnenTitel => 'Assign a person';

  @override
  String personAktuell(String name) {
    return 'Currently: $name';
  }

  @override
  String get personZuordnenAktion => 'Assign';

  @override
  String get bestaetigEndgueltigLoeschen => 'Delete permanently';

  @override
  String get bestaetigTippeVor => 'Type ';

  @override
  String get bestaetigTippeNach => ' to confirm:';

  @override
  String fortschrittFehlgeschlagen(String fehler) {
    return 'Failed: $fehler';
  }

  @override
  String sterneStern(int nummer) {
    return 'Star $nummer of 5';
  }

  @override
  String sterneSternVoll(int nummer) {
    return 'Star $nummer of 5, filled';
  }

  @override
  String sterneSetzen(int nummer) {
    return 'Set a rating of $nummer out of 5 stars';
  }

  @override
  String sterneBewertungAnzeige(int nummer) {
    return 'Rated $nummer out of 5 stars';
  }

  @override
  String get scrubberTooltip => 'Jump to a date';

  @override
  String get farbeViolett => 'Violet';

  @override
  String farbeAusgewaehlt(String farbe) {
    return '$farbe, selected';
  }

  @override
  String farbeSetzen(String farbe) {
    return 'Set the $farbe colour label';
  }

  @override
  String get histogrammTitel => 'Histogram';

  @override
  String get histogrammKeineVorschau => 'No preview yet';

  @override
  String get histogrammHelligkeit => 'Luminance';

  @override
  String get livePhotoHalten => 'Press and hold to play';

  @override
  String get metaBelichtungBeispiel => 'e.g. 1/125 or 0.5';

  @override
  String get karteTippenFuerOrt => 'Tap to set a location';

  @override
  String get rasterFotoNichtGefunden => 'That photo is not in the timeline.';

  @override
  String get kameraImportTitel => 'Import from a camera or SD card';

  @override
  String get kameraKeinDatentraeger =>
      'No volume with photos or videos found. Plug in a camera or SD card over USB – the list updates by itself as soon as one is recognised.';

  @override
  String get mischerTitel => 'Colour mixer';

  @override
  String get mischerFarbton => 'Hue';

  @override
  String get mischerSaettigung => 'Saturation';

  @override
  String get mischerHelligkeit => 'Luminance';

  @override
  String get mischerHinweis =>
      'Only affects coloured areas – greys are left untouched.';

  @override
  String get bandRot => 'Red';

  @override
  String get bandOrange => 'Orange';

  @override
  String get bandGelb => 'Yellow';

  @override
  String get bandGruen => 'Green';

  @override
  String get bandAqua => 'Aqua';

  @override
  String get bandBlau => 'Blue';

  @override
  String get bandViolett => 'Violet';

  @override
  String get bandMagenta => 'Magenta';

  @override
  String get kurveTitel => 'Tone curve';

  @override
  String get kurveHinweis =>
      'Drag to place or move a point; press and hold to remove one.';

  @override
  String get pinFeld => 'PIN';

  @override
  String get pinFestlegenTitel => 'Set a PIN';

  @override
  String get pinNeuFeld => 'New PIN (8-10 digits)';

  @override
  String get pinWiederholen => 'Repeat the PIN';

  @override
  String get pinWarnung =>
      'Important: photos in the locked folder are genuinely encrypted (AES-256). Without this PIN there is NO way to get them back – not even by resetting the app.';

  @override
  String get pinZiffernFehler => 'The PIN has to be 8 to 10 digits.';

  @override
  String get pinUngleich => 'The PINs do not match.';

  @override
  String get allgFestlegen => 'Set';

  @override
  String get pinEingebenTitel => 'Enter your PIN';

  @override
  String get pinFalsch => 'Wrong PIN.';

  @override
  String get passphraseFeld => 'Passphrase';

  @override
  String get passphraseFestlegenTitel => 'Set a backup passphrase';

  @override
  String get passphraseNeuFeld => 'New passphrase (at least 8 characters)';

  @override
  String get passphraseWiederholen => 'Repeat the passphrase';

  @override
  String get passphraseWarnung =>
      'Important: backups are genuinely encrypted (AES-256). Without this passphrase there is NO way to restore them – not even on another machine. Best write it down somewhere safe as well.';

  @override
  String get passphraseUngleich => 'The passphrases do not match.';

  @override
  String get passphraseFalsch => 'Wrong passphrase.';

  @override
  String get allgFoto => 'Photo';

  @override
  String get allgVideo => 'Video';

  @override
  String get kachelFavorisiert => 'favourite';

  @override
  String kachelBeschreibung(String typ, String name, String datum) {
    return '$typ $name, $datum';
  }

  @override
  String albumFotosLoeschenTitel(int anzahl) {
    return 'Delete $anzahl photo(s)?';
  }

  @override
  String get albumFotosLoeschenText =>
      'These photos are removed from the album and moved to the trash.';

  @override
  String albumZielordner(String album) {
    return 'Choose a destination folder for \"$album\"';
  }

  @override
  String get albumExportieren => 'Export the album';

  @override
  String get albumLeer => 'This album has no photos in it yet.';

  @override
  String get albumFotosHinzufuegen => 'Add photos';

  @override
  String get albumTitelbildSetzen => 'Use as cover';

  @override
  String get albumTitelbildGesetzt => 'Cover set';

  @override
  String albumFotosWaehlenTitel(String album) {
    return 'Photos for “$album”';
  }

  @override
  String get regelLoeschenTitel => 'Delete the rule?';

  @override
  String regelLoeschenText(String name) {
    return 'Really delete the rule \"$name\"? Actions it has already applied are kept.';
  }

  @override
  String get regelOrtUnvollstaendig => 'Location: not fully configured';

  @override
  String get regelDatumUnvollstaendig => 'Date range: not fully configured';

  @override
  String get regelTitel => 'Automation rules';

  @override
  String get regelNeu => 'New rule';

  @override
  String get regelLeer =>
      'No automation rules yet.\n\nCreate a rule to put photos into an album or tag automatically, or mark them as favourites, based on location, AI tag or capture date – like camera presets, but for other conditions.';

  @override
  String get allgBearbeiten => 'Edit';

  @override
  String get regelNameNoetig => 'The rule needs a name.';

  @override
  String get regelKoordinatenUngueltig =>
      'Latitude and longitude have to be valid numbers.';

  @override
  String get regelBreitengradBereich =>
      'Latitude has to be between -90 and 90.';

  @override
  String get regelLaengengradBereich =>
      'Longitude has to be between -180 and 180.';

  @override
  String get regelTagWaehlen => 'Please choose an AI tag term.';

  @override
  String get regelDatumWaehlen => 'Please choose a start and an end date.';

  @override
  String get regelDatumReihenfolge =>
      'The start date has to come before the end date.';

  @override
  String get regelBreitengrad => 'Latitude';

  @override
  String get regelLaengengrad => 'Longitude';

  @override
  String get regelKeinVokabular =>
      'There is no AI tag vocabulary (Settings → AI tagging vocabulary).';

  @override
  String get regelTagBegriff => 'AI tag term';

  @override
  String get regelNameFeld => 'Name (e.g. \"Holiday in Italy\")';

  @override
  String get regelBedingung => 'Condition';

  @override
  String get presetZielalbum => 'Destination album (optional)';

  @override
  String get presetKeinAlbum => 'No album';

  @override
  String get presetNeuesAlbum => 'or: create a new album';

  @override
  String get presetFavorisieren => 'Mark as favourite automatically';

  @override
  String get presetTagsWaehlenPlatzhalter => 'Choose tags …';

  @override
  String get presetKeineTags => 'There are no tags.';

  @override
  String get presetLoeschenTitel => 'Delete the preset?';

  @override
  String presetLoeschenText(String kamera) {
    return 'Really delete the camera preset for \"$kamera\"? Photos already imported stay as they are.';
  }

  @override
  String get presetTitel => 'Camera presets';

  @override
  String get presetNeu => 'New preset';

  @override
  String get presetLeer =>
      'No camera presets yet.\n\nCreate a preset for a particular camera to put its future imports into an album or tag automatically – even before the first photo from that camera has arrived.';

  @override
  String get presetHerstellerModellNoetig =>
      'Both make and model are required.';

  @override
  String get presetBekannteKamera => 'Use a known camera (optional)';

  @override
  String get presetHersteller => 'Make (e.g. Canon, Apple)';

  @override
  String get presetModell => 'Model (e.g. EOS R5, iPhone 15 Pro)';

  @override
  String get allgClipNoetigKurz =>
      'Needs the CLIP model (Settings → AI models).';

  @override
  String get duplNichtsLoeschbar =>
      'Nothing can be deleted automatically: every group has more than one photo marked as a favourite or rated – please go through those by hand.';

  @override
  String get duplNichtsZuLoeschen => 'Nothing to delete.';

  @override
  String get duplPapierkorbTitel => 'Move the copies to the trash?';

  @override
  String duplPapierkorbAnzahl(int fotos, int gruppen) {
    return '$fotos photo(s) from $gruppen group(s) will be moved to the trash.';
  }

  @override
  String get duplBehaltenRegel =>
      'Kept in each group: the favourite, otherwise the highest rating, otherwise the sharpest, otherwise the one with the highest resolution.';

  @override
  String duplUebersprungen(int anzahl) {
    return '$anzahl group(s) are left untouched, because more than one photo there is a favourite or rated.';
  }

  @override
  String get duplRueckgaengig => 'Undo: they can be restored from the trash.';

  @override
  String get duplInPapierkorb => 'Move to trash';

  @override
  String duplVerschoben(int anzahl) {
    return '$anzahl photo(s) moved to the trash.';
  }

  @override
  String get duplTitel => 'Duplicates & similar photos';

  @override
  String get duplZweiteBibliothek => 'Second library';

  @override
  String get duplAlleKopienLoeschen => 'Delete all copies';

  @override
  String get duplAehnlichkeit => 'Similarity:';

  @override
  String get duplSchwelleHinweis =>
      'Higher values mean only very similar photos are recognised as a group. Lower values find more, but less certain, matches.';

  @override
  String get duplKeineGruppen => 'No groups of similar photos found.';

  @override
  String get duplVerschiebenTooltip => 'Move to the trash';

  @override
  String get duplZusammenfuehren => 'Merge';

  @override
  String get duplZusammenfuehrenTitel => 'Merge similar photos';

  @override
  String duplZusammenfuehrenText(int anzahl) {
    return 'Metadata from all $anzahl photos is transferred to the selected photo. The remaining photos go to the trash and can be restored there.';
  }

  @override
  String get duplBehaltenAuswahl => 'Keep this photo';

  @override
  String duplBehaltenDetails(int sterne, int favorit) {
    return '$sterne stars · $favorit favourite(s)';
  }

  @override
  String get duplBeschreibungenVerbinden => 'Combine distinct descriptions';

  @override
  String duplZusammengefuehrt(int anzahl) {
    return 'Merged $anzahl photo(s) and moved them to trash.';
  }

  @override
  String get clusterTitel => 'Review suggestions';

  @override
  String get clusterFertig => 'All suggestions have been reviewed.';

  @override
  String clusterAehnlichZu(String name) {
    return 'Similar to: $name';
  }

  @override
  String get clusterUeberspringen => 'Skip';

  @override
  String get gesichtUmbenennen => 'Rename or change the person';

  @override
  String get gesichtNeuBenennen => 'Name a new face';

  @override
  String get gesichtGesperrt =>
      'Editing faces is not available for photos in the locked folder.';

  @override
  String get gesichtManuellHinzufuegen => 'Add a face by hand';

  @override
  String get gesichtHinzufuegenBeenden => 'Stop adding';

  @override
  String get gesichtRechteckHinweis =>
      'Drag a rectangle over a face to mark it by hand.';

  @override
  String get bearbBildNichtLesbar => 'The image could not be read.';

  @override
  String bearbBildNichtLesbarFehler(String fehler) {
    return 'The image could not be read: $fehler';
  }

  @override
  String get bearbSpeichernTitel => 'Save your changes?';

  @override
  String get bearbSpeichernText =>
      'The original file is replaced by the edited version. This cannot be undone.';

  @override
  String get bearbNichtFinalisiert => 'The image could not be finalised.';

  @override
  String get bearbZuschneidenAnwenden => 'Apply the crop';

  @override
  String get bearbTitel => 'Edit';

  @override
  String get importWasTitel => 'What would you like to import?';

  @override
  String get importWasText =>
      'Pick individual photos and videos, import a whole folder including its subfolders, or import straight from a connected camera or SD card.';

  @override
  String get importEinzelneDateien => 'Choose individual files';

  @override
  String get importGanzerOrdner => 'Choose a whole folder';

  @override
  String get importVonKamera => 'From a camera or SD card';

  @override
  String get importOrdnerWaehlen => 'Choose a folder to import';

  @override
  String get importNichtsImOrdner =>
      'No supported photos or videos found in that folder.';

  @override
  String get importNichtsAufDatentraeger =>
      'No supported photos or videos found on that volume.';

  @override
  String get importAbgeschlossen => 'Import finished';

  @override
  String importBilanzNeu(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl added',
      one: '1 added',
    );
    return '$_temp0';
  }

  @override
  String importBilanzDuplikate(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl were already in the library and were skipped',
      one: '1 was already in the library and was skipped',
    );
    return '$_temp0';
  }

  @override
  String importBilanzFehler(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl did not come in',
      one: '1 did not come in',
    );
    return '$_temp0';
  }

  @override
  String get importLaeuft => 'Importing photos & videos …';

  @override
  String get importJetztSichten => 'Cull them now';

  @override
  String integPruefungFehlgeschlagen(String fehler) {
    return 'The check failed: $fehler';
  }

  @override
  String get integOriginalFehlt =>
      'The original is missing from disk – the whole photo or video is removed from the library.';

  @override
  String get integMaskeFehlt =>
      'The mask file is missing – the mask entry is removed.';

  @override
  String get integCropFehlt =>
      'The face crop is missing – only the preview is removed; the person it belongs to is kept.';

  @override
  String get integPfadEntfernt =>
      'The file path is removed from the database – the file can be recreated through \"Tools → Rebuild previews\".';

  @override
  String get integDateiLoeschenTitel => 'Delete the file?';

  @override
  String integDateiLoeschenText(String pfad) {
    return '$pfad will be deleted from disk for good.';
  }

  @override
  String get integErneutPruefen => 'Check again';

  @override
  String get integPruefsummen => 'Check checksums';

  @override
  String get integPruefsummenHinweis =>
      'Reads every original file in full and compares it against the checksum stored at import – noticeably slower on a large library than checking only for missing and orphaned files.';

  @override
  String integKeineProbleme(int anzahl) {
    return 'No problems found ($anzahl files checked).';
  }

  @override
  String get integAusDbEntfernen => 'Remove from the database';

  @override
  String get integDateiLoeschen => 'Delete the file';

  @override
  String integAbweichungen(int anzahl) {
    return 'Checksum mismatches ($anzahl)';
  }

  @override
  String get integInhaltGeaendert => 'The contents have changed since import';

  @override
  String get integAnsehen => 'View';

  @override
  String get integVorschauTitel => 'Preview';

  @override
  String get integKeineVorschau => 'No preview can be shown for this file.';

  @override
  String get integVorschauVerschluesselt =>
      'The photo is locked – its preview is encrypted along with it.';

  @override
  String get integFotoOeffnen => 'Open the photo';

  @override
  String integHeaderProbleme(int anzahl) {
    return 'Encrypted files with an invalid header ($anzahl)';
  }

  @override
  String get integBeschaedigt =>
      'The file may be damaged – not a valid encrypted file';

  @override
  String get gesperrtLeer =>
      'No locked photos. In a photo\'s full-screen view, the lock icon in the top right moves it here and encrypts it on the way.';

  @override
  String get gesperrtEntfernen => 'Take out of the locked folder (decrypt)';

  @override
  String get gesperrtEndgueltigTitel => 'Delete permanently?';

  @override
  String get gesperrtEndgueltigText =>
      'The file will be deleted for good – there is no recovery afterwards, not even with the right PIN.';

  @override
  String get gesperrtPapierkorbLeer =>
      'The locked trash is empty.\n\nPhotos deleted from the locked folder land here rather than in the normal, unprotected trash.';

  @override
  String get gesperrtWiederherstellen => 'Restore (stays locked)';

  @override
  String get personKeineGesichter => 'There are no faces for this person.';

  @override
  String get personProfilbildWaehlen => 'Choose a profile picture';

  @override
  String get personProfilbildAendern => 'Change the profile picture';

  @override
  String get personKeineFotos => 'No photos for this person yet.';

  @override
  String get personDoppelklickHinweis =>
      'Double-clicking a photo opens it for review with every face that was found.';

  @override
  String get personGelerntesVerworfen =>
      'What was learned has been discarded – the general threshold applies again.';

  @override
  String personSchwelleAngepasst(String schwelle, String allgemein) {
    return 'adjusted to $schwelle instead of $allgemein';
  }

  @override
  String personSchwelleWiderspruch(String allgemein) {
    return 'still $allgemein – the decisions contradict each other; a rejected face was more similar than a confirmed one';
  }

  @override
  String personSchwelleWirdAngepasst(int anzahl) {
    return 'adjusted from $anzahl decisions onwards';
  }

  @override
  String get personVerwerfen => 'Discard';

  @override
  String get restaurWartet => 'Waiting in the queue';

  @override
  String restaurProzentLaeuft(int prozent) {
    return 'AI restoration running – $prozent%';
  }

  @override
  String restaurProzentMitRest(int prozent, String rest) {
    return 'AI restoration running – $prozent%, about $rest left';
  }

  @override
  String restaurProzentMitWarteschlange(int prozent, int wartend) {
    return 'AI restoration running – $prozent%, $wartend queued';
  }

  @override
  String restaurZeileLaeuft(int prozent) {
    return 'Running – $prozent%';
  }

  @override
  String restaurZeileMitRest(int prozent, String rest) {
    return 'Running – $prozent%, about $rest left';
  }

  @override
  String restaurDauerMinuten(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl minutes',
      one: 'one minute',
    );
    return '$_temp0';
  }

  @override
  String restaurDauerSekunden(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl seconds',
      one: 'one second',
    );
    return '$_temp0';
  }

  @override
  String get restaurWasPassiert =>
      'Real-ESRGAN scales the photo to four times its edge length and smooths noise and compression artefacts along the way. The original is untouched; the result sits beside it and can be removed at any time.';

  @override
  String get restaurTitel => 'AI restoration – queue';

  @override
  String get restaurLeer =>
      'There are no restoration jobs.\nYou can start an AI restoration from a photo\'s develop screen.';

  @override
  String get restaurAusListe => 'Remove from the list';

  @override
  String restaurFehlgeschlagen(String grund) {
    return 'Failed: $grund';
  }

  @override
  String get restaurFehlgeschlagenKurz => 'Failed';

  @override
  String get zweitOrdnerWaehlen =>
      'Choose the folder of the second PhotoVault library';

  @override
  String get zweitTitel => 'Compare against a second library';

  @override
  String get allgErneutVersuchen => 'Try again';

  @override
  String get zweitErklaerung =>
      'Compares your own library against a second, independent PhotoVault library – on an external drive or an old machine, say – by AI image similarity, and finds photos that are already there before you import them again.\n\nLocked photos in the second library are never included, and its PIN is never needed.';

  @override
  String get zweitOrdnerKnopf => 'Choose the second library\'s folder';

  @override
  String get zweitSchwelleHinweis =>
      'Higher values mean only very similar photos count as a match.';

  @override
  String get zweitKeineTreffer =>
      'No similar photos found in the second library.';

  @override
  String zweitTreffer(int anzahl) {
    return '$anzahl possible match(es)';
  }

  @override
  String get zweitAndererOrdner => 'A different folder';

  @override
  String zweitAehnlichProzent(String prozent) {
    return '$prozent % similar';
  }

  @override
  String get zweitBibliothek => 'second library';

  @override
  String get aehnlTitel => 'Similar photos';

  @override
  String get aehnlClipFehlt =>
      'AI image search is unavailable – the CLIP model is missing (see Settings → AI models).';

  @override
  String get aehnlKeineTreffer =>
      'There is no AI embedding for this photo yet (see Tools → AI image search → Compute CLIP embeddings), or there are no similar photos in the library.';

  @override
  String get stapelErklaerung =>
      'Photos that look alike AND were taken within a few seconds of each other are suggested here as a series. \"Apply\" collapses a group into one stack – only the cover image stays visible in the overview, and nothing is deleted.';

  @override
  String stapelAlleUebernehmen(int anzahl) {
    return 'Accept all $anzahl';
  }

  @override
  String get stapelAlleFrageTitel => 'Accept all series?';

  @override
  String stapelAlleFrage(int anzahl) {
    return '$anzahl groups will be combined into stacks. The sharpest photo becomes the cover. Nothing is lost – “Ungroup series” in the info sheet undoes any grouping.';
  }

  @override
  String werkzStapelGefunden(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl series are waiting',
      one: '1 series is waiting',
      zero: 'No series found',
    );
    return '$_temp0';
  }

  @override
  String get serienvergleichTitel => 'Compare series';

  @override
  String get serienvergleichErklaerung =>
      'The same faces side by side. On a whole photo you cannot see who blinked – on the crops you can, at once. The frame marks the shot with the sharpest face; that is a suggestion, not a decision.';

  @override
  String get serienvergleichOhneGesichter =>
      'No face was detected in these shots – only the images themselves are compared.';

  @override
  String get serienvergleichSchaerfstes => 'Sharpest face of the series';

  @override
  String serienvergleichSchaerfe(int wert) {
    return 'Sharpness $wert';
  }

  @override
  String serienvergleichAugen(int prozent) {
    return 'Eyes open: $prozent %';
  }

  @override
  String get serienvergleichOhneWert => 'Sharpness not measured yet';

  @override
  String get serienvergleichOeffnen => 'Compare faces';

  @override
  String get serienvergleichZuKurz => 'Comparing needs at least two shots.';

  @override
  String get stapelKeine => 'No burst series found.';

  @override
  String get allgVerwerfen => 'Discard';

  @override
  String get statTitel => 'Statistics';

  @override
  String get allgAktualisieren => 'Refresh';

  @override
  String get statLeer => 'No photos or videos in the library yet.';

  @override
  String get statProJahr => 'Photos & videos per year';

  @override
  String get statSaisonalitaet => 'Seasonality – shots per month';

  @override
  String get statKameras => 'Most-used cameras';

  @override
  String get statInsgesamt => 'Items in total';

  @override
  String get statFotos => 'Photos';

  @override
  String get statVideos => 'Videos';

  @override
  String get statSpeicherplatz => 'Disk space';

  @override
  String get statImPapierkorb => 'In the trash';

  @override
  String statDiagrammJahr(String werte) {
    return 'Bar chart, photos and videos per year: $werte';
  }

  @override
  String statDiagrammMonat(String werte) {
    return 'Bar chart, seasonality per month: $werte';
  }

  @override
  String get papierkorbTitel => 'Trash';

  @override
  String get papierkorbEndgueltigTitel => 'Delete permanently?';

  @override
  String papierkorbEndgueltigText(int anzahl) {
    return 'Delete $anzahl file(s) for good.';
  }

  @override
  String papierkorbAnzahl(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl photos',
      one: 'one photo',
    );
    return '$_temp0';
  }

  @override
  String papierkorbUmfang(int anzahl, String platz) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl photos',
      one: 'one photo',
    );
    return '$_temp0 · $platz';
  }

  @override
  String get papierkorbLeer => 'The trash is empty.';

  @override
  String get videoNichtGeoeffnet => 'The video could not be opened.';

  @override
  String get videoZuschneidenFehler => 'Trimming failed.';

  @override
  String get videoZuschneiden => 'Trim';

  @override
  String get xmpAlleUebernehmen => 'Apply all';

  @override
  String get xmpErneutEinlesen => 'Read again';

  @override
  String xmpKeineAbweichungen(int anzahl) {
    return '$anzahl sidecar(s) checked – no differences from the database found.';
  }

  @override
  String get restaurWirdGestartet => 'Starting …';

  @override
  String get restaurAbgebrochen => 'Cancelled';

  @override
  String get restaurGrundModellLaedtNicht =>
      'The restoration model could not be loaded.';

  @override
  String get restaurGrundModellWeg => 'The model is no longer available.';

  @override
  String get restaurGrundFotoWeg =>
      'The photo has been deleted in the meantime.';

  @override
  String get restaurGrundGesperrt =>
      'AI restoration is not available for locked photos.';

  @override
  String get restaurGrundAufloesung => 'Image resolution unknown.';

  @override
  String get restaurGrundNichtGerendert => 'The image could not be rendered.';

  @override
  String get restaurGrundNichtDekodiert =>
      'The rendered image could not be decoded.';

  @override
  String get restaurNichtVerfuegbar =>
      'AI restoration is not available – the model is not installed.';

  @override
  String personSchwelleWieAllgemein(String allgemein) {
    return 'still $allgemein';
  }

  @override
  String personWiedererkennung(
      String erklaerung, int bestaetigt, int abgelehnt) {
    String _temp0 = intl.Intl.pluralLogic(
      bestaetigt,
      locale: localeName,
      other: '$bestaetigt confirmations',
      one: 'one confirmation',
    );
    String _temp1 = intl.Intl.pluralLogic(
      abgelehnt,
      locale: localeName,
      other: '$abgelehnt corrections',
      one: 'one correction',
    );
    return 'Recognition: $erklaerung. From $_temp0 and $_temp1.';
  }

  @override
  String get infoKeineUnbenannten =>
      'No unnamed faces found on this photo – if face detection has not run yet, see Tools → Scan for faces.';

  @override
  String get infoTitel => 'Info';

  @override
  String get infoVideoStandbild =>
      'Analysed on a single frame from the first second – not on the whole clip.';

  @override
  String get infoBeschreibungHinzufuegen => 'Add a description';

  @override
  String get infoKiBeschreibung => 'AI caption';

  @override
  String get infoErkannterText => 'Recognised text';

  @override
  String get infoTextKopieren => 'Copy text';

  @override
  String get infoTextKopiert => 'Text copied to the clipboard';

  @override
  String infoTextStellen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl text areas in the photo',
      one: '1 text area in the photo',
    );
    return '$_temp0';
  }

  @override
  String get infoBewertung => 'Rating';

  @override
  String get infoNiemandZugeordnet => 'Nobody assigned yet.';

  @override
  String get infoDetails => 'Details';

  @override
  String get infoStandortBekannt => 'Location known';

  @override
  String get infoOrtNichtAufgeloest =>
      'Location not resolved yet (Tools → Locations)';

  @override
  String get infoOrtEntfernen => 'Clear the location';

  @override
  String get infoBearbeitet => 'Edited';

  @override
  String get infoBearbeitetEntwickelt => 'developed';

  @override
  String get infoBearbeitetRestauriert => 'restored';

  @override
  String get infoBearbeitetZugeschnitten => 'trimmed';

  @override
  String infoOriginalUnberuehrt(String arten) {
    return '$arten – the original file is unchanged';
  }

  @override
  String get infoOriginalHerstellen => 'Restore original';

  @override
  String get infoOriginalHerstellenFrage =>
      'Undo every edit on this photo? The derived files are deleted; the original stays as it is.';

  @override
  String get infoOriginalHergestellt => 'Original restored.';

  @override
  String infoSerie(int anzahl) {
    return 'Series: $anzahl photos';
  }

  @override
  String get infoNurTitelbild =>
      'Only the cover image is visible in the overview';

  @override
  String get infoSerieAufloesen => 'Break up the series';

  @override
  String get infoTagHinzufuegenPlatzhalter => 'Add a tag …';

  @override
  String get stufeBildanalyse => 'Image analysis';

  @override
  String get stufeTexterkennung => 'Text recognition';

  @override
  String get stufeSchlagwoerter => 'Tags';

  @override
  String get stufeBildbeschreibung => 'Captions';

  @override
  String get aktualisierungKeineVeroeffentlichungen => 'No releases found.';

  @override
  String get aktualisierungKeineVersion => 'No version number in the response.';

  @override
  String backupGrenzeErreicht(int anzahl) {
    return 'Limit reached – $anzahl file(s) follow on the next run';
  }

  @override
  String backupUebernommen(int anzahl) {
    return '$anzahl entries taken from the database snapshot (people, family tree, trips, activities …)';
  }

  @override
  String get backupAusschnitteNeu => 'Redrawing face crops …';

  @override
  String get einstBackupManuellHinweis =>
      'A backup with a passphrase also carries an encrypted snapshot of the database – people, family tree, trips, activities and saved searches come back when you restore. Without a passphrase the backup holds only the originals and the sidecars beside them (description, stars, colour label, location, tags, albums); everything else could not be restored afterwards.';

  @override
  String backupNichtGesichert(int anzahl) {
    return '$anzahl file(s) could not be backed up – they will be retried on the next run';
  }

  @override
  String get backupPassphraseNoetig =>
      'This backup is encrypted – a passphrase is needed.';

  @override
  String get backupOrdnerFehlt =>
      'The selected folder does not contain a backup.';

  @override
  String downloadPruefsummeFehler(
      String datei, String erhalten, String erwartet) {
    return 'The checksum of $datei does not match the expected SHA-256 (got $erhalten, expected $erwartet) – the download was discarded. The file on the server may have changed, or it was altered in transit.';
  }

  @override
  String downloadFehlgeschlagen(String datei, String fehler) {
    return 'Downloading $datei failed: $fehler';
  }

  @override
  String downloadEntpackenFehler(String datei, String fehler) {
    return 'Unpacking $datei failed: $fehler';
  }

  @override
  String downloadNichtImZip(String datei) {
    return '$datei was not found in the zip.';
  }

  @override
  String get regelAusloeserOrt => 'Location (radius)';

  @override
  String get regelAusloeserTag => 'AI tag';

  @override
  String get regelAusloeserDatum => 'Date range';

  @override
  String regelUmkreisUm(String km, String breite, String laenge) {
    return 'Within $km km of $breite, $laenge';
  }

  @override
  String regelTagWert(String begriff) {
    return 'AI tag: $begriff';
  }

  @override
  String regelDatumBereich(String von, String bis) {
    return '$von – $bis';
  }

  @override
  String regelUmkreis(String km) {
    return 'Radius: $km km';
  }

  @override
  String regelAlbumTeil(String name) {
    return 'Album: $name';
  }

  @override
  String regelTagsTeil(String namen) {
    return 'Tags: $namen';
  }

  @override
  String duplGruppe(int nummer, int anzahl) {
    return 'Group $nummer · $anzahl photos';
  }

  @override
  String stapelSerie(int nummer, int anzahl) {
    return 'Series $nummer · $anzahl photos';
  }

  @override
  String clusterGesichterZuordnen(int anzahl) {
    return 'Assign $anzahl faces';
  }

  @override
  String clusterGesichterAnzahl(int anzahl) {
    return '$anzahl faces';
  }

  @override
  String gesichtEmbeddingFehler(String fehler) {
    return 'The recognition embedding failed: $fehler';
  }

  @override
  String bearbSpeichernFehler(String fehler) {
    return 'Saving failed: $fehler';
  }

  @override
  String integFehlendeDateien(int anzahl) {
    return 'Missing files ($anzahl)';
  }

  @override
  String integVerwaisteDateien(int anzahl) {
    return 'Orphaned files ($anzahl)';
  }

  @override
  String get viewerKugelSchwenken => '3D sphere instead of flat panning';

  @override
  String get regelNeuTitel => 'New automation rule';

  @override
  String get regelBearbeitenTitel => 'Edit rule';

  @override
  String presetZeileAlbum(String album) {
    return 'Album: $album';
  }

  @override
  String presetZeileTags(String tags) {
    return 'Tags: $tags';
  }

  @override
  String get presetKeineAktion => 'No action configured';

  @override
  String get presetNeuTitel => 'New camera preset';

  @override
  String get presetBearbeitenTitel => 'Edit camera preset';

  @override
  String allgSucheFehlgeschlagen(String fehler) {
    return 'Search failed: $fehler';
  }

  @override
  String get allgUnbekannterFehler => 'Unknown error';

  @override
  String erkundenVorJahren(int jahre) {
    String _temp0 = intl.Intl.pluralLogic(
      jahre,
      locale: localeName,
      other: '$jahre years ago',
      one: '1 year ago',
    );
    return '$_temp0';
  }

  @override
  String erkundenImMonatVorJahren(String monat, int jahre) {
    return 'In $monat, $jahre years ago';
  }

  @override
  String get gesichtBenennen => 'Name face';

  @override
  String get gesichtUnbenannt => 'Unnamed';

  @override
  String get bearbZuschneiden => 'Crop';

  @override
  String get bearbLinksDrehen => 'Rotate left';

  @override
  String get bearbRechtsDrehen => 'Rotate right';

  @override
  String get bearbHorizontalSpiegeln => 'Flip horizontally';

  @override
  String get bearbVertikalSpiegeln => 'Flip vertically';

  @override
  String get integAusDbEntfernenTitel => 'Remove from database?';

  @override
  String get integArtOriginal => 'Original';

  @override
  String get integArtThumbnail => 'Thumbnail';

  @override
  String get integArtVorschau => 'Preview';

  @override
  String get integArtEntwickelt => 'Developed image';

  @override
  String get integArtRestauriert => 'AI-restored image';

  @override
  String get integArtVideoZuschnitt => 'Trimmed video';

  @override
  String get integArtGesichtsCrop => 'Face crop';

  @override
  String get integArtMaske => 'AI mask';

  @override
  String get integAlleVerwaistenLoeschen => 'Delete all';

  @override
  String get integAlleVerwaistenTitel => 'Delete all orphaned files?';

  @override
  String integAlleVerwaistenText(int anzahl, String groesse) {
    return '$anzahl files totalling $groesse will be permanently deleted from disk. No database row refers to them, so the library loses nothing it could have shown.';
  }

  @override
  String integVerwaisteGeloescht(int anzahl) {
    return 'Deleted $anzahl orphaned files.';
  }

  @override
  String integWeitereEintraege(int anzahl, int gezeigt) {
    return '… and $anzahl more. The list shows only the first $gezeigt; “Delete all” clears the rest too.';
  }

  @override
  String get gesperrtTabFotos => 'Photos';

  @override
  String get gesperrtTabPapierkorb => 'Trash';

  @override
  String get karteHell => 'Light';

  @override
  String get karteDunkel => 'Dark';

  @override
  String get karteTopografie => 'Topographic';

  @override
  String get karteGlobus => 'Globe';

  @override
  String zweitVergleichFehlgeschlagen(String fehler) {
    return 'Comparison failed: $fehler';
  }

  @override
  String xmpEinlesenFehlgeschlagen(String fehler) {
    return 'Reading failed: $fehler';
  }

  @override
  String get xmpFeldBewertung => 'Rating';

  @override
  String get xmpFeldFarbmarkierung => 'Colour label';

  @override
  String get xmpFeldBeschreibung => 'Description';

  @override
  String get xmpFeldNeueTags => 'New tags';

  @override
  String get xmpFeldStandort => 'Location';

  @override
  String get xmpFeldGesichter => 'Names for recognised faces';

  @override
  String xmpGesichterOhneNamen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl faces without a name',
      one: '1 face without a name',
    );
    return '$_temp0';
  }

  @override
  String get xmpKeineSidecars => 'No XMP sidecars found.';

  @override
  String get liveWiedergabeStoppen => 'Stop playback';

  @override
  String get liveDauerschleife => 'Play on a loop';

  @override
  String get metaHersteller => 'Camera make';

  @override
  String get metaModell => 'Camera model';

  @override
  String get metaObjektiv => 'Lens';

  @override
  String get metaBrennweite => 'Focal length (mm)';

  @override
  String get metaBlende => 'Aperture (f/…)';

  @override
  String get metaBelichtungszeit => 'Shutter speed';

  @override
  String get passphraseZuKurz =>
      'The passphrase must be at least 8 characters long.';

  @override
  String get exportVorgabenTitel => 'Export presets';

  @override
  String get exportVorgabenLeer =>
      'No presets yet. A preset remembers size, quality and file naming – for everything you export more than once.';

  @override
  String get exportVorgabeNeu => 'New preset';

  @override
  String get exportVorgabeNeuTitel => 'New export preset';

  @override
  String get exportVorgabeBearbeitenTitel => 'Edit preset';

  @override
  String get exportVorgabeName => 'Name';

  @override
  String get exportVorgabeNameNoetig => 'Please give the preset a name.';

  @override
  String get exportVorgabeNachJpeg => 'Render to JPEG';

  @override
  String get exportVorgabeNachJpegHinweis =>
      'Without this the file is copied unchanged – the only way that leaves RAW files and videos untouched.';

  @override
  String get exportVorgabeKante => 'Longer edge (pixels)';

  @override
  String get exportVorgabeKanteLeer => 'empty = full resolution';

  @override
  String get exportVorgabeKanteUngueltig =>
      'The edge length must be between 64 and 20000.';

  @override
  String exportVorgabeQualitaet(int prozent) {
    return 'JPEG quality: $prozent%';
  }

  @override
  String get exportVorgabeMuster => 'File name pattern';

  @override
  String get exportVorgabeMusterNoetig =>
      'The file name pattern must not be empty.';

  @override
  String get exportVorgabeMusterHinweis =>
      'The extension is always added automatically. The running number counts within one export run and is padded to four digits.';

  @override
  String get exportVorgabeXmp => 'Write an XMP sidecar';

  @override
  String get exportVorgabeXmpHinweis =>
      'Rating, keywords and location for other programs – as a separate file next to the photo.';

  @override
  String exportVorgabeJpegVoll(int prozent) {
    return 'JPEG, full resolution, $prozent%';
  }

  @override
  String exportVorgabeJpegKante(int kante, int prozent) {
    return 'JPEG, longer edge $kante px, $prozent%';
  }

  @override
  String get exportVorgabeOhneXmp => 'no XMP';

  @override
  String get exportVorgabeLoeschenTitel => 'Delete preset?';

  @override
  String exportVorgabeLoeschenText(String name) {
    return '“$name” will be removed. Files you have already exported are not affected.';
  }

  @override
  String get exportEigeneVorgaben => 'Your presets';

  @override
  String get exportVorgabenVerwalten => 'Manage presets …';

  @override
  String get werkzExportVorgabenTitel => 'Export presets';

  @override
  String get werkzExportVorgabenText =>
      'Named output settings for exporting: size, JPEG quality, file naming and whether an XMP sidecar is written.';

  @override
  String get exportVorgabeNameVergeben => 'That name is already taken.';

  @override
  String get entwObjektivkorrekturKeinRaw =>
      'Not a RAW file – the camera has already corrected distortion and vignetting.';

  @override
  String get entwObjektivkorrekturVerfuegbar =>
      'Camera and lens are known: distortion and vignetting are corrected.';

  @override
  String get entwObjektivkorrekturUnbekanntesObjektiv =>
      'There is no profile for this camera. With ProRAW that is no loss – the correction is already baked into the file.';

  @override
  String get entwObjektivkorrekturNichtLesbar =>
      'The RAW data in this file cannot be opened. The other sliders therefore only affect the embedded preview.';

  @override
  String get einstSuche => 'Search settings';

  @override
  String get einstNichtsGefunden => 'No setting matches that search.';

  @override
  String get einstBeschrErscheinungsbild => 'Light, dark, or follow the system';

  @override
  String get einstBeschrSprache =>
      'Language of the interface and of the keywords';

  @override
  String get einstBeschrUeberwacht =>
      'Folders that new photos come in from on their own';

  @override
  String get einstBeschrBibliotheken => 'Switch between several libraries';

  @override
  String get einstBeschrSpeicherort =>
      'Where the library lives and how much room it takes';

  @override
  String get einstBeschrModelle => 'Download and remove the local models';

  @override
  String get einstBeschrHintergrund =>
      'Whether analysis starts automatically after an import';

  @override
  String get einstBeschrVokabular => 'The terms photos are tagged with';

  @override
  String get einstAbschnittKarte => 'Map';

  @override
  String get einstBeschrKarte => 'Tile source for the dark map';

  @override
  String get einstKartenNetzHinweis =>
      'The map fetches its tiles as you look at it – from OpenStreetMap, OpenTopoMap, Esri and, for terrain, AWS Open Data. Those servers learn which section you are viewing, and with it roughly where your photographs were taken. Without the map nothing of this leaves the machine: country, region and town for a GPS position are looked up in the downloaded place directory.';

  @override
  String get einstCartoText =>
      'By default the dark map draws recoloured OpenStreetMap tiles – no sign-up, no key. For CARTO\'s finer cartography, enter a key here.';

  @override
  String get einstCartoAktiv => 'CARTO Dark Matter, up to zoom level 20.';

  @override
  String get einstCartoOhne =>
      'Recoloured OpenStreetMap tiles, up to zoom level 19.';

  @override
  String get einstCartoFeld => 'CARTO key';

  @override
  String get einstCartoFeldHinweis => 'Leave empty for OpenStreetMap';

  @override
  String get einstCartoQuelle =>
      'Free and without an account at carto.com/basemaps/apikey. CARTO states its raster tiles are being retired – without a key the map is unaffected.';

  @override
  String get einstCartoGespeichert => 'CARTO key saved';

  @override
  String get einstCartoEntfernt =>
      'CARTO key removed – the map uses OpenStreetMap again';

  @override
  String get einstBeschrStandortdaten =>
      'Place names for GPS coordinates, offline';

  @override
  String get einstBeschrGesperrt => 'PIN, encryption and what is kept inside';

  @override
  String get einstBeschrBackupSchluessel => 'Passphrase for encrypted backups';

  @override
  String get einstBeschrBackupManuell => 'Start a backup by hand';

  @override
  String get einstBeschrBackupAuto =>
      'Back up regularly without having to think about it';

  @override
  String get einstBeschrPapierkorb =>
      'View deleted photos, restore them, remove them for good';

  @override
  String get einstBeschrGefahr => 'Steps that cannot be undone';

  @override
  String get einstBeschrUeber => 'Version, licences and updates';

  @override
  String get allgRueckgaengig => 'Undo';

  @override
  String get personenIgnoriertTab => 'Ignored';

  @override
  String tabMitZahl(String beschriftung, int anzahl) {
    return '$beschriftung ($anzahl)';
  }

  @override
  String get personenIgnorierenTooltip => 'Ignore selected faces';

  @override
  String personenZugeordnetMeldung(int anzahl, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl faces assigned to “$name”.',
      one: 'One face assigned to “$name”.',
    );
    return '$_temp0';
  }

  @override
  String personenIgnoriertMeldung(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl faces ignored.',
      one: 'One face ignored.',
    );
    return '$_temp0';
  }

  @override
  String get personenIgnoriertLeer =>
      'No ignored faces. Whatever you set aside under “Unnamed faces” – posters, reflections, statues – collects here and can be brought back at any time.';

  @override
  String get personenIgnoriertHinweis =>
      'Ignored faces no longer appear in the grid and are left out of grouping. Double-click opens the whole photo.';

  @override
  String personenIgnoriertTeilHinweis(int gezeigt, int gesamt) {
    return '$gezeigt of $gesamt ignored faces. Double-click opens the whole photo.';
  }

  @override
  String personenZurueckholenKnopf(int anzahl) {
    return 'Bring back $anzahl';
  }

  @override
  String get clusterPhaseLaden => 'Loading faces …';

  @override
  String get clusterPhaseVergleichen => 'Comparing faces …';

  @override
  String get clusterPhaseVorschlaege => 'Preparing suggestions …';

  @override
  String get clusterOhneProzent => 'Working …';

  @override
  String clusterFehlgeschlagen(String fehler) {
    return 'Automatic grouping failed: $fehler';
  }

  @override
  String get clusterIgnorierenTooltip => 'Ignore the whole group';

  @override
  String get gesichtIgnorieren => 'Ignore';

  @override
  String get gesichtIgnoriert => 'Ignored';

  @override
  String get gesichtZurueckgeholt => 'This face counts again.';

  @override
  String gesichtPosition(int nummer, int gesamt) {
    return '$nummer of $gesamt';
  }

  @override
  String get gesichtVoriges => 'Previous photo (left arrow)';

  @override
  String get gesichtNaechstes => 'Next photo (right arrow)';

  @override
  String get clusterUnerwartetBeendet =>
      'Automatic grouping ended unexpectedly.';

  @override
  String get aufgAktiv => 'Active';

  @override
  String aufgStufeKurz(int nummer, int gesamt) {
    return 'Step $nummer/$gesamt';
  }

  @override
  String get personenAlleIgnorieren => 'Ignore all unnamed faces';

  @override
  String personenAlleIgnorierenHinweis(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl faces move to “Ignored”',
      one: 'One face moves to “Ignored”',
      zero: 'Nothing left',
    );
    return '$_temp0';
  }

  @override
  String personenAlleIgnoriertMeldung(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other:
          '$anzahl faces ignored. Bring individual ones back under “Ignored”.',
      one: 'One face ignored. Bring individual ones back under “Ignored”.',
      zero: 'There was nothing to ignore.',
    );
    return '$_temp0';
  }

  @override
  String get personenAlleErkennungenLoeschen => 'Delete all unnamed detections';

  @override
  String get personenAlleErkennungenLoeschenHinweis =>
      'Frees space, but comes back on the next scan';

  @override
  String get personenErkennungenLoeschenTitel =>
      'Really delete the detections?';

  @override
  String get personenErkennungenLoeschenText =>
      'All unnamed detections and their crops are deleted from disk – including the ones already ignored. Named people are left untouched.\n\nThis is not permanent: the next face scan finds the same spots again. To be rid of them for good, use “Ignore all unnamed faces” instead – that survives another scan.';

  @override
  String personenErkennungenGeloeschtMeldung(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl detections deleted.',
      one: 'One detection deleted.',
      zero: 'There were no detections to delete.',
    );
    return '$_temp0';
  }

  @override
  String get gesichtZuordnungLoesen => 'Remove assignment';

  @override
  String get gesichtNichtMehrIgnorieren => 'Stop ignoring';

  @override
  String get gesichtFotoLoeschen => 'Delete photo';

  @override
  String get zeitraumName => 'Name';

  @override
  String get zeitraumArt => 'Kind';

  @override
  String get zeitraumZaehlt => 'Counting photos …';

  @override
  String zeitraumFotos(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n photos in this period',
      one: '1 photo in this period',
      zero: 'No photo in this period',
    );
    return '$_temp0';
  }

  @override
  String get reisenSelbstAnlegen => 'Add a trip by hand';

  @override
  String reisenSelbstAngelegt(String name) {
    return 'Trip \"$name\" created.';
  }

  @override
  String get aktivitaetenSelbstAnlegen => 'Add an activity by hand';

  @override
  String aktivitaetenSelbstAngelegt(String name) {
    return 'Activity \"$name\" created.';
  }

  @override
  String get infoOrtSuchen => 'Find place';

  @override
  String get infoOrtSuchenBeispiel => 'e.g. Goslar';

  @override
  String get infoOrtKeinVerzeichnis =>
      'The place directory is missing. You can download it under Settings → Location data.';

  @override
  String infoOrtNichtGefunden(String name) {
    return 'No place called \"$name\" in the directory.';
  }

  @override
  String infoOrtGesetzt(String ort) {
    return 'Location set to $ort.';
  }

  @override
  String infoOrtGesetztMehrdeutig(String ort, int weitere) {
    return 'Location set to $ort - there are $weitere more of the same name.';
  }

  @override
  String get gesichtNichtMehrDurchsuchen => 'Stop scanning for faces';

  @override
  String get gesichtWiederDurchsuchen => 'Scan for faces again';

  @override
  String get gesichtNichtMehrDurchsuchtHinweis =>
      'This photo will be skipped when scanning again. Faces already found remain.';

  @override
  String get gesichtWiederDurchsuchtHinweis =>
      'This photo will be scanned again.';

  @override
  String get gesichtInGesperrtemOrdner =>
      'The photo is now in the locked folder.';

  @override
  String get gesichtFavoritGesetzt => 'Marked as favourite.';

  @override
  String get gesichtFavoritEntfernt => 'Favourite removed.';

  @override
  String get gesichtSperrenFehlgeschlagen =>
      'The photo could not be moved to the locked folder.';

  @override
  String get gesichtErkennungLoeschen => 'Delete detection';

  @override
  String gesichtAlleUnbenanntenIgnorieren(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: 'Ignore $anzahl unnamed faces',
      one: 'Ignore unnamed face',
      zero: 'No unnamed faces',
    );
    return '$_temp0';
  }

  @override
  String get personWeitereFotosSuchen => 'Find more photos';

  @override
  String vorschlagTitel(String name) {
    return 'Suggestions for $name';
  }

  @override
  String get vorschlagHinweis =>
      'Everything is selected. Take out what is wrong – the recognition learns from that too: a rejection raises this person\'s threshold.';

  @override
  String get vorschlagAlleWaehlen => 'Select all';

  @override
  String get vorschlagKeineWaehlen => 'Select none';

  @override
  String vorschlagUebernehmen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: 'Assign $anzahl faces',
      one: 'Assign one face',
      zero: 'Nothing selected',
    );
    return '$_temp0';
  }

  @override
  String vorschlagUebernommenMeldung(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl photos added.',
      one: 'One photo added.',
      zero: 'Nothing taken over – the feedback was still saved.',
    );
    return '$_temp0';
  }

  @override
  String get vorschlagKeineEmbeddings =>
      'There is no recognition data for this person yet. It is created during the face scan once the SFace model is installed.';

  @override
  String get vorschlagKeineKandidaten =>
      'There are no unnamed faces that could be suggested.';

  @override
  String vorschlagNichtsGefunden(String schwelle) {
    return 'No unnamed face is above this person\'s threshold of $schwelle.';
  }

  @override
  String get gesichtRahmenAusblenden => 'Hide boxes';

  @override
  String get gesichtRahmenEinblenden => 'Show boxes';

  @override
  String get entwKlarheit => 'Clarity';

  @override
  String get entwVignettierung => 'Vignette';

  @override
  String get entwLutKeine => 'No colour table';

  @override
  String get entwLutWaehlen => 'Choose colour table (.cube)';

  @override
  String get entwLutEntfernen => 'Remove colour table';

  @override
  String get entwLutStaerke => 'Strength';

  @override
  String entwLutFehlt(String name) {
    return 'The colour table “$name” can no longer be read and was removed.';
  }

  @override
  String entwLutNichtLesbar(String fehler) {
    return 'The file cannot be read: $fehler';
  }

  @override
  String get entwLutEindimensional =>
      'This is a one-dimensional table – it describes a curve, not a colour space. Use the tone curve for that.';

  @override
  String get entwLutOhneGroesse => 'The file is missing the LUT_3D_SIZE entry.';

  @override
  String entwLutGroesse(int zeile) {
    return 'The edge length in line $zeile is outside the allowed range (2 to 256).';
  }

  @override
  String get entwLutZeilenzahl =>
      'The file does not contain as many values as its edge length requires.';

  @override
  String entwLutZeile(int zeile) {
    return 'Line $zeile cannot be read.';
  }

  @override
  String get histogrammWaveform => 'Waveform';

  @override
  String get histogrammParade => 'Parade';

  @override
  String get entwFormRechteck => 'Rectangle';

  @override
  String get entwFormFarbe => 'Colour';

  @override
  String get entwRechteckHinweis =>
      'Drag out a rectangle. Rotation and soft edge are set below.';

  @override
  String get entwFarbauswahlHinweis =>
      'Tap a colour in the photo. Everything close enough to it is selected – lighter and darker too, because colour counts for more than brightness.';

  @override
  String entwFarbeAufgenommen(int rot, int gruen, int blau) {
    return 'R $rot · G $gruen · B $blau';
  }

  @override
  String get entwToleranz => 'Tolerance';

  @override
  String get vergleichTitel => 'Compare two photos';

  @override
  String get vergleichNebeneinander => 'Side by side';

  @override
  String get vergleichUebereinander => 'Stacked';

  @override
  String get vergleichKoppeln => 'Link views';

  @override
  String get vergleichEntkoppeln => 'Unlink views';

  @override
  String get vergleichZuruecksetzen => 'Reset zoom';

  @override
  String get auswVergleichen => 'Compare the two selected photos';

  @override
  String get listeOhneKamera => 'No camera information';

  @override
  String get zeitleisteGroesser => 'Larger tiles';

  @override
  String get zeitleisteKleiner => 'Smaller tiles – more months at once';

  @override
  String get zeitleisteFormReihen =>
      'Justified rows – every photo in its own shape';

  @override
  String get zeitleisteFormQuadrate => 'Square grid';

  @override
  String get listeSpalten => 'Columns';

  @override
  String get listeSpalteDateiname => 'File name';

  @override
  String get listeSpalteDatum => 'Taken';

  @override
  String get listeSpalteKamera => 'Camera';

  @override
  String get listeSpalteObjektiv => 'Lens';

  @override
  String get listeSpalteBelichtung => 'Exposure';

  @override
  String get listeSpalteBewertung => 'Rating';

  @override
  String get listeSpalteFarbe => 'Colour';

  @override
  String get listeSpalteMasse => 'Dimensions';

  @override
  String get listeSpalteGroesse => 'File size';

  @override
  String get listeSpalteArt => 'Kind';

  @override
  String get listeSpalteOrt => 'Place';

  @override
  String get listeSpalteBreiteAendern => 'Change width';

  @override
  String get ansichtRaster => 'Grid';

  @override
  String get ansichtListe => 'List';

  @override
  String get gruppeMonat => 'By month';

  @override
  String get gruppeKamera => 'By camera';

  @override
  String get gruppeKeine => 'No grouping';

  @override
  String get sortReihenfolge => 'Sort order';

  @override
  String get sortAufnahmeNeu => 'Date taken, newest first';

  @override
  String get sortAufnahmeAlt => 'Date taken, oldest first';

  @override
  String get sortImportNeu => 'Recently added';

  @override
  String get sortName => 'File name, A–Z';

  @override
  String get sortBewertung => 'Rating, best first';

  @override
  String get sortGroesse => 'File size, largest first';

  @override
  String get sortFundreihenfolge => 'Match order';

  @override
  String get bearbGeradeziehen => 'Straighten';

  @override
  String get bearbPerspektive => 'Perspective';

  @override
  String get bearbPerspektiveAnwenden => 'Correct';

  @override
  String get modellLamaTitel => 'Object removal (LaMa)';

  @override
  String get modellLamaText =>
      'Fills a marked area from its surroundings – for dust spots, passers-by or the bin at the edge of the frame. At 208 MB the largest model here; one pass takes about a second.';

  @override
  String get modellLamaLizenz =>
      'Apache 2.0 (Samsung Research), ONNX export by Carve';

  @override
  String get bearbRetusche => 'Remove object';

  @override
  String get aufgLamaModell => 'the LaMa model';

  @override
  String get bearbRetuscheNichtsMarkiert =>
      'Nothing marked – paint over whatever should disappear.';

  @override
  String get bearbRetuscheAnwenden => 'Remove';

  @override
  String get bearbRetuscheZurueck => 'Undo last stroke';

  @override
  String get bearbPinselbreite => 'Brush width';

  @override
  String bearbRetuscheFehler(String fehler) {
    return 'Removal failed: $fehler';
  }

  @override
  String get stammbaumTitel => 'Family tree';

  @override
  String stammbaumTitelVon(String name) {
    return 'Family tree: $name';
  }

  @override
  String get stammbaumElternteilHinzufuegen => 'Add parent';

  @override
  String get stammbaumPartnerHinzufuegen => 'Add partner';

  @override
  String get stammbaumKindHinzufuegen => 'Add child';

  @override
  String get stammbaumInDieMitte => 'Move to centre';

  @override
  String get stammbaumLebensdaten => 'Life dates …';

  @override
  String get stammbaumFotosZeigen => 'Photos of this person';

  @override
  String get stammbaumVerbindungEntfernen => 'Remove connection';

  @override
  String stammbaumVerbindungEntfernenFrage(String eine, String andere) {
    return 'The relationship between $eine and $andere will be removed. Both people and their photos stay.';
  }

  @override
  String get stammbaumFehlerSelbst =>
      'A person cannot be related to themselves.';

  @override
  String get stammbaumFehlerKreis =>
      'That would run in a circle: this person already appears further down the same branch.';

  @override
  String get stammbaumFehlerVorhanden =>
      'This relationship is already recorded.';

  @override
  String stammbaumZuVieleHaushalte(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl more households do not fit the picture.',
      one: 'One more household does not fit the picture.',
    );
    return '$_temp0';
  }

  @override
  String get stammbaumLeer =>
      'No relatives recorded for this person yet. Use the buttons at the top right to add parents, a partner or children – either from the people you have already named, or as a new name, even without a single photo.';

  @override
  String get stammbaumPersonFehlt => 'This person no longer exists.';

  @override
  String get stammbaumGeboren => 'Born';

  @override
  String get stammbaumGestorben => 'Died';

  @override
  String get stammbaumUnbekannt => 'unknown';

  @override
  String get stammbaumNurJahrHinweis =>
      'If only the year is known, pick any day within it – only the year is shown anyway.';

  @override
  String get gradSelbst => 'this person';

  @override
  String gradEltern(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Mother',
        'm': 'Father',
        'other': 'Parent',
      },
    );
    return '$_temp0';
  }

  @override
  String gradGrosseltern(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Grandmother',
        'm': 'Grandfather',
        'other': 'Grandparent',
      },
    );
    return '$_temp0';
  }

  @override
  String gradUrgrosseltern(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Great-grandmother',
        'm': 'Great-grandfather',
        'other': 'Great-grandparent',
      },
    );
    return '$_temp0';
  }

  @override
  String gradUrurgrosseltern(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Great-great-grandmother',
        'm': 'Great-great-grandfather',
        'other': 'Great-great-grandparent',
      },
    );
    return '$_temp0';
  }

  @override
  String gradVorfahreN(int stufe) {
    return 'Ancestor, $stufe generations up';
  }

  @override
  String gradKind(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Daughter',
        'm': 'Son',
        'other': 'Child',
      },
    );
    return '$_temp0';
  }

  @override
  String gradEnkel(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Granddaughter',
        'm': 'Grandson',
        'other': 'Grandchild',
      },
    );
    return '$_temp0';
  }

  @override
  String gradUrenkel(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Great-granddaughter',
        'm': 'Great-grandson',
        'other': 'Great-grandchild',
      },
    );
    return '$_temp0';
  }

  @override
  String gradUrurenkel(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Great-great-granddaughter',
        'm': 'Great-great-grandson',
        'other': 'Great-great-grandchild',
      },
    );
    return '$_temp0';
  }

  @override
  String gradNachkommeN(int stufe) {
    return 'Descendant, $stufe generations down';
  }

  @override
  String gradGeschwister(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Sister',
        'm': 'Brother',
        'other': 'Sibling',
      },
    );
    return '$_temp0';
  }

  @override
  String gradHalbgeschwister(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Half-sister',
        'm': 'Half-brother',
        'other': 'Half-sibling',
      },
    );
    return '$_temp0';
  }

  @override
  String gradNeffeNichte(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Niece',
        'm': 'Nephew',
        'other': 'Sibling’s child',
      },
    );
    return '$_temp0';
  }

  @override
  String gradGrossneffeNichte(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Great-niece',
        'm': 'Great-nephew',
        'other': 'Sibling’s grandchild',
      },
    );
    return '$_temp0';
  }

  @override
  String gradGeschwisterNachkommeN(int stufe) {
    return 'Descendant of a sibling, $stufe steps down';
  }

  @override
  String gradOnkelTante(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Aunt',
        'm': 'Uncle',
        'other': 'Parent’s sibling',
      },
    );
    return '$_temp0';
  }

  @override
  String gradGrossonkelTante(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Great-aunt',
        'm': 'Great-uncle',
        'other': 'Grandparent’s sibling',
      },
    );
    return '$_temp0';
  }

  @override
  String gradVorfahrengeschwisterN(int stufe) {
    return 'Sibling of an ancestor, $stufe generations up';
  }

  @override
  String gradCousin(String geschlecht, int stufe) {
    String _temp0 = intl.Intl.pluralLogic(
      stufe,
      locale: localeName,
      other: 'Degree-$stufe',
      two: 'Second',
      one: 'First',
    );
    String _temp1 = intl.Intl.selectLogic(
      geschlecht,
      {
        'other': '$_temp0 cousin',
      },
    );
    return '$_temp1';
  }

  @override
  String gradEntfernt(int stufe, String bezeichnung) {
    return '$bezeichnung, $stufe times removed';
  }

  @override
  String gradPartner(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Partner',
        'm': 'Partner',
        'other': 'Partner',
      },
    );
    return '$_temp0';
  }

  @override
  String gradSchwager(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Sister-in-law',
        'm': 'Brother-in-law',
        'other': 'Sibling-in-law',
      },
    );
    return '$_temp0';
  }

  @override
  String gradSchwiegereltern(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Mother-in-law',
        'm': 'Father-in-law',
        'other': 'Parent-in-law',
      },
    );
    return '$_temp0';
  }

  @override
  String gradSchwiegerkind(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Daughter-in-law',
        'm': 'Son-in-law',
        'other': 'Child-in-law',
      },
    );
    return '$_temp0';
  }

  @override
  String gradStiefeltern(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Stepmother',
        'm': 'Stepfather',
        'other': 'Stepparent',
      },
    );
    return '$_temp0';
  }

  @override
  String gradStiefkind(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Stepdaughter',
        'm': 'Stepson',
        'other': 'Stepchild',
      },
    );
    return '$_temp0';
  }

  @override
  String gradStiefgeschwister(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Stepsister',
        'm': 'Stepbrother',
        'other': 'Stepsibling',
      },
    );
    return '$_temp0';
  }

  @override
  String get gradAngeheiratet => 'related by marriage';

  @override
  String gradUeberWeg(String schritt, String bezug, String name) {
    return '$schritt of $bezug $name';
  }

  @override
  String get gradKeine => 'not related';

  @override
  String get navStammbaum => 'Family tree';

  @override
  String get stammbaumAndereWaehlen => 'Put another person at the centre';

  @override
  String get stammbaumAnsichtBaum => 'Tree';

  @override
  String get stammbaumAnsichtListe => 'Relatives';

  @override
  String stammbaumListeKopf(String name, int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl people are related to $name – closest relatives first.',
      one: 'One person is related to $name.',
    );
    return '$_temp0';
  }

  @override
  String get stammbaumKeinePersonen =>
      'No people yet. Name a few faces under “People”, or add someone here via “Put another person at the centre”.';

  @override
  String get stammbaumGeschlecht => 'Gender';

  @override
  String get stammbaumGeschlechtWeiblich => 'female';

  @override
  String get stammbaumGeschlechtMaennlich => 'male';

  @override
  String get stammbaumGeschlechtDivers => 'non-binary';

  @override
  String get stammbaumGeschlechtOffen => 'not stated';

  @override
  String get stammbaumGeschlechtHinweis =>
      'Used only for the relationship labels – without it you get “sibling” instead of “sister”.';

  @override
  String get stammbaumAngaben => 'Person details';

  @override
  String get stammbaumAnsichtFaecher => 'Fan';

  @override
  String get stammbaumAnsichtNachfahren => 'Descendants';

  @override
  String get stammbaumKeineVorfahren =>
      'No ancestors recorded for this person yet. The fan shows parents, grandparents and great-grandparents – add a parent at the top right and it fills from the inside out.';

  @override
  String get stammbaumKeineNachfahren =>
      'No children recorded for this person yet. The outline shows all descendants, indented by generation.';

  @override
  String get stammbaumFamilienfotos => 'Photos of this family';

  @override
  String stammbaumFamilienfotosVon(String name) {
    return 'Photos of $name’s family';
  }

  @override
  String get stammbaumGedcomImport => 'Import GEDCOM …';

  @override
  String get gedcomImportTitel => 'The file contains';

  @override
  String gedcomImportGefunden(int personen, int kanten, int ereignisse) {
    return '$personen people, $kanten relationships and $ereignisse events.';
  }

  @override
  String get gedcomImportNeuHinweis =>
      'All of them are created anew. Nothing existing is changed or merged.';

  @override
  String get gedcomImportUebernehmen => 'Import';

  @override
  String gedcomImportFertig(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl people imported.',
      one: 'One person imported.',
    );
    return '$_temp0';
  }

  @override
  String get gedcomFehlerTitel => 'File cannot be read';

  @override
  String get gedcomFehlerKeinKopf =>
      'The file does not begin with a GEDCOM header. It is probably not a GEDCOM file.';

  @override
  String gedcomFehlerKodierung(String kodierung) {
    return 'The file is written in $kodierung. That encoding cannot be deciphered reliably, and half-deciphered names would be worse than an honest no. Please export it again as UTF-8 from the program it came from.';
  }

  @override
  String get gedcomFehlerKeinePersonen =>
      'The file does not contain a single person.';

  @override
  String get gedcomBerichtTitel => 'What came up while reading';

  @override
  String get gedcomBerichtSauber => 'Nothing to report.';

  @override
  String gedcomBerichtDoppelte(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl people may already exist.',
      one: 'One person may already exist.',
    );
    return '$_temp0';
  }

  @override
  String get gedcomBerichtDoppelteHinweis =>
      'Nothing was merged. Who really is the same person is yours to decide, on the people screen.';

  @override
  String gedcomBerichtUngenaueDaten(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl dates were given only approximately and were left empty.',
      one: 'One date was given only approximately and was left empty.',
    );
    return '$_temp0';
  }

  @override
  String gedcomBerichtUebersprungen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl entries belong to something this app does not keep.',
      one: 'One entry belongs to something this app does not keep.',
    );
    return '$_temp0';
  }

  @override
  String gedcomBerichtKreise(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other:
          '$anzahl relationships would have closed a loop and were left out.',
      one: 'One relationship would have closed a loop and was left out.',
    );
    return '$_temp0';
  }

  @override
  String gedcomBerichtOhneNamen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl people had no name in the file.',
      one: 'One person had no name in the file.',
    );
    return '$_temp0';
  }

  @override
  String get gedcomOrtGeburt => 'Place of birth';

  @override
  String get gedcomOrtTod => 'Place of death';

  @override
  String get gedcomOrtTaufe => 'Baptism';

  @override
  String get gedcomOrtBestattung => 'Burial';

  @override
  String get gedcomOhneNamen => 'Unnamed';

  @override
  String get stammbaumZeitleisteOhneDaten =>
      'Nothing on the timeline yet: no date is recorded for anyone in this family.';

  @override
  String get stammbaumAnsichtZeitleiste => 'Timeline';

  @override
  String get zeitleisteOhneDatum => 'no date known';

  @override
  String zeitleisteEreignisse(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl events',
      one: 'one event',
    );
    return '$_temp0';
  }

  @override
  String get stammbaumFamilienstatistik => 'Family statistics';

  @override
  String get famstatAufFotos => 'In the photos';

  @override
  String get famstatAusLebensdaten => 'From the life dates';

  @override
  String get famstatAufnahmenGesamt => 'Photos';

  @override
  String get famstatImBild => 'In the picture';

  @override
  String get famstatZeitraum => 'Period';

  @override
  String famstatOhneBild(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl people are in no photo',
      one: 'One person is in no photo',
    );
    return '$_temp0';
  }

  @override
  String get famstatAufnahmenJeJahr => 'Photos per year';

  @override
  String get famstatOftZusammen => 'Often pictured together';

  @override
  String famstatVonBis(String von, String bis) {
    return '$von to $bis';
  }

  @override
  String famstatAlterVonBis(int von, int bis) {
    return 'aged $von to $bis';
  }

  @override
  String famstatInJahren(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: 'across $anzahl years',
      one: 'in one year',
    );
    return '$_temp0';
  }

  @override
  String get famstatFehlendeLebensdaten =>
      'Age at death, age at marriage and age per generation appear once death and marriage dates are entered. Photo Vault does not estimate them.';

  @override
  String get famstatKeineFotos =>
      'Nobody from this family has been recognised in a photo yet.';

  @override
  String get famstatLeer => 'No one is recorded for this family.';

  @override
  String get famstatPersonen => 'People';

  @override
  String get famstatLebensalter => 'Age at death';

  @override
  String get famstatHeiratsalter => 'Age at marriage';

  @override
  String get famstatHaeufigsterName => 'Most common surname';

  @override
  String famstatJahre(String jahre) {
    return '$jahre years';
  }

  @override
  String famstatSpanne(int von, int bis) {
    return '$von to $bis years';
  }

  @override
  String get famstatOhneWert => 'not known';

  @override
  String famstatEingerechnet(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl people counted',
      one: 'one person counted',
    );
    return '$_temp0';
  }

  @override
  String famstatOhneSterbedatum(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl people without a date of death are not counted.',
      one: 'One person without a date of death is not counted.',
    );
    return '$_temp0';
  }

  @override
  String get famstatWarumOhneSterbedatum =>
      'Anyone still living has no date of death. Counted as “zero years”, the average would look plausible and be badly wrong.';

  @override
  String famstatOhneGeburtsdatum(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other:
          '$anzahl marriages have no date of birth to go with them and are not counted.',
      one:
          'One marriage has no date of birth to go with it and is not counted.',
    );
    return '$_temp0';
  }

  @override
  String get famstatAlterJeGeneration => 'Age at death across the generations';

  @override
  String famstatGeneration(int nummer) {
    return 'Generation $nummer';
  }

  @override
  String famstatGenerationKurz(int nummer) {
    return '$nummer';
  }

  @override
  String get famstatGenerationHinweis =>
      'The first is the oldest one in this family. Generations in which no one has died are missing.';

  @override
  String get famstatKinderzahl => 'Children per person';

  @override
  String get famstatKinderHinweis =>
      'A distribution, not an average: the youngest generation sits at zero because its children are still ahead of it. Only children who are part of this family are counted.';

  @override
  String famstatKinderAchse(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl children',
      one: 'one child',
      zero: 'no children',
    );
    return '$_temp0';
  }

  @override
  String get famstatNachnamen => 'Surnames';

  @override
  String get famstatVornamen => 'Given names';

  @override
  String famstatDiagrammGenerationen(String inhalt) {
    return 'Age at death across the generations: $inhalt';
  }

  @override
  String famstatDiagrammKinder(String inhalt) {
    return 'Children per person: $inhalt';
  }

  @override
  String get erkundenReisen => 'Trips';

  @override
  String get erkundenAktivitaeten => 'Activities';

  @override
  String get gelaendeKarte => 'Map on the landscape';

  @override
  String get kalenderGanzesJahr => 'Whole year';

  @override
  String get einstSchwebeVorschauTitel => 'Play videos on hover';

  @override
  String get einstSchwebeVorschauText =>
      'When the mouse rests on a video or a live photo for a moment, it starts playing right in the tile - muted and looping, until the pointer moves on. Only ever one at a time. Locked items stay still: playing them would mean decrypting them in passing. Switched off, the tiles remain stills.';

  @override
  String get gelaendeStimmung => 'Time of day';

  @override
  String get stimmungMorgen => 'Morning';

  @override
  String get stimmungMittag => 'Midday';

  @override
  String get stimmungAbend => 'Evening';

  @override
  String get stimmungBlaueStunde => 'Blue hour';

  @override
  String get einstKarteScharfTitel => 'Map at double resolution';

  @override
  String get einstKarteScharfText =>
      'On a display with double pixel density the map fetches four tiles of the next deeper level and places them where one would go: four times the pixels, house numbers and shop names become legible. The price is about two and a half times as many tiles per screen - on a slower machine zooming stutters noticeably. Switched off, the map draws as it did before.';

  @override
  String get routeVergroessern => 'Enlarge the map';

  @override
  String get routeVerkleinern => 'Shrink the map';

  @override
  String get reisenTitel => 'Trips';

  @override
  String get reisenLeer =>
      'No trip yet. Photo Vault does not have you type them in, it recognises them: as soon as enough located photos from far away are together, a suggestion appears here for you to confirm.';

  @override
  String get reisenSuchtNoch => 'Looking for trips …';

  @override
  String get reisenVorschlaege => 'Suggestions';

  @override
  String get reisenBestaetigte => 'Your trips';

  @override
  String get reisenIstEineReise => 'That was a trip';

  @override
  String get reisenKeineReise => 'Not a trip';

  @override
  String get reisenBenennen => 'Name the trip';

  @override
  String get reisenName => 'Name';

  @override
  String get reisenNotiz => 'Note';

  @override
  String get reisenTagesnotiz => 'Note for this day';

  @override
  String reisenTagesnotizTitel(String datum) {
    return '$datum';
  }

  @override
  String get reisenTagesnotizSchreiben => 'Write a note for this day';

  @override
  String get reisenTagesnotizAendern => 'Edit the note for this day';

  @override
  String get reisenUmbenennen => 'Rename';

  @override
  String get reisenLoeschen => 'Remove trip';

  @override
  String reisenLoeschenFrage(String name) {
    return 'Remove “$name”? The photos stay where they are.';
  }

  @override
  String get reisenOhneOrt => 'Unknown parts';

  @override
  String reisenSpanne(String von, String bis) {
    return '$von to $bis';
  }

  @override
  String reisenNaechte(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl nights',
      one: 'one night',
    );
    return '$_temp0';
  }

  @override
  String reisenAnzahl(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl trips',
      one: 'one trip',
      zero: 'no trips',
    );
    return '$_temp0';
  }

  @override
  String ortsbezugOrte(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl places',
      one: 'one place',
    );
    return '$_temp0';
  }

  @override
  String ortsbezugWeitere(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl more places',
      one: 'one more place',
    );
    return '$_temp0';
  }

  @override
  String aktivitaetenAnzahl(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl activities',
      one: 'one activity',
      zero: 'no activities',
    );
    return '$_temp0';
  }

  @override
  String aktivitaetenMitReise(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl on trips',
      one: 'one on a trip',
    );
    return '$_temp0';
  }

  @override
  String aktivitaetenOhneReiseZahl(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl standalone',
      one: 'one standalone',
    );
    return '$_temp0';
  }

  @override
  String reisenAufnahmen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl photos',
      one: 'one photo',
    );
    return '$_temp0';
  }

  @override
  String get reisenOrte => 'Places visited';

  @override
  String get reisenAktualisieren => 'Look again';

  @override
  String get reisenRoute => 'Route';

  @override
  String get reisenKeineRoute => 'Without a located photo there is no route.';

  @override
  String get reisenAlsTitelbild => 'Use as cover';

  @override
  String get reisenTitelbildGesetzt => 'Cover set.';

  @override
  String reisenTag(String datum) {
    return '$datum';
  }

  @override
  String fortschrittLaender(int besucht, int gesamt) {
    return '$besucht of $gesamt countries';
  }

  @override
  String fortschrittRegionen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl regions',
      one: 'one region',
    );
    return '$_temp0';
  }

  @override
  String fortschrittOrte(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl places',
      one: 'one place',
    );
    return '$_temp0';
  }

  @override
  String get fortschrittOhneGeodaten =>
      'Without the GeoNames data no photo can be assigned to a country. It is downloaded under “Tools”.';

  @override
  String fortschrittHinweis(int gesamt) {
    return 'Counted against the $gesamt countries and territories in the GeoNames data – overseas territories included, not just the 195 sovereign states. A curated list of our own would be a second truth beside the one the photos are actually sorted by.';
  }

  @override
  String get weltkarteTitel => 'World map';

  @override
  String get weltkarteEbenen => 'Layers';

  @override
  String get weltkarteLaender => 'Countries';

  @override
  String get weltkarteRegionen => 'Regions';

  @override
  String get weltkarteOrte => 'Places';

  @override
  String get weltkarteKeinOrt => 'The data set knows no place at this spot.';

  @override
  String weltkarteMarkeGesetzt(String name) {
    return '“$name” is marked.';
  }

  @override
  String get weltkarteOeffnen => 'World map';

  @override
  String get laenderTitel => 'Countries';

  @override
  String laenderKopf(int gesamt, int besucht, int teilweise) {
    return '$gesamt countries · $besucht visited · $teilweise partial';
  }

  @override
  String get laenderSuchen => 'Search country or capital';

  @override
  String get laenderFilter => 'Filter by';

  @override
  String get laenderAlle => 'All';

  @override
  String get laenderLegende => 'Key';

  @override
  String get laenderAusFotos => 'Backed by photos';

  @override
  String get laenderNurVonHand => 'Marked by hand';

  @override
  String get laenderVollstaendig => 'Complete';

  @override
  String get laenderTeilweise => 'Partial';

  @override
  String get laenderNichtBesucht => 'Not visited';

  @override
  String get laenderBesucht => 'Visited';

  @override
  String get laenderGeplant => 'Planned';

  @override
  String get laenderVerbleibend => 'Remaining';

  @override
  String laenderRegionen(int besucht, int gesamt) {
    return '$besucht of $gesamt regions';
  }

  @override
  String get laenderOhneRegionen => 'No regions on record';

  @override
  String laenderAufnahmen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl photos',
      one: 'one photo',
      zero: 'no photos',
    );
    return '$_temp0';
  }

  @override
  String get laenderNichtsGefunden => 'No country matches your search.';

  @override
  String get laenderMarkeBesucht => 'Mark as visited';

  @override
  String get laenderMarkeGeplant => 'Mark as planned';

  @override
  String get laenderMarkeWeg => 'Remove mark';

  @override
  String get laenderVonHand => 'by hand';

  @override
  String get laenderOhneGeodaten =>
      'Without the GeoNames data set there is no country directory. It is downloaded under “Tools”.';

  @override
  String get laenderHinweisMarke =>
      'What your photos prove appears here on its own. Mark by hand what no photo shows – the trip before your first digital camera, or next year\'s destination.';

  @override
  String get erdteilEU => 'Europe';

  @override
  String get erdteilAS => 'Asia';

  @override
  String get erdteilNA => 'North America';

  @override
  String get erdteilSA => 'South America';

  @override
  String get erdteilAF => 'Africa';

  @override
  String get erdteilOC => 'Oceania';

  @override
  String get erdteilAN => 'Antarctica';

  @override
  String get erdteilUnbekannt => 'No continent';

  @override
  String get werkzGpxTitel => 'Locate photos from a GPX track';

  @override
  String get werkzGpxText =>
      'A recording carries timestamps. That gives photos from cameras without GPS a location too.';

  @override
  String get gpxTitel => 'Locate from GPX';

  @override
  String get gpxDateiWaehlen => 'Choose a GPX file …';

  @override
  String get gpxErklaerung =>
      'Choose a recording. Photo Vault lays your photos\' capture times against the track and fills in the coordinates – only for photos that do not have one yet.';

  @override
  String gpxSpur(int punkte, String von, String bis) {
    return '$punkte points · $von to $bis';
  }

  @override
  String get gpxVersatz => 'Time offset';

  @override
  String get gpxVersatzHinweis =>
      'EXIF writes the capture time without a time zone, GPX writes UTC. The suggestion is the offset at which the most photos fall on the track – it also catches a camera clock that runs wrong.';

  @override
  String gpxTreffer(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl photos get a location.',
      one: 'One photo gets a location.',
      zero: 'No photo falls on the track.',
    );
    return '$_temp0';
  }

  @override
  String get gpxVerorten => 'Locate';

  @override
  String gpxFertig(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl photos located.',
      one: 'One photo located.',
    );
    return '$_temp0';
  }

  @override
  String get gpxKeineKandidaten =>
      'Every photo within this track\'s time span already has a location.';

  @override
  String get gpxFehlerKeinGpx => 'This is not a GPX file.';

  @override
  String get gpxFehlerOhneZeit =>
      'Not a single point in this track has a timestamp. Without a time nothing can be matched.';

  @override
  String get gpxFehlerLeer => 'The file contains no points at all.';

  @override
  String get stammbaumKeineFamilienfotos =>
      'Nobody from this family has been recognised in a photo yet.';

  @override
  String get stammbaumGedcomExport => 'Export as GEDCOM …';

  @override
  String stammbaumGedcomFertig(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl people exported.',
      one: 'One person exported.',
    );
    return '$_temp0';
  }

  @override
  String gradAdoptiveltern(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Adoptive mother',
        'm': 'Adoptive father',
        'other': 'Adoptive parent',
      },
    );
    return '$_temp0';
  }

  @override
  String gradPflegeeltern(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Foster mother',
        'm': 'Foster father',
        'other': 'Foster parent',
      },
    );
    return '$_temp0';
  }

  @override
  String gradAdoptivkind(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Adopted daughter',
        'm': 'Adopted son',
        'other': 'Adopted child',
      },
    );
    return '$_temp0';
  }

  @override
  String gradPflegekind(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Foster daughter',
        'm': 'Foster son',
        'other': 'Foster child',
      },
    );
    return '$_temp0';
  }

  @override
  String get stammbaumLeiblich => 'Biological';

  @override
  String get stammbaumAdoptiv => 'Adoptive';

  @override
  String get stammbaumPflege => 'Foster';

  @override
  String get stammbaumAnsichtSanduhr => 'Hourglass';

  @override
  String get stammbaumSeitenlinien => 'Collateral line';

  @override
  String get stammbaumSeitenlinienHinweis =>
      'Siblings beside the person, their children below – this is what makes nephews, nieces and in-laws visible.';

  @override
  String lebenslaufVon(String name) {
    return 'Life story: $name';
  }

  @override
  String get lebenslaufHinzufuegen => 'Add event';

  @override
  String get lebenslaufLeer =>
      'Nothing recorded for this person yet. Birth and death live with the person details; weddings, moves, jobs and everything else go here.';

  @override
  String get lebenslaufGeburt => 'Born';

  @override
  String get lebenslaufTod => 'Died';

  @override
  String get lebenslaufHochzeit => 'Marriage';

  @override
  String get lebenslaufUmzug => 'Move';

  @override
  String get lebenslaufBeruf => 'Work';

  @override
  String get lebenslaufAusbildung => 'Education';

  @override
  String get lebenslaufSonstiges => 'Other';

  @override
  String get lebenslaufOhneDatum => 'no date';

  @override
  String get lebenslaufOrt => 'Place';

  @override
  String get lebenslaufOrtAufKarte => 'Place on the map';

  @override
  String get lebenslaufOrtErkannt =>
      'Found on the map – tap to correct the point.';

  @override
  String get lebenslaufOrtUnbekannt =>
      'This place is not in the gazetteer. Tap the map to set it yourself.';

  @override
  String get lebenslaufOrtEntfernen => 'Remove location';

  @override
  String get lebenslaufOrtOhneVerzeichnis =>
      'Without the gazetteer, places cannot be found automatically. A point can still be set by hand.';

  @override
  String get lebenslaufNotiz => 'Note';

  @override
  String get stammbaumLebenslauf => 'Life story …';

  @override
  String get orteIch => 'This person';

  @override
  String get orteVorfahren => 'Ancestors';

  @override
  String get orteNachkommen => 'Descendants';

  @override
  String get orteSeitenlinie => 'Collateral line';

  @override
  String get orteAngeheiratet => 'By marriage';

  @override
  String get orteEreignisse => 'Life events';

  @override
  String get orteNichtsGewaehlt => 'No group selected.';

  @override
  String get stammbaumFamilienorte => 'Places of this family';

  @override
  String get stammbaumMenue => 'More about this person';

  @override
  String get stammbaumVerbindungsart => 'Kind of connection …';

  @override
  String stammbaumVerbindungsartTitel(String kind, String elternteil) {
    return 'How is $kind connected to $elternteil?';
  }

  @override
  String get stammbaumVerbindungsartHinweis =>
      'Adoptive and foster parents count as parents everywhere – only the term and the dashed line tell them apart.';

  @override
  String get stammbaumNichtsEntfernt => 'That connection was already removed.';

  @override
  String get stammbaumWeitereVerwandte => 'More relatives';

  @override
  String get stammbaumVerwandtenHinzufuegen => 'Add a relative …';

  @override
  String get stammbaumGruppeVorfahren => 'Ancestors';

  @override
  String get stammbaumGruppeNachkommen => 'Descendants';

  @override
  String get stammbaumGruppeSeitenlinie => 'Collateral line';

  @override
  String get stammbaumGruppeAngeheiratet => 'By marriage';

  @override
  String get stammbaumGradGrosselternteil => 'Grandparent';

  @override
  String get stammbaumGradUrgrosselternteil => 'Great-grandparent';

  @override
  String get stammbaumGradEnkelkind => 'Grandchild';

  @override
  String get stammbaumGradUrenkelkind => 'Great-grandchild';

  @override
  String get stammbaumGradGeschwisterkind => 'Sibling';

  @override
  String get stammbaumGradHalbgeschwisterkind => 'Half-sibling';

  @override
  String get stammbaumGradOnkelTante => 'Uncle or aunt';

  @override
  String get stammbaumGradNeffeNichte => 'Nephew or niece';

  @override
  String get stammbaumGradCousin => 'Cousin';

  @override
  String get stammbaumGradSchwiegerelternteil => 'Parent-in-law';

  @override
  String get stammbaumGradSchwiegerkind => 'Child-in-law';

  @override
  String get stammbaumGradSchwager => 'Brother- or sister-in-law';

  @override
  String get stammbaumGradStiefelternteil => 'Step-parent';

  @override
  String get stammbaumGradStiefkind => 'Stepchild';

  @override
  String stammbaumFehltElternteil(String name) {
    return '$name needs a parent first.';
  }

  @override
  String stammbaumFehltGrosselternteil(String name) {
    return '$name needs grandparents first.';
  }

  @override
  String stammbaumFehltKind(String name) {
    return '$name needs a child first.';
  }

  @override
  String stammbaumFehltEnkelkind(String name) {
    return '$name needs a grandchild first.';
  }

  @override
  String stammbaumFehltGeschwister(String name) {
    return '$name needs a sibling first.';
  }

  @override
  String stammbaumFehltOnkelTante(String name) {
    return '$name needs an uncle or aunt first.';
  }

  @override
  String stammbaumFehltPartner(String name) {
    return '$name needs a partner first.';
  }

  @override
  String stammbaumFehltGeschwisterOderPartner(String name) {
    return '$name needs a sibling or a partner first.';
  }

  @override
  String stammbaumUeberWen(String grad) {
    return '$grad – through whom?';
  }

  @override
  String stammbaumVerwandterEingetragen(String name, String bezeichnung) {
    return '$name has been added – $bezeichnung.';
  }

  @override
  String stammbaumNurEintragbares(String name) {
    return 'Shown is what can be added for $name. Greyed out means an intermediate person is still missing.';
  }

  @override
  String stammbaumFamilienorteVon(String name) {
    return 'Places of $name’s family';
  }

  @override
  String get stammbaumKeineFamilienorte =>
      'No photo from this family has a location.';

  @override
  String get stammbaumZierbaumDrucken => 'Ornamental tree as PDF';

  @override
  String get stammbaumTafelDrucken => 'Chart as PDF …';

  @override
  String get stammbaumTafelFertig => 'The chart has been written.';

  @override
  String get aufgWirdErmittelt => 'Working out what is left …';

  @override
  String aufgAbgebrochenBei(int erledigt, int gesamt) {
    return 'Cancelled at $erledigt of $gesamt';
  }

  @override
  String aufgFertigMit(int gesamt) {
    return 'Done – $gesamt processed';
  }

  @override
  String get beendenTitel => 'Still analysing';

  @override
  String get beendenText =>
      'Quitting loses the file currently being worked on; everything already analysed stays. Still running:';

  @override
  String get beendenTrotzdem => 'Quit anyway';

  @override
  String get beendenWeiterlaufen => 'Keep running';

  @override
  String get aufgUebersetzenTitel => 'Translate captions';

  @override
  String get aufgUebersetzenText =>
      'Turns the existing English AI captions into German – without running the captioning model again.';

  @override
  String get aufgUebersetzungsmodell =>
      'the English → German translation model';

  @override
  String get werkzUebersetzeBeschreibungen => 'Translating captions …';

  @override
  String get werkzAlleUebersetzt => 'Every caption has been translated.';

  @override
  String get aufgLaeuftSchon => 'This analysis is already running.';

  @override
  String get infoKiBeschreibungVonHand => 'AI caption, edited by hand';

  @override
  String get infoKiVonHandHinweis =>
      'Survives “All photos”. Clear the field to have it computed again.';

  @override
  String get infoSpracheDe => 'DE';

  @override
  String get infoSpracheEn => 'EN';

  @override
  String get infoKiPlatzhalterDe => 'Write the German version';

  @override
  String get infoKiPlatzhalterEn => 'Write the English version';

  @override
  String duplGefunden(int gruppen, int fotos) {
    return '$gruppen groups with $fotos photos';
  }

  @override
  String get duplNichtsGefunden => 'No groups found';

  @override
  String get duplGruppeIgnorieren => 'Skip';

  @override
  String duplGruppeIgnoriert(int anzahl) {
    return '$anzahl photos will be skipped by the duplicate search from now on.';
  }

  @override
  String duplAusnahmenZahl(int anzahl) {
    return '$anzahl skipped';
  }

  @override
  String get duplAusnahmenTitel => 'Show skipped ones again';

  @override
  String duplAusnahmenFrage(int anzahl) {
    return '$anzahl pairs are excluded from the search. Should all of them be considered again?';
  }

  @override
  String get duplAusnahmenLoeschen => 'Show all again';

  @override
  String get entwNurMitCoreImage =>
      'Sharpening, noise reduction, clarity and vignetting need processing steps that only exist on macOS. Every other slider works fully here.';

  @override
  String get modellOcrTitel => 'Text recognition (PaddleOCR)';

  @override
  String get modellOcrText =>
      'Finds text in photos and reads it – two models, 13.7 MB together. Covers the Latin alphabet including umlauts and ß. Not needed on macOS: Apple\'s Vision framework does it there without a download.';

  @override
  String get modellOcrLizenz => 'Apache 2.0 (PaddleOCR)';

  @override
  String get aufgOcrModell => 'the text recognition model';

  @override
  String get werkzDatumTitel => 'Read capture date from RAW photos and videos';

  @override
  String get werkzDatumFrageTitel => 'Correct the capture date?';

  @override
  String get werkzDatumFrage =>
      'Photos whose capture date came from the file timestamp will get the real date from the RAW file. They move to the right place in the timeline and calendar, and on disk into the matching month folder.\n\nThe photos themselves are not modified. The run cannot be undone.';

  @override
  String get werkzDatumStarten => 'Correct';

  @override
  String get werkzKorrigiereDatum =>
      'Reading capture data from RAW photos and videos ...';

  @override
  String get werkzKeineRawFotos =>
      'No RAW photographs and no videos in the library.';

  @override
  String get karteGlobusZoomHinweis =>
      'Zooming in further shows no extra detail – the Earth texture is a single image. Tap a pin to switch to the map at that spot.';

  @override
  String get karteHineinzoomen => 'Zoom in';

  @override
  String get karteHerauszoomen => 'Zoom out';

  @override
  String get zoomEinpassen => 'Fit to window';

  @override
  String get karteEreignisseEinblenden => 'Show life events';

  @override
  String get karteEreignisseAusblenden => 'Hide life events';

  @override
  String get karteStandortZeigen => 'My location';

  @override
  String get karteStandortNichtErmittelbar =>
      'Could not determine your location. Check System Settings → Privacy & Security → Location Services to see whether Photo Vault may ask.';

  @override
  String get karteStandortSuche => 'Determining location …';

  @override
  String get weltkarteKlickMarkiert => 'A click marks';

  @override
  String weltkarteMarkeWeggenommen(String name) {
    return '“$name” is no longer marked.';
  }

  @override
  String weltkarteSchonBelegt(String name) {
    return '“$name” is already covered by your photos.';
  }

  @override
  String get weltkarteLegende => 'Where a mark comes from';

  @override
  String get weltkarteLegendeFotos =>
      'Filled, solid outline: evidenced by located photos.';

  @override
  String get weltkarteLegendeHand =>
      'Pale, dotted outline: marked by hand, without a photo.';

  @override
  String get weltkarteLegendeGeplant =>
      'Nearly empty, dashed outline: planned – does not count as visited.';

  @override
  String get weltkarteOhneUmriss =>
      'Small territories such as the Vatican have no outline; they stay a dot.';

  @override
  String ortRegionen(int besucht, int gesamt) {
    return 'Regions · $besucht of $gesamt';
  }

  @override
  String ortOrte(int besucht, int gesamt) {
    return 'Places · $besucht of $gesamt';
  }

  @override
  String ortFotos(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl photos',
      one: 'One photo',
    );
    return '$_temp0';
  }

  @override
  String get ortNichtsHier =>
      'Nothing from here yet – no photo, and the dataset knows no further level below.';

  @override
  String get meldungenTitel => 'Notifications';

  @override
  String get meldungenKeine => 'Nothing to report yet.';

  @override
  String get meldungenGlocke => 'Show notifications';

  @override
  String get meldungSchliessen => 'Dismiss notification';

  @override
  String get meldungenAlleSchliessen => 'Hide all';

  @override
  String get meldungenVerlaufLeeren => 'Clear history';

  @override
  String meldungWiederholt(int anzahl) {
    return '$anzahl×';
  }

  @override
  String get meldungArtHinweis => 'Note';

  @override
  String get meldungArtErfolg => 'Done';

  @override
  String get meldungArtWarnung => 'Warning';

  @override
  String get meldungArtFehler => 'Error';

  @override
  String get aktivitaetenTitel => 'Activities';

  @override
  String get aktivitaetenOeffnen => 'Show activities';

  @override
  String get aktivitaetenVorschlaege => 'Suggestions';

  @override
  String get aktivitaetenBestaetigte => 'On trips';

  @override
  String get aktivitaetenOhneReise => 'On their own';

  @override
  String get aktivitaetenLeer =>
      'No activity yet. Hikes, bike rides and outings are detected from a day\'s photos – a handful of located pictures spanning at least three quarters of an hour are needed.';

  @override
  String get aktivitaetenSuchtNoch => 'Looking for outings …';

  @override
  String get aktivitaetenBenennen => 'Name activity';

  @override
  String get aktivitaetenUmbenennen => 'Rename';

  @override
  String get aktivitaetenName => 'Name';

  @override
  String get aktivitaetenLoeschen => 'Delete activity';

  @override
  String aktivitaetenLoeschenFrage(String name) {
    return 'Remove “$name” from the list? The photos stay where they are.';
  }

  @override
  String get aktivitaetenNotiz => 'Note';

  @override
  String get aktivitaetenArtAendern => 'Change type';

  @override
  String aktivitaetenStrecke(String km) {
    return '$km km';
  }

  @override
  String aktivitaetenDauer(int stunden, int minuten) {
    return '$stunden h $minuten min';
  }

  @override
  String aktivitaetenDauerKurz(int minuten) {
    return '$minuten min';
  }

  @override
  String aktivitaetenAufnahmen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl photos',
      one: 'One photo',
    );
    return '$_temp0';
  }

  @override
  String get aktivitaetenOhneOrt => 'Out and about';

  @override
  String aktivitaetenZuReise(String reise) {
    return 'Part of: $reise';
  }

  @override
  String get aktivitaetenKeineRoute => 'Too few located photos for a route.';

  @override
  String get aktivitaetenInDieserReise => 'Outings';

  @override
  String get reiseartReise => 'Trip';

  @override
  String get reisenZusammenfuehren => 'Merge';

  @override
  String get reisenZusammenfuehrenAllein =>
      'There is no second trip to merge this one with.';

  @override
  String reisenZusammenfuehrenTitel(String name) {
    return 'Add to “$name”';
  }

  @override
  String reisenZusammenfuehrenHinweis(String name) {
    return 'The selected trips are absorbed into “$name”: photos, outings, tracks and daily notes come along, and the selected names disappear.';
  }

  @override
  String reisenZusammengefuehrt(String name, int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl trips were',
      one: 'One trip was',
    );
    return '$_temp0 merged into “$name”.';
  }

  @override
  String get reiseartUnternehmung => 'Deployment';

  @override
  String get reiseartGeschaeftlich => 'Business';

  @override
  String get reiseartBesuch => 'Visit';

  @override
  String get reiseartSonstiges => 'Other';

  @override
  String get reisenArtAendern => 'Kind of trip';

  @override
  String get reisenAktivitaetAnlegen => 'Add outing';

  @override
  String get reisenOhneAktivitaeten =>
      'None yet – “Add outing” turns the whole trip, or a stretch of it, into one.';

  @override
  String get reisenAktivitaetLeer =>
      'No photo of this trip falls in that period.';

  @override
  String reisenAktivitaetAngelegt(String name, int anzahl) {
    return 'Outing “$name” created with $anzahl photos.';
  }

  @override
  String aktivitaetenAngelegt(String name) {
    return '“$name” recorded.';
  }

  @override
  String aktivitaetenEntfernt(String name) {
    return '“$name” removed.';
  }

  @override
  String get aufnahmenWahlTitelAktivitaet => 'Photos of this activity';

  @override
  String get aufnahmenWahlTitelReise => 'Photos of this journey';

  @override
  String aufnahmenWahlZeitraum(String von, String bis) {
    return 'Period ($von – $bis)';
  }

  @override
  String get aufnahmenWahlAlle => 'All photos';

  @override
  String aufnahmenWahlGewaehlt(num anzahl) {
    final intl.NumberFormat anzahlNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String anzahlString = anzahlNumberFormat.format(anzahl);

    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahlString photos selected',
      one: '1 photo selected',
      zero: 'nothing selected',
    );
    return '$_temp0';
  }

  @override
  String aufnahmenWahlAusserhalb(num anzahl) {
    final intl.NumberFormat anzahlNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String anzahlString = anzahlNumberFormat.format(anzahl);

    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahlString of them outside this view',
      one: '1 of them outside this view',
    );
    return '$_temp0';
  }

  @override
  String get aufnahmenWahlLeer =>
      'There is no photo in this period. Use “All photos” to pick one from outside it.';

  @override
  String aufnahmenWahlGeaendert(num dazu, num weg) {
    final intl.NumberFormat dazuNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String dazuString = dazuNumberFormat.format(dazu);
    final intl.NumberFormat wegNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String wegString = wegNumberFormat.format(weg);

    String _temp0 = intl.Intl.pluralLogic(
      dazu,
      locale: localeName,
      other: '$dazuString photos added',
      one: '1 photo added',
      zero: '',
    );
    String _temp1 = intl.Intl.pluralLogic(
      weg,
      locale: localeName,
      other: ', $wegString removed',
      one: ', 1 removed',
      zero: '',
    );
    return '$_temp0$_temp1';
  }

  @override
  String get aufnahmenWahlUnveraendert => 'Nothing changed.';

  @override
  String get aktivitaetenArtNeu => 'New type …';

  @override
  String get aktivitaetenArtNeuFrage => 'What should the type be called?';

  @override
  String get aktArtSpaziergang => 'Walk';

  @override
  String get aktArtWanderung => 'Hike';

  @override
  String get aktArtRadtour => 'Bike ride';

  @override
  String get aktArtAusflug => 'Outing';

  @override
  String get aktArtBesichtigung => 'Sightseeing';

  @override
  String get aktArtBootsfahrt => 'Boat trip';

  @override
  String get aktArtSonstiges => 'Other';

  @override
  String get aktivitaetenIstEine => 'Yes, an outing';

  @override
  String get aktivitaetenKeine => 'Not an outing';

  @override
  String get spurHinzufuegen => 'Add GPX track';

  @override
  String get spurEntfernen => 'Remove track';

  @override
  String get spurEntferntMeldung => 'Track removed.';

  @override
  String spurHinzugefuegtMeldung(String name, String km) {
    return 'Track “$name” added: $km km.';
  }

  @override
  String get spurTitel => 'Recorded track';

  @override
  String spurKm(String km) {
    return '$km km';
  }

  @override
  String spurKennzahlen(String km, int auf, int ab) {
    return '$km km · ▲ $auf m · ▼ $ab m';
  }

  @override
  String spurKennzahlenOhneHoehe(String km) {
    return '$km km · no elevation data';
  }

  @override
  String spurPunkte(int anzahl) {
    return '$anzahl points';
  }

  @override
  String get spurHoehenprofil => 'Elevation profile';

  @override
  String get spurOhneHoehen =>
      'This file carries no elevations – without them there is no profile.';

  @override
  String spurProfilBeschreibung(String km, int tief, int hoch, int auf) {
    return 'Elevation profile over $km km, from $tief to $hoch metres, $auf metres of ascent.';
  }

  @override
  String spurStelle(String km, int hoehe) {
    return '$km km · $hoehe m';
  }

  @override
  String get spurSchonDa => 'This activity already has a track.';

  @override
  String get flugStarten => 'Start flight';

  @override
  String get flugAnhalten => 'Pause';

  @override
  String get flugWeiter => 'Continue';

  @override
  String get flugNochmal => 'Again';

  @override
  String get flugBeenden => 'Back to overview';

  @override
  String get flugFortschritt => 'Position along the track';

  @override
  String get flugHoehe => 'Elevation';

  @override
  String get flugTempo => 'Speed';

  @override
  String get flugSteigung => 'Gradient';

  @override
  String get flugVideo => 'Export as video';

  @override
  String get flugVideoAbbrechen => 'Cancel export';

  @override
  String flugVideoFertig(String datei) {
    return 'Video saved: $datei';
  }

  @override
  String get flugVideoAbgebrochen => 'Export cancelled';

  @override
  String get flugVideoKeinWerkzeug =>
      'Video export is unavailable – the video encoder is missing. macOS provides it, Linux and Windows ship it in the package; if you see this, the installation is incomplete.';

  @override
  String flugVideoLaeuft(int prozent) {
    return 'Writing video – $prozent %';
  }

  @override
  String flugVideoLaeuftMitRest(int prozent, String rest) {
    return 'Writing video – $prozent %, about $rest left';
  }

  @override
  String get flugVideoEinstellungen => 'Export video';

  @override
  String get flugVideoAufloesung => 'Resolution';

  @override
  String get flugVideoDauer => 'Length';

  @override
  String flugVideoDauerWert(int sekunden) {
    return '$sekunden seconds';
  }

  @override
  String flugVideoBilder(int bilder) {
    return '$bilder frames';
  }

  @override
  String get flugVideoWeiter => 'Save as …';

  @override
  String get flugVideoWaehrenddessen =>
      'The frames are rendered off screen – the flight is not played for it. This view has to stay open until it is done.';

  @override
  String flugVideoFehler(String grund) {
    return 'Video export failed: $grund';
  }

  @override
  String get flugAufstieg => 'Ascent';

  @override
  String get flugUnterwegs => 'elapsed';

  @override
  String get flugOhneZeit =>
      'The track carries no timestamps – without them there is no speed.';

  @override
  String get flugProfilBeschreibung =>
      'Elevation profile of the track with the point the flight has reached.';

  @override
  String flugMeterProfil(int meter) {
    return '$meter m';
  }

  @override
  String flugKmH(String wert) {
    return '$wert km/h';
  }

  @override
  String flugProzent(String wert) {
    return '$wert %';
  }

  @override
  String flugKm(String wert) {
    return '$wert km';
  }

  @override
  String get gelaendeTitel => 'Terrain';

  @override
  String get gelaendeOeffnen => 'Show terrain';

  @override
  String get gelaendeLaedt => 'Fetching elevations …';

  @override
  String get gelaendeNichts =>
      'No elevation data arrived for this area. The tiles live on the network; without a connection there is no landscape.';

  @override
  String get gelaendeBedienung => 'Drag to rotate and tilt · scroll to zoom';

  @override
  String gelaendeUeberhoeht(String faktor) {
    return 'Elevation exaggerated $faktor×';
  }

  @override
  String get gelaendeNamensnennung => 'Elevation: Tilezen / AWS Open Data';

  @override
  String get karteLuftbild => 'Aerial imagery';

  @override
  String get gelaendeEbeneWege => 'Hiking routes';

  @override
  String get gelaendeEbeneBeschriftung => 'Roads and place names';

  @override
  String get gelaendeEbeneHoehenlinien => 'Contour lines';

  @override
  String get gelaendeEbeneWanderobjekte => 'Peaks, huts, springs';

  @override
  String get gelaendeErneut => 'Try again';

  @override
  String get einstKiTagsZurueck => 'Take back AI tags';

  @override
  String get einstKiTagsZurueckText => 'Counting …';

  @override
  String einstKiTagsZurueckAnzahl(int anzahl) {
    return '$anzahl assigned by image recognition – hand-made ones stay';
  }

  @override
  String einstKiTagsZurueckFrage(int anzahl) {
    return '$anzahl tags from image recognition will be removed. Tags you set yourself stay untouched. Image recognition will then assign them again under the new rule.';
  }

  @override
  String get einstKiTagsZurueckJetzt => 'Take back';

  @override
  String einstKiTagsZurueckFertig(int anzahl) {
    return '$anzahl tags taken back.';
  }

  @override
  String papierkorbAusgewaehlt(int anzahl) {
    return '$anzahl selected';
  }

  @override
  String get papierkorbHinweis =>
      'Tap the arrow on a photo to restore it. Press and hold to select several.';

  @override
  String aktivitaetenWeitere(int anzahl) {
    return '+$anzahl more';
  }

  @override
  String get einstVorladenTitel => 'Preload map areas';

  @override
  String get einstVorladenText =>
      'Fetches the tiles for your own photo areas to disk – the map then needs no network there';

  @override
  String get einstVorladenKeineOrte => 'There are no located photos yet.';

  @override
  String einstVorladenFrage(int gebiete, int kacheln, int mb) {
    return '$gebiete areas, $kacheln tiles, about $mb MB. This takes a while and keeps running as long as settings stay open.';
  }

  @override
  String get einstVorladenStarten => 'Preload';

  @override
  String einstVorladenStand(int fertig, int gesamt) {
    return '$fertig of $gesamt';
  }

  @override
  String einstVorladenFertig(int geladen, int fehler) {
    return '$geladen tiles loaded, $fehler unreachable.';
  }

  @override
  String get mitschnittTitel => 'Tile log';

  @override
  String get mitschnittErklaerung =>
      'Records what the network really returns for every map tile: status code, exception, duration, and whether the server keeps the connection open. Tiles served from the map cache never appear here – they never reach the network.';

  @override
  String get mitschnittStarten => 'Start recording';

  @override
  String get mitschnittAnhalten => 'Stop';

  @override
  String get mitschnittLeeren => 'Clear';

  @override
  String get mitschnittLaeuft =>
      'Recording. Open the map now and keep zooming until the grey tiles show up.';

  @override
  String get mitschnittAus => 'Stopped.';

  @override
  String get mitschnittNochNichts => 'Nothing recorded yet.';

  @override
  String get mitschnittVerbJeAbruf => 'Connections per request';

  @override
  String get mitschnittAbrufeJeKachel => 'Requests per tile';

  @override
  String get mitschnittAbrufe => 'Requests';

  @override
  String get mitschnittVerbindungen => 'Connections';

  @override
  String get mitschnittKacheln => 'distinct tiles';

  @override
  String get mitschnittGeglueckt => 'succeeded';

  @override
  String get mitschnittFehlgeschlagen => 'failed';

  @override
  String get mitschnittAbgebrochen => 'cancelled';

  @override
  String get mitschnittWiederholte => 'fetched more than once';

  @override
  String get mitschnittOhneDauer => 'server closed the connection';

  @override
  String get mitschnittStatusTitel => 'Status codes';

  @override
  String get mitschnittFehlerTitel => 'Errors';

  @override
  String get mitschnittLetzteTitel => 'Most recent requests';

  @override
  String get mitschnittKopieren => 'Copy report';

  @override
  String get mitschnittKopiert => 'The report is on the clipboard.';

  @override
  String get einstMitschnittTitel => 'Tile log';

  @override
  String get einstMitschnittText =>
      'Record what actually happens while the map loads.';

  @override
  String mitschnittDauer(int ms, int max) {
    return 'Average $ms ms, longest $max ms';
  }

  @override
  String mitschnittDaten(String mb) {
    return '$mb MB downloaded';
  }

  @override
  String mitschnittVerworfen(int anzahl) {
    return '$anzahl older entries were dropped at the limit.';
  }

  @override
  String mitschnittMalGeholt(int anzahl) {
    return '${anzahl}x';
  }

  @override
  String get aufgTitel => 'Jobs';

  @override
  String get aufgModusAlle => 'All';

  @override
  String get aufgErstellen => 'Create job';

  @override
  String get aufgErstellenText =>
      'Queue several jobs at once. They run one after another - how many run side by side is set under \"Manage concurrency\".';

  @override
  String get aufgEinreihen => 'Queue';

  @override
  String get aufgGleichzeitigTitel => 'Manage concurrency';

  @override
  String get aufgGleichzeitigText =>
      'How many compute-heavy jobs may run side by side. Each keeps an AI model in memory and reads the same photographs off the disk again - more is not always faster. Jobs without a model start straight away regardless.';

  @override
  String get aufgDatumText =>
      'Reads the capture date back out of RAW files and videos and moves them to the right place on the timeline. Rewrites data and moves files - hence the confirmation.';

  @override
  String get aufgAblageTitel => 'Sort storage by date';

  @override
  String get aufgAblageText =>
      'Moves photos into the folder of the month they were taken if they are not there, and puts stray .xmp sidecars back next to their photo. Changes no date – only the location on disk. Moves files, hence the confirmation.';

  @override
  String get werkzOrdneAblage => 'Sorting the storage ...';

  @override
  String get werkzAblageStimmt => 'Every item sits in the folder of its date.';

  @override
  String werkzAblageBilanz(int verschoben, int gesamt) {
    return '$verschoben of $gesamt moved';
  }

  @override
  String get werkzAblageFrageTitel => 'Sort the storage?';

  @override
  String get werkzAblageFrage =>
      'Items whose folder does not match their capture date are moved into the right month folder. The capture dates themselves stay untouched. Nothing visible changes inside the app - but the library\'s folder structure on disk does.';

  @override
  String get werkzAblageStarten => 'Sort storage';

  @override
  String aufgOffeneFotos(int anzahl) {
    return '$anzahl photographs outstanding';
  }

  @override
  String aufgEingereiht(int anzahl) {
    return '$anzahl jobs queued.';
  }

  @override
  String get werkzZuAufgabenText =>
      'Faces, thumbnails, text recognition, places, keywords and everything else that starts a pass over the library. They live there and nowhere else.';

  @override
  String get aufgVorschauTitel => 'Generate thumbnails';

  @override
  String get sperreTitel => 'This library is already open';

  @override
  String get sperreText =>
      'Another Photo Vault window is working with the same data right now. Two windows on one library show different states and run background tasks twice.\n\nNothing is broken – this library simply will not be opened a second time.';

  @override
  String get sperreOrt => 'Location';

  @override
  String get sperreErneut => 'Try again';

  @override
  String get sperreNochBelegt => 'It is still open.';

  @override
  String get sperreAndere => 'Open another library';

  @override
  String get sperreBeenden => 'Quit Photo Vault';

  @override
  String get sperreAuswahlTitel => 'Open another library';

  @override
  String get sperreAuswahlLeer => 'No other library is listed.';

  @override
  String get personVorschlag => 'Suggested by recognition';

  @override
  String get personSuchenOderAnlegen => 'Search for a person or add a new one';

  @override
  String get allgLeeren => 'Clear';

  @override
  String get personNochKeine =>
      'There is no person yet. Type a name to add the first one.';

  @override
  String personKeinTreffer(String suche) {
    return 'No person is called “$suche”. The button adds them.';
  }

  @override
  String personAnlegenAktion(String name) {
    return 'Add “$name”';
  }

  @override
  String get viewerGesichtAufziehen => 'Add a missing face – drag a frame';

  @override
  String get viewerGesichtAufziehenEnde => 'Stop adding';

  @override
  String get viewerGesichtNachtragen => 'Name the added face';

  @override
  String get viewerRahmenZuKlein =>
      'That frame is too small. Drag a box around the face.';

  @override
  String get viewerRahmenNichtLesbar =>
      'The photograph could not be read – no face was added.';

  @override
  String get viewerAufziehenHinweis => 'Drag a frame around the missing face.';

  @override
  String get karteEigene => 'Custom map';

  @override
  String get einstEigeneKarteTitel => 'Custom map source';

  @override
  String get einstEigeneKarteText =>
      'The bundled maps stop early: OpenStreetMap serves real tiles up to level 19, OpenTopoMap up to 17. If you need house numbers, building outlines or aerial imagery, enter your own source here. It then appears as a fourth entry in the map menu.';

  @override
  String einstEigeneKarteAktiv(String name) {
    return '$name is set up';
  }

  @override
  String get einstEigeneKarteOhne => 'No custom source set up';

  @override
  String get einstEigeneKarteVorlage => 'Use a template';

  @override
  String einstEigeneKarteVorlageGemessen(String stufe) {
    return 'up to level $stufe, measured';
  }

  @override
  String einstEigeneKarteVorlageLautAnbieter(String stufe) {
    return 'up to level $stufe, per the provider';
  }

  @override
  String get einstEigeneKarteName => 'Name';

  @override
  String get einstEigeneKarteAdresse => 'Tile URL';

  @override
  String einstEigeneKarteAdresseHinweis(String muster) {
    return 'https://…/$muster.png';
  }

  @override
  String get einstEigeneKarteNennung => 'Attribution';

  @override
  String get einstEigeneKarteNennungHinweis =>
      '© provider, © OpenStreetMap contributors';

  @override
  String get einstEigeneKarteStufe => 'Highest zoom level';

  @override
  String einstEigeneKarteSchluesselHinweis(String marke) {
    return 'The key belongs in the URL – replace $marke with your own.';
  }

  @override
  String einstEigeneKarteWoher(String quelle) {
    return 'Keys are available at $quelle';
  }

  @override
  String get einstEigeneKarteSitzung => 'Get Google session';

  @override
  String get einstEigeneKarteSitzungText =>
      'Google only serves tiles once a session token exists. Put your key into the URL and fetch one here; it lasts about two weeks.';

  @override
  String get einstEigeneKarteSitzungOk =>
      'Session fetched and inserted into the URL';

  @override
  String einstEigeneKarteSitzungFehler(String fehler) {
    return 'Google returned no session: $fehler';
  }

  @override
  String get einstEigeneKarteSitzungOhneSchluessel =>
      'The URL still has no key in it';

  @override
  String get einstEigeneKarteEntfernen => 'Remove source';

  @override
  String get einstEigeneKarteGespeichert => 'Custom map source saved';

  @override
  String get einstEigeneKarteEntfernt => 'Custom map source removed';

  @override
  String get einstEigeneKarteFehlerLeer => 'A URL is required';

  @override
  String get einstEigeneKarteFehlerHttp =>
      'The URL must start with http:// or https://';

  @override
  String einstEigeneKarteFehlerPlatzhalter(String teile) {
    return 'The URL is missing $teile';
  }

  @override
  String einstEigeneKarteFehlerUnbekannt(String teile) {
    return 'The URL contains a placeholder in braces that the map does not know – only $teile are allowed';
  }

  @override
  String get einstEigeneKarteFehlerNennung =>
      'Attribution is a licence requirement and must not be empty';

  @override
  String get einstEigeneKarteWarnungTitel =>
      'Before you switch on a third-party map source';

  @override
  String get einstEigeneKarteWarnungUebermittlung =>
      'Every tile is a request to that provider. It reveals which part of the world you are looking at, how far you zoom in and how long you stay. With the bundled maps the other end is a donated server without an account – here it is a key issued to you.';

  @override
  String get einstEigeneKarteWarnungOffline =>
      'Tiles you have looked at stay on disk and remain available without a network; pre-loading whole areas works for this source too. Without pre-loading, anything you have never looked at stays grey when offline.';

  @override
  String get einstEigeneKarteWarnungBedingungen =>
      'How far a provider permits caching is set out in its terms – some allow it for a limited time, some not at all, and Google explicitly forbids offline use. That is exactly what this app does: keep tiles and show them again without a network. Whether that is permitted for your provider is not something the app can decide for you.';

  @override
  String get einstEigeneKarteWarnungAnnehmen => 'Understood, switch on';

  @override
  String get einstEigeneKarteFehlerSchluessel =>
      'The URL still contains the template\'s placeholder – put your own key there';

  @override
  String get aufnahmenHinzufuegen => 'Add photos';

  @override
  String get aufnahmenAusAktivitaetEntfernen => 'Remove from activity';

  @override
  String get aufnahmenAusReiseEntfernen => 'Remove from trip';

  @override
  String aufnahmenEntferntAktivitaet(int anzahl) {
    return 'Removed $anzahl photo(s) from the activity';
  }

  @override
  String aufnahmenEntferntReise(int anzahl) {
    return 'Removed $anzahl photo(s) from the trip';
  }

  @override
  String get auswAuswaehlen => 'Select';

  @override
  String get einstKartenquellenTitel => 'Available map sources';

  @override
  String get einstKartenquellenText =>
      'How deep a map goes is up to the provider - beyond that the app only enlarges. The figure in metres is the width of a hundred screen points at mid latitudes; at 300 m you make out streets, at 20 m individual houses.';

  @override
  String get einstKartenquellenMitgeliefert => 'bundled';

  @override
  String get einstKartenquellenVorlage => 'template';

  @override
  String einstKartenquellenTiefe(String stufe, String meter) {
    return 'to level $stufe · about $meter';
  }

  @override
  String get einstKartenquellenGemessen => 'measured';

  @override
  String get einstKartenquellenLautAnbieter => 'per the provider';

  @override
  String get einstKartenquellenSchluessel => 'key required';

  @override
  String get einstKartenquellenHochaufloesend => 'serves double resolution';

  @override
  String get einstKartenquellenSimuliert => 'double resolution is simulated';

  @override
  String get einstKartenquellenKnoepfe =>
      'The button on the right makes a map the default view - for a template without a key it also switches it on. The preload further down then fills the cache for exactly that map.';

  @override
  String get einstKartenquellenSeite => 'Open the provider\'s page';

  @override
  String einstKartenquellenSeiteFehler(String adresse) {
    return 'The page could not be opened: $adresse';
  }

  @override
  String get einstKartenquellenStandard => 'default';

  @override
  String get einstKartenquellenAlsStandard => 'Make default';

  @override
  String get einstKartenquellenAlsStandardHinweis =>
      'Show this map the next time the map view is opened';

  @override
  String einstKartenquellenStandardGesetzt(String name) {
    return '$name will be the default view from the next time the map is opened.';
  }

  @override
  String get einstKartenquellenUebernehmen => 'Use this';

  @override
  String get einstKartenquellenUebernehmenHinweis =>
      'Turn this source on as your own map and make it the default';

  @override
  String einstKartenquellenUebernommen(String name) {
    return '$name is switched on and will be the default view from the next time the map is opened.';
  }

  @override
  String get einstKartenquellenEintragen => 'Fill in';

  @override
  String get einstKartenquellenEintragenHinweis =>
      'Write this template into the form below - the key will still be missing';

  @override
  String einstKartenquellenEingetragen(String name) {
    return '$name is in the form below. Enter your key and save.';
  }

  @override
  String get aufgDatumsherkunftTitel => 'Where capture dates come from';

  @override
  String get aufgDatumsherkunftText =>
      'Looks inside every file for an actual capture date. Where there is none, the date comes from the file system – from the last copy, not from the shutter. Those photos are marked and kept out of memories and bursts. The same pass reads the time-zone offset that every fourth file carries.';

  @override
  String get werkzPruefeDatumsherkunft =>
      'Checking where capture dates come from …';

  @override
  String get werkzAlleDatumGeprueft => 'Every photo has already been checked.';

  @override
  String get infoDatumGeschaetzt => 'Date is a guess – the file carries none';

  @override
  String get infoDatumGeschaetztKurz => 'estimated';

  @override
  String get sucheDatumGeschaetzt => 'Only with an estimated date';

  @override
  String get ortVorschlagTitel => 'Places from neighbours';

  @override
  String get ortVorschlagErklaerung =>
      'These photos carry no place – but the ones taken just before and after do, and they agree. Places taken over are marked as inherited: they are a reasoned guess, not a measurement.';

  @override
  String get ortVorschlagKeine => 'No photo can be placed from its neighbours.';

  @override
  String ortVorschlagAnzahl(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n photos',
      one: '1 photo',
    );
    return '$_temp0';
  }

  @override
  String ortVorschlagBegruendung(int nachbarn, int minuten) {
    String _temp0 = intl.Intl.pluralLogic(
      nachbarn,
      locale: localeName,
      other: '$nachbarn placed neighbours',
      one: '1 placed neighbour',
    );
    return '$_temp0, at most $minuten minutes away';
  }

  @override
  String ortVorschlagAlleUebernehmen(int n) {
    return 'Take all $n';
  }

  @override
  String get ortVorschlagAlleFrageTitel => 'Take all suggestions?';

  @override
  String ortVorschlagAlleFrage(int gruppen, int aufnahmen) {
    return '$gruppen groups with $aufnahmen photos in total will get the place of their neighbours. The place stays marked as inherited and can be removed individually.';
  }

  @override
  String get ortVorschlagWerkzTitel => 'Inherit places from neighbours';

  @override
  String get ortVorschlagWerkzText =>
      'Photos without a place whose neighbours in time were all at the same spot.';

  @override
  String get infoOrtGeerbt => 'Inherited from neighbouring photos';

  @override
  String get aufgVideobilderTitel => 'Videos: more than one still';

  @override
  String get aufgVideobilderText =>
      'A video used to be analysed from a single still frame. From ten seconds of runtime, up to five frames spread over its length are analysed – for search, tags and faces. The frames are not kept.';

  @override
  String get werkzVideobilder => 'Analysing further stills …';

  @override
  String get werkzAlleVideobilder => 'Every video has already been checked.';

  @override
  String get suchoptIso => 'ISO';

  @override
  String get startFehlerTitel => 'The library could not be opened';

  @override
  String get startFehlerText =>
      'Photo Vault encountered an error during startup. The technical details can help diagnose it.';

  @override
  String get startFehlerErneut => 'Try again';

  @override
  String get befehlspaletteTitel => 'Find a command';

  @override
  String get befehlspaletteHinweis => 'Enter a section or tool';

  @override
  String get befehlspaletteLeer => 'No matching command';

  @override
  String get kuerzelBefehlspalette => 'Open the command palette';

  @override
  String get gesundheitTitel => 'Library health';

  @override
  String get gesundheitWerkzeugText =>
      'Check backups, database, storage and local models together.';

  @override
  String get gesundheitEinleitung =>
      'These checks show whether the library is complete, backed up and ready to work.';

  @override
  String get gesundheitAktualisieren => 'Refresh health';

  @override
  String get gesundheitDatenbank => 'Database';

  @override
  String get gesundheitDatenbankOk => 'SQLite reports no structural errors.';

  @override
  String get gesundheitDatenbankFehler => 'SQLite reported a structural error.';

  @override
  String get gesundheitIntegritaetOeffnen => 'Check all files';

  @override
  String get gesundheitSicherung => 'Automatic backup';

  @override
  String get gesundheitSicherungAus => 'Automatic backup is turned off.';

  @override
  String get gesundheitSicherungNie =>
      'Automatic backup is configured but has never completed successfully.';

  @override
  String gesundheitLetzteSicherung(String datum) {
    return 'Last successful run: $datum';
  }

  @override
  String gesundheitSicherungOffen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl photos are waiting for backup.',
      one: '1 photo is waiting for backup.',
      zero: 'All current photos are backed up.',
    );
    return '$_temp0';
  }

  @override
  String get gesundheitSpeicher => 'Storage use';

  @override
  String get gesundheitSpeicherWirdGezaehlt => 'counting …';

  @override
  String gesundheitMedien(int fotos, int videos) {
    return '$fotos photos, $videos videos';
  }

  @override
  String get gesundheitModelle => 'Local features';

  @override
  String gesundheitModelleStand(int bereit, int gesamt) {
    return '$bereit of $gesamt local data and AI features are ready.';
  }

  @override
  String get gesundheitOrteTitel => 'Places to inherit';

  @override
  String gesundheitOrteOffen(int anzahl) {
    return '$anzahl item(s) without a place have a located neighbour close in time.';
  }

  @override
  String get gesundheitOrteAnsehen => 'Review suggestions';

  @override
  String get gesundheitGesichterTitel => 'Faces without a person';

  @override
  String gesundheitGesichterOffen(int anzahl) {
    return '$anzahl detected face(s) belong to nobody yet. Under People they can be assigned in groups.';
  }

  @override
  String get gesundheitGesichterZuordnen => 'Go to People';

  @override
  String get gesundheitDatumTitel => 'Questionable capture dates';

  @override
  String gesundheitDatumOffen(int anzahl) {
    return '$anzahl item(s) carry a timestamp on the full hour – with a real shutter time about two would. The run looks into the file for what is actually there.';
  }

  @override
  String get gesundheitDatumPruefen => 'Check date origin';

  @override
  String get gesundheitVideobilderTitel => 'Videos judged from one frame';

  @override
  String gesundheitVideobilderOffen(int anzahl) {
    return '$anzahl video(s) run longer than ten seconds and are still searched by their first frame alone.';
  }

  @override
  String get gesundheitVideobilderHolen => 'Fetch more frames';

  @override
  String get stufeWiedererkennung => 'Recognition';

  @override
  String get aufgWiedererkennungTitel => 'Who might this be?';

  @override
  String get aufgWiedererkennungText =>
      'Compares unnamed faces with the named people and suggests who might be shown. Nothing is assigned – that stays your decision.';

  @override
  String get werkzWiedererkennung => 'Compare faces';

  @override
  String get werkzAlleVerglichen => 'All faces have already been compared.';

  @override
  String get gesundheitVorschlaegeTitel => 'Recognised faces are waiting';

  @override
  String gesundheitVorschlaegeOffen(int anzahl) {
    return '$anzahl unnamed face(s) resemble a named person closely enough for a suggestion.';
  }

  @override
  String get gesundheitVorschlaegeAnsehen => 'Review suggestions';

  @override
  String get vorschlaegeTitel => 'Who might this be?';

  @override
  String get vorschlaegeEinleitung =>
      'Suggested, not assigned. You see per person what recognition found, and you decide.';

  @override
  String vorschlaegeAnzahl(int anzahl) {
    return '$anzahl suggestion(s)';
  }

  @override
  String get vorschlaegeKeine => 'There are no suggestions at the moment.';

  @override
  String get vorschlaegeBeiseite => 'Include set-aside faces';

  @override
  String get vorschlaegeBeiseiteHinweis =>
      'You set these faces aside once – back then some of today\'s people did not exist yet. This is what recognition finds among them now.';

  @override
  String get vorschlaegeBeiseiteLeer =>
      'Recognition finds nothing among the set-aside faces.';

  @override
  String get vorschlaegeLaufHinweis =>
      'Nothing compared yet. The run \\u201cWho might this be?\\u201d fills this list.';

  @override
  String get gesundheitBeiseiteTitel => 'Set-aside faces, never compared';

  @override
  String gesundheitBeiseiteOffen(int anzahl) {
    return '$anzahl set-aside face(s) have never been compared with your named people – they were set aside before those people existed.';
  }

  @override
  String get gesundheitBeiseiteAnsehen => 'Take a look';

  @override
  String get vorschlaegeJetztVergleichen => 'Compare now';

  @override
  String vorschlaegeBeiseiteNieVerglichen(int anzahl) {
    return '$anzahl set-aside face(s) have never been compared. The pass changes nothing – it only says which of them might belong to a named person.';
  }

  @override
  String get vorschlaegeLaeuft => 'The pass is running …';

  @override
  String get datenschutzExportTitel => 'Privacy export';

  @override
  String get datenschutzExportText =>
      'JPEG up to 2048 pixels without EXIF, GPS or XMP; known faces and detected license plates are obscured locally.';

  @override
  String datenschutzAusgelassen(int anzahl) {
    return '$anzahl item(s) left out: videos and images that cannot be re-rendered cannot be stripped of their metadata.';
  }

  @override
  String get sicherTeilenTitel => 'Encrypted sharing package';

  @override
  String get sicherTeilenText =>
      'Share originals and file names in one password-protected .pvshare file.';

  @override
  String get sicherTeilenZiel => 'Save sharing package';

  @override
  String get sicherTeilenDateiname => 'PhotoVault-Share.pvshare';

  @override
  String sicherTeilenFertig(String pfad) {
    return 'Encrypted sharing package saved: $pfad';
  }

  @override
  String sicherTeilenFehler(String fehler) {
    return 'Could not create the sharing package: $fehler';
  }

  @override
  String get einstPrivateMetadatenTitel => 'Protect private metadata';

  @override
  String get einstPrivateMetadatenText =>
      'Removes file names, dates, locations, descriptions, tags, and album assignments for newly locked items from the readable database. The values are encrypted with the vault key and restored when the item is permanently unlocked.';

  @override
  String get gesundheitBereinigen => 'Clean temporary files';

  @override
  String gesundheitBereinigt(int anzahl, String groesse) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: 'Removed $anzahl temporary files ($groesse).',
      one: 'Removed 1 temporary file ($groesse).',
      zero: 'No temporary leftovers found.',
    );
    return '$_temp0';
  }

  @override
  String get sicherTeilenImportTitel => 'Open sharing package';

  @override
  String get sicherTeilenImportText =>
      'Verify, decrypt, and import a password-protected .pvshare file into this library.';

  @override
  String get sicherTeilenImportPassphrase => 'Sharing package passphrase';

  @override
  String sicherTeilenImportFertig(int importiert, int duplikate) {
    return 'Imported $importiert items and skipped $duplikate duplicates.';
  }

  @override
  String sicherTeilenImportFehler(String fehler) {
    return 'Could not open sharing package: $fehler';
  }
}
