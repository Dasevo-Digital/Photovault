part of 'befehl.dart';

/// Ein neues Album. Die Kennung vergibt, wer den Befehl erzeugt – so kann
/// ein Gerät offline weiterarbeiten und das Album gleich füllen.
final class AlbumAnlegen extends Befehl<void> {
  const AlbumAnlegen(this.albumId, this.name, this.angelegtAm);

  static AlbumAnlegen aus(Map<String, Object?> w) => AlbumAnlegen(
    w['albumId']! as String,
    w['name']! as String,
    DateTime.parse(w['angelegtAm']! as String),
  );

  final String albumId;
  final String name;
  final DateTime angelegtAm;

  @override
  String get art => 'albumAnlegen';

  @override
  Map<String, Object?> get werte => {
    'albumId': albumId,
    'name': name,
    'angelegtAm': angelegtAm.toIso8601String(),
  };

  @override
  Future<void> anwenden(AppDatabase db) => db.createAlbum(
    AlbumsCompanion.insert(id: albumId, name: name, createdAt: angelegtAm),
  );
}

/// Aufnahmen in ein Album legen.
final class AlbumFuellen extends Befehl<void> {
  const AlbumFuellen(this.albumId, this.ids);

  static AlbumFuellen aus(Map<String, Object?> w) =>
      AlbumFuellen(w['albumId']! as String, _kennungen(w['ids']));

  final String albumId;
  final List<String> ids;

  @override
  String get art => 'albumFuellen';

  @override
  Map<String, Object?> get werte => {'albumId': albumId, 'ids': ids};

  @override
  Future<void> anwenden(AppDatabase db) => db.addAssetsToAlbum(albumId, ids);
}

/// Aufnahmen aus einem Album nehmen; mit [albumLoeschen] auch das Album –
/// wenn es erst für diese Aktion angelegt wurde.
final class AusAlbumNehmen extends Befehl<void> {
  const AusAlbumNehmen(this.albumId, this.ids, {this.albumLoeschen = false});

  static AusAlbumNehmen aus(Map<String, Object?> w) => AusAlbumNehmen(
    w['albumId']! as String,
    _kennungen(w['ids']),
    albumLoeschen: w['albumLoeschen']! as bool,
  );

  final String albumId;
  final List<String> ids;
  final bool albumLoeschen;

  @override
  String get art => 'ausAlbumNehmen';

  @override
  Map<String, Object?> get werte => {
    'albumId': albumId,
    'ids': ids,
    'albumLoeschen': albumLoeschen,
  };

  @override
  Future<void> anwenden(AppDatabase db) => ids.length == 1 && !albumLoeschen
      ? db.removeAssetFromAlbum(albumId, ids.single)
      : db.nimmAusAlbum(albumId, ids, albumLoeschen: albumLoeschen);
}

/// Das Titelbild eines Albums; `null` nimmt die Wahl zurück.
final class AlbumTitelbildSetzen extends Befehl<void> {
  const AlbumTitelbildSetzen(this.albumId, this.id);

  static AlbumTitelbildSetzen aus(Map<String, Object?> w) =>
      AlbumTitelbildSetzen(w['albumId']! as String, w['id'] as String?);

  final String albumId;
  final String? id;

  @override
  String get art => 'albumTitelbildSetzen';

  @override
  Map<String, Object?> get werte => {'albumId': albumId, 'id': id};

  @override
  Future<void> anwenden(AppDatabase db) => db.setzeAlbumTitelbild(albumId, id);
}

/// Eine Suche als intelligentes Album merken.
final class SucheMerken extends Befehl<void> {
  const SucheMerken(this.sucheId, this.name, this.filter);

  static SucheMerken aus(Map<String, Object?> w) => SucheMerken(
    w['sucheId']! as String,
    w['name']! as String,
    SearchFilters.fromJson((w['filter']! as Map).cast<String, dynamic>()),
  );

  final String sucheId;
  final String name;
  final SearchFilters filter;

  @override
  String get art => 'sucheMerken';

  @override
  Map<String, Object?> get werte => {
    'sucheId': sucheId,
    'name': name,
    // Über Text und zurück: So steht hier, was jsonEncode daraus macht
    // (Aufzählungen als Namen, Daten als Text), und nicht ein Objekt,
    // das erst beim Versand scheitert.
    'filter': jsonDecode(jsonEncode(filter.toJson())),
  };

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.createSavedSearch(sucheId, name, filter);
}

/// Eine gemerkte Suche vergessen.
final class SucheVergessen extends Befehl<void> {
  const SucheVergessen(this.sucheId);

  static SucheVergessen aus(Map<String, Object?> w) =>
      SucheVergessen(w['sucheId']! as String);

  final String sucheId;

  @override
  String get art => 'sucheVergessen';

  @override
  Map<String, Object?> get werte => {'sucheId': sucheId};

  @override
  Future<void> anwenden(AppDatabase db) => db.deleteSavedSearch(sucheId);
}
