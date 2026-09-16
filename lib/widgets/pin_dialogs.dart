import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'namens_dialog.dart'
    show MitTextsteuerung, MitTextsteuerungen;

import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../services/meldungsdienst.dart';

/// Fragt einen PIN ab (z.B. um den gesperrten Ordner zu öffnen oder eine
/// Änderung zu bestätigen). Gibt `null` zurück, wenn abgebrochen wurde.
/// `maxLength` deckt auch schon bestehende, mit einer älteren (4-6-stelligen)
/// Richtlinie eingerichtete PINs ab – siehe [showSetPinDialog].
Future<String?> showEnterPinDialog(BuildContext context, {String? title}) async {
  // Vorgabewert erst hier: im Kopf gibt es noch keinen Kontext. Als lokale
  // Variable, weil ein Parameter innerhalb des Builder-Closures unten nicht
  // als „sicher nicht null" gilt.
  final titel = title ?? AppTexte.of(context).pinEingebenTitel;
  // Die Steuerung gehört dem Fenster, nicht diesem Aufruf – siehe
  // [MitTextsteuerung]. Gerade hier: Ein Absturz beim Ausblenden träfe
  // die Eingabe zum gesperrten Ordner.
  final result = await showDialog<String>(
    context: context,
    builder: (context) => MitTextsteuerung(
        builder: (context, ctrl) => AlertDialog(
      title: Text(titel),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 10,
        decoration: InputDecoration(labelText: AppTexte.of(context).pinFeld, counterText: ''),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(AppTexte.of(context).allgAbbrechen)),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('OK')),
            ],
            )),
  );
  return result;
}

/// Lässt einen neuen PIN zweimal eingeben (Bestätigung), validiert
/// clientseitig auf 8-10 Ziffern und Übereinstimmung. Mindestlänge bewusst
/// auf 8 angehoben (statt zuvor 6) – bei einem exfiltrierten
/// `library.sqlite` lässt sich der verpackte Master-Key offline durchprobieren,
/// ganz ohne Sperre nach Fehlversuchen (die es bei einer rein lokalen App ohne
/// Server naturgemäß nicht geben kann). Selbst mit dem bewusst kostspieligen
/// Argon2id (siehe VaultCrypto) bleibt ein 6-stelliger PIN (nur 1 Million
/// Kombinationen) in einem für einen entschlossenen Angreifer praktikablen
/// Zeitrahmen knackbar; 8 Stellen (100 Millionen Kombinationen) verschieben
/// das in einen deutlich unpraktikableren Bereich, ohne die App auf ein
/// alphanumerisches Passwort umzustellen. Gibt den neuen PIN zurück oder
/// `null` bei Abbruch.
Future<String?> showSetPinDialog(BuildContext context) async {
  String? error;
  final result = await showDialog<String>(
    context: context,
    builder: (context) => MitTextsteuerungen(
      anzahl: 2,
      builder: (context, felder) {
        final pinCtrl = felder[0];
        final confirmCtrl = felder[1];
        return StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(AppTexte.of(context).pinFestlegenTitel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pinCtrl,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 10,
              decoration: InputDecoration(
                  labelText: AppTexte.of(context).pinNeuFeld, counterText: ''),
            ),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 10,
              decoration: InputDecoration(
                  labelText: AppTexte.of(context).pinWiederholen, counterText: ''),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(error!, style: TextStyle(
                        color: Theme.of(context).colorScheme.error, fontSize: 12)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Text(
                AppTexte.of(context).pinWarnung,
                style: TextStyle(fontSize: 12, color: context.semantik.warnung),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(AppTexte.of(context).allgAbbrechen)),
          FilledButton(
            onPressed: () {
              final pin = pinCtrl.text.trim();
              final confirm = confirmCtrl.text.trim();
              if (pin.length < 8 || pin.length > 10 || int.tryParse(pin) == null) {
                setState(() => error = AppTexte.of(context).pinZiffernFehler);
                return;
              }
              if (pin != confirm) {
                setState(() => error = AppTexte.of(context).pinUngleich);
                return;
              }
              Navigator.pop(context, pin);
            },
            child: Text(AppTexte.of(context).allgFestlegen),
          ),
        ],
      ),
        );
      },
    ),
  );
  return result;
}

