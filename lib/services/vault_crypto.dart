import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Größe der Klartext-Chunks beim Ver-/Entschlüsseln einer Datei – erlaubt
/// Streaming mit konstantem Speicherbedarf, auch für mehrere Gigabyte große
/// Videos, statt eine Datei komplett in den Speicher zu laden.
const int _chunkSize = 1 << 20; // 1 MiB

/// Länge des AES-256-GCM-Authentifizierungs-Tags in Bytes.
const int _macLength = 16;

/// Erste Fassung des Dateiformats: jeder Block für sich authentifiziert,
/// aber nichts sichert ihre Reihenfolge. Wird nur noch gelesen.
const List<int> _magicV1 = [0x50, 0x56, 0x45, 0x31]; // "PVE1"

/// Zweite Fassung: jeder Block trägt seine laufende Nummer als
/// mitauthentifizierte Zusatzdaten, und ein Abschlussblock hält fest, wie
/// viele es waren.
const List<int> _magicV2 = [0x50, 0x56, 0x45, 0x32]; // "PVE2"

/// Ergebnis von [VaultCrypto.createMasterKey]/[VaultCrypto.wrapMasterKey]:
/// alles, was zusätzlich zum Master-Key selbst in [PrivacySettings]
/// gespeichert werden muss, um ihn später mit demselben PIN wieder
/// entpacken zu können.
class WrappedMasterKey {
  final SecretKey masterKey;
  final Uint8List kdfSalt;
  final Uint8List nonce;
  final Uint8List wrapped;
  const WrappedMasterKey({
    required this.masterKey,
    required this.kdfSalt,
    required this.nonce,
    required this.wrapped,
  });
}

/// AES-256-GCM-Dateiverschlüsselung + PIN-basiertes "Envelope Encryption"
/// für den gesperrten Ordner (siehe Klassenkommentar in [PrivacySettings]).
///
/// Architektur: ein einmalig zufällig erzeugter 256-Bit-"Master-Key"
/// verschlüsselt tatsächlich die Dateien. Der PIN selbst verschlüsselt (=
/// "wrapped") nur diesen Master-Key – über Argon2id, damit ein Angreifer mit
/// Zugriff auf die Datenbank nicht einfach alle 10.000-1.000.000
/// PIN-Kombinationen durchprobieren kann. Der Vorteil dieser Trennung: ein
/// PIN-Wechsel muss nur den (kurzen) Master-Key neu verpacken, nicht alle
/// Dateien neu verschlüsseln.
///
/// WICHTIG: Es gibt bewusst keine Wiederherstellung ohne PIN – wer den PIN
/// vergisst, kann die gesperrten Fotos nicht mehr entschlüsseln. Das ist der
/// Preis für echte Verschlüsselung statt eines reinen Anzeige-Filters.
class VaultCrypto {
  VaultCrypto._();

  static final AesGcm _cipher = AesGcm.with256bits();
  static const _bytesMagic = <int>[0x50, 0x56, 0x42, 0x31]; // PVB1

  /// Bewusst moderate statt maximale Argon2id-Parameter: die reine
  /// Dart-Implementierung (keine native Beschleunigung, siehe pubspec.yaml)
  /// wäre bei OWASP-Empfehlungswerten spürbar langsam beim Entsperren. Immer
  /// noch deutlich widerstandsfähiger gegen Offline-Brute-Force als ein
  /// einfacher, schneller Hash.
  static final Argon2id _kdf = Argon2id(
    parallelism: 1,
    memory: 65536, // 64 MiB
    iterations: 3,
    hashLength: 32,
  );

  static Uint8List _randomBytes(int length) {
    final rnd = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rnd.nextInt(256)));
  }

  static Future<SecretKey> _deriveWrappingKey(String pin, List<int> salt) =>
      _kdf.deriveKeyFromPassword(password: pin, nonce: salt);

  /// Erzeugt einen neuen zufälligen Master-Key und verpackt ihn direkt mit
  /// [pin] – für die Erst-Einrichtung des gesperrten Ordners.
  static Future<WrappedMasterKey> createMasterKey(String pin) async {
    final masterKey = await _cipher.newSecretKey();
    return wrapMasterKey(masterKey, pin);
  }

  /// Verpackt einen (neuen oder bestehenden) Master-Key mit [pin] – für die
  /// Erst-Einrichtung und für einen PIN-Wechsel (dort mit dem unverändert
  /// bleibenden, bereits vorhandenen Master-Key).
  static Future<WrappedMasterKey> wrapMasterKey(
      SecretKey masterKey, String pin) async {
    final salt = _randomBytes(16);
    final wrappingKey = await _deriveWrappingKey(pin, salt);
    final masterKeyBytes = await masterKey.extractBytes();
    final nonce = _cipher.newNonce();
    final box = await _cipher.encrypt(masterKeyBytes,
        secretKey: wrappingKey, nonce: nonce);
    return WrappedMasterKey(
      masterKey: masterKey,
      kdfSalt: salt,
      nonce: Uint8List.fromList(nonce),
      wrapped: Uint8List.fromList([...box.cipherText, ...box.mac.bytes]),
    );
  }

  /// Entpackt den Master-Key mit [pin]. Wirft [SecretBoxAuthenticationError],
  /// wenn der PIN falsch ist (GCM-Authentifizierung schlägt fehl) – das ist
  /// zugleich die einzige PIN-Prüfung der App, es gibt keinen separat
  /// gespeicherten PIN-Hash mehr.
  static Future<SecretKey> unwrapMasterKey(
    String pin, {
    required List<int> kdfSalt,
    required List<int> nonce,
    required List<int> wrapped,
  }) async {
    final wrappingKey = await _deriveWrappingKey(pin, kdfSalt);
    final cipherText = wrapped.sublist(0, wrapped.length - _macLength);
    final mac = Mac(wrapped.sublist(wrapped.length - _macLength));
    final box = SecretBox(cipherText, nonce: nonce, mac: mac);
    final masterKeyBytes = await _cipher.decrypt(box, secretKey: wrappingKey);
    return SecretKey(masterKeyBytes);
  }

  /// Authentifizierte Verschlüsselung für kleine Steuerdaten, die nie als
  /// Klartextdatei auf der Platte landen sollen (z.B. Paket-Manifeste).
  static Future<Uint8List> encryptBytes(
      List<int> clearText, SecretKey masterKey,
      {List<int> aad = const []}) async {
    final nonce = _cipher.newNonce();
    final box = await _cipher.encrypt(clearText,
        secretKey: masterKey, nonce: nonce, aad: aad);
    return Uint8List.fromList(
        [..._bytesMagic, ...nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  static Future<Uint8List> decryptBytes(
      List<int> encrypted, SecretKey masterKey,
      {List<int> aad = const []}) async {
    if (encrypted.length < 4 + 12 + _macLength ||
        !_bytesEqual(encrypted.sublist(0, 4), _bytesMagic)) {
      throw const FormatException('Keine gültigen verschlüsselten Daten.');
    }
    final nonce = encrypted.sublist(4, 16);
    final cipherText = encrypted.sublist(16, encrypted.length - _macLength);
    final mac = Mac(encrypted.sublist(encrypted.length - _macLength));
    return Uint8List.fromList(await _cipher.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: masterKey,
      aad: aad,
    ));
  }

  /// Die laufende Nummer eines Blocks als mitauthentifizierte Zusatzdaten.
  ///
  /// Sie steht nicht in der Datei – beide Seiten zählen mit. Dadurch passt
  /// ein an eine andere Stelle geschobener Block nicht mehr: Die
  /// Authentifizierung schlägt fehl, obwohl der Block selbst unverändert
  /// ist.
  static Uint8List _blockNummer(int nummer) =>
      (ByteData(8)..setUint64(0, nummer, Endian.big)).buffer.asUint8List();

  /// Verschlüsselt [source] blockweise nach [destination].
  ///
  /// Dateiformat: 4 Bytes Magic ("PVE2"), danach Blöcke aus je
  /// [4 Bytes Klartextlänge][12 Bytes Nonce][Chiffretext][16 Bytes GCM-Tag].
  /// Jeder Block ist für sich authentifiziert UND an seine laufende Nummer
  /// gebunden; den Schluss bildet ein leerer Abschlussblock, dessen Nummer
  /// die Anzahl der Datenblöcke ist.
  ///
  /// Der Abschlussblock ist der Grund für das neue Format: Ohne ihn liess
  /// sich eine Datei am Ende kürzen, ohne dass es beim Entschlüsseln
  /// auffiel – jeder verbliebene Block war ja gültig. Er wird auch für eine
  /// leere Quelldatei geschrieben, damit „gar keine Blöcke" nie ein
  /// gültiger Zustand ist.
  static Future<void> encryptFile(
      File source, File destination, SecretKey masterKey) async {
    final input = await source.open(mode: FileMode.read);
    final sink = destination.openWrite();
    try {
      sink.add(_magicV2);

      Future<void> schreibe(List<int> klartext, int nummer) async {
        final nonce = _cipher.newNonce();
        final box = await _cipher.encrypt(klartext,
            secretKey: masterKey, nonce: nonce, aad: _blockNummer(nummer));
        final header = ByteData(4)..setUint32(0, klartext.length, Endian.big);
        sink.add(header.buffer.asUint8List());
        sink.add(nonce);
        sink.add(box.cipherText);
        sink.add(box.mac.bytes);
      }

      var nummer = 0;
      while (true) {
        final chunk = await input.read(_chunkSize);
        if (chunk.isEmpty) break;
        await schreibe(chunk, nummer);
        nummer++;
      }
      await schreibe(const <int>[], nummer);
      await sink.flush();
    } finally {
      await input.close();
      await sink.close();
    }
  }

  /// Entschlüsselt eine mit [encryptFile] erzeugte Datei. Wirft
  /// [FormatException] bei falschem Datei-Format bzw.
  /// [SecretBoxAuthenticationError], wenn ein Chunk manipuliert/beschädigt
  /// ist oder der falsche Master-Key übergeben wurde.
  static Future<void> decryptFile(
      File source, File destination, SecretKey masterKey) async {
    final input = await source.open(mode: FileMode.read);
    final sink = destination.openWrite();
    var vollstaendig = false;
    try {
      final magic = await input.read(4);
      final istV2 = magic.length == 4 && _bytesEqual(magic, _magicV2);
      final istV1 = magic.length == 4 && _bytesEqual(magic, _magicV1);
      if (!istV1 && !istV2) {
        throw const FormatException(
            'Keine gültige verschlüsselte Vault-Datei.');
      }

      var nummer = 0;
      while (true) {
        final header = await input.read(4);
        if (header.isEmpty) {
          // Vor der Umstellung gab es keinen Abschlussblock; dort ist das
          // Dateiende das Ende. Bei PVE2 fehlt hier etwas.
          if (istV1) break;
          throw const FormatException(
              'Die Datei endet vor dem Abschlussblock – sie wurde abgeschnitten.');
        }
        if (header.length != 4) {
          throw const FormatException('Unvollständiger Blockkopf.');
        }
        final plainLength = ByteData.sublistView(Uint8List.fromList(header))
            .getUint32(0, Endian.big);
        // Die Länge steht unverschlüsselt in der Datei und ist damit das
        // einzige Feld, das ein Angreifer frei setzen kann. Ohne diese
        // Schranke ginge sie ungeprüft an read() – bis zu 4 GiB für einen
        // Block, der höchstens _chunkSize gross sein darf.
        if (plainLength > _chunkSize) {
          throw const FormatException('Unplausible Blocklänge.');
        }
        final nonce = await input.read(12);
        final cipherText = await input.read(plainLength);
        final macBytes = await input.read(_macLength);
        if (nonce.length != 12 ||
            cipherText.length != plainLength ||
            macBytes.length != _macLength) {
          throw const FormatException('Unvollständiger Block.');
        }
        final box = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
        final plain = await _cipher.decrypt(
          box,
          secretKey: masterKey,
          aad: istV2 ? _blockNummer(nummer) : const <int>[],
        );

        if (istV2 && plainLength == 0) {
          // Abschlussblock: Seine Nummer ist die Anzahl der Datenblöcke,
          // und sie ist mitauthentifiziert – ein Kürzen fällt damit auf.
          if ((await input.read(1)).isNotEmpty) {
            throw const FormatException('Daten hinter dem Abschlussblock.');
          }
          break;
        }
        sink.add(plain);
        nummer++;
      }
      await sink.flush();
      vollstaendig = true;
    } finally {
      await input.close();
      await sink.close();
      // Bricht das Entschlüsseln ab – falscher Schlüssel, beschädigte oder
      // abgeschnittene Datei –, dann steht in [destination] bereits der
      // Klartext aller Blöcke, die bis dahin durchgingen. Bei einer
      // gesperrten Datei ist das genau das, was nie auf der Platte stehen
      // soll: eine unverschlüsselte Teilkopie, die kein Aufrufer je wieder
      // anfasst, weil er die Ausnahme sieht und nicht die Datei.
      //
      // Gemessen an einem 3-MiB-Foto, dem die letzten 40 Byte fehlten:
      // 2 MiB lesbarer Klartext blieben liegen (Prüfrunde 8).
      if (!vollstaendig && await destination.exists()) {
        try {
          await destination.delete();
        } catch (_) {
          // Ein fehlgeschlagenes Aufräumen darf den eigentlichen Fehler
          // nicht verdecken – der Aufrufer soll erfahren, warum das
          // Entschlüsseln scheiterte, nicht warum das Löschen scheiterte.
        }
      }
    }
  }

  /// Billiger Sanity-Check für die Bibliotheks-Integritätsprüfung: prüft nur
  /// die ersten 4 Bytes (Magic Header), ohne den Rest zu entschlüsseln. Ein
  /// [SecretKey] wird bewusst nicht gebraucht – geht nicht um Entschlüsseln,
  /// sondern nur darum, offensichtlich beschädigte/verkürzte Dateien zu
  /// erkennen (z.B. durch einen abgebrochenen Schreibvorgang).
  static Future<bool> hasValidEncryptedHeader(File file) async {
    final raf = await file.open(mode: FileMode.read);
    try {
      final magic = await raf.read(4);
      if (magic.length != 4) return false;
      return _bytesEqual(magic, _magicV2) || _bytesEqual(magic, _magicV1);
    } finally {
      await raf.close();
    }
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