/// Sorgt dafür, dass der Master-Key des gesperrten Ordners für die laufende
/// Sitzung im Speicher vorliegt: fragt bei Bedarf den PIN ab, oder führt bei
/// noch nicht eingerichtetem PIN direkt durch die Einrichtung. Wird sowohl
/// beim Sperren eines Fotos (Vollbildansicht) als auch beim Öffnen des
/// gesperrten Ordners (Einstellungen) aufgerufen – dank
/// [LibraryState.vaultUnlockedThisSession] muss dadurch nicht mehrfach pro
/// Sitzung nach dem PIN gefragt werden. Gibt `true` zurück, wenn der
/// gesperrte Ordner danach entsperrt ist.
Future<bool> ensureVaultUnlocked(BuildContext context, LibraryState library) async {
  if (library.vaultUnlockedThisSession) return true;

  if (!await library.db.hasPinSet()) {
    if (!context.mounted) return false;
    final pin = await showSetPinDialog(context);
    if (pin == null) return false;
    await library.setupVaultPin(pin);
    return true;
  }

  if (!context.mounted) return false;
  final pin = await showEnterPinDialog(context);
  if (pin == null) return false;
  try {
    await library.unlockVaultWithPin(pin);
    return true;
  } catch (_) {
    if (context.mounted) {
      melde.warnung(AppTexte.of(context).pinFalsch);
    }
    return false;
  }
}

/// Fragt eine Backup-Passphrase ab (z.B. um verschlüsselte Backups zu
/// entsperren). Anders als der PIN des gesperrten Ordners bewusst kein
/// Zahlenfeld/keine Längenbegrenzung – ein Backup liegt oft langfristig
/// extern (Cloud-Ordner, externe Platte), eine kurze PIN wäre dafür zu
/// schwach. Gibt `null` zurück, wenn abgebrochen wurde.
Future<String?> showEnterPassphraseDialog(BuildContext context,
    {String? title}) async {
  final titel = title ?? AppTexte.of(context).einstBackupPassphraseEingeben;
  final result = await showDialog<String>(
    context: context,
    builder: (context) => MitTextsteuerung(
        builder: (context, ctrl) => AlertDialog(
      title: Text(titel),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        obscureText: true,
        decoration: InputDecoration(labelText: AppTexte.of(context).passphraseFeld),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(AppTexte.of(context).allgAbbrechen)),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('OK')),
            ],
            )),
  );
  return result;
}

/// Lässt eine neue Backup-Passphrase zweimal eingeben (Bestätigung),
/// validiert clientseitig auf mindestens 8 Zeichen und Übereinstimmung.
/// Gibt die neue Passphrase zurück oder `null` bei Abbruch.
Future<String?> showSetPassphraseDialog(BuildContext context) async {
  String? error;
  final result = await showDialog<String>(
    context: context,
    builder: (context) => MitTextsteuerungen(
      anzahl: 2,
      builder: (context, felder) {
        final passCtrl = felder[0];
        final confirmCtrl = felder[1];
        return StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(AppTexte.of(context).passphraseFestlegenTitel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: passCtrl,
              autofocus: true,
              obscureText: true,
              decoration:
                  InputDecoration(labelText: AppTexte.of(context).passphraseNeuFeld),
            ),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              decoration:
                  InputDecoration(labelText: AppTexte.of(context).passphraseWiederholen),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(error!, style: TextStyle(
                        color: Theme.of(context).colorScheme.error, fontSize: 12)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Text(
                AppTexte.of(context).passphraseWarnung,
                style: TextStyle(fontSize: 12, color: context.semantik.warnung),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(AppTexte.of(context).allgAbbrechen)),
          FilledButton(
            onPressed: () {
              final pass = passCtrl.text;
              final confirm = confirmCtrl.text;
              if (pass.length < 8) {
                setState(() => error = AppTexte.of(context).passphraseZuKurz);
                return;
              }
              if (pass != confirm) {
                setState(() => error = AppTexte.of(context).passphraseUngleich);
                return;
              }
              Navigator.pop(context, pass);
            },
            child: Text(AppTexte.of(context).allgFestlegen),
          ),
        ],
      ),
        );
      },
    ),
  );
  return result;
}

/// Sorgt dafür, dass der Backup-Master-Key für die laufende Sitzung im
/// Speicher vorliegt – analog zu [ensureVaultUnlocked], aber für die
/// Backup-Verschlüsselung (eigene Passphrase, eigener Schlüssel). Wird vor
/// jedem manuellen oder automatischen verschlüsselten Backup aufgerufen.
Future<bool> ensureBackupKeyAvailable(BuildContext context, LibraryState library) async {
  if (library.backupKeyAvailableThisSession) return true;

  if (!await library.db.hasBackupKey()) {
    if (!context.mounted) return false;
    final pass = await showSetPassphraseDialog(context);
    if (pass == null) return false;
    await library.setupBackupPassphrase(pass);
    return true;
  }

  if (!context.mounted) return false;
  final pass = await showEnterPassphraseDialog(context);
  if (pass == null) return false;
  try {
    await library.unlockBackupKeyWithPassphrase(pass);
    return true;
  } catch (_) {
    if (context.mounted) {
      melde.warnung(AppTexte.of(context).passphraseFalsch);
    }
    return false;
  }
}
