import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Hängt der Rechner am Netzteil, und wie lange hat niemand etwas
/// eingegeben? Für die Rechenhilfe (#120, siehe `rechenpause`).
///
/// **Ohne Hilfsprogramme.** Im Sandkasten von macOS darf die App kein
/// Programm starten (`pmset` fiele aus); gefragt wird deshalb direkt über
/// FFI – IOKit und CoreGraphics unter macOS, kernel32 und user32 unter
/// Windows. Unter Linux genügt `/sys/class/power_supply`; den Leerlauf
/// kennt dort nur die jeweilige Oberfläche (X11, Wayland), und so bleibt
/// er unbekannt.
///
/// `null` heisst überall: lässt sich nicht sagen.
abstract final class Rechnerzustand {
  /// Ob der Leerlauf hier messbar ist – sonst bietet die Einstellung
  /// „nur unbenutzt“ gar nicht erst an.
  static bool get leerlaufMessbar => Platform.isMacOS || Platform.isWindows;

  static bool? amNetzteil() {
    try {
      if (Platform.isMacOS) return _mac.amNetzteil();
      if (Platform.isWindows) return _windows.amNetzteil();
      if (Platform.isLinux) return amNetzteilLinux(Directory(_linuxStrom));
    } catch (e) {
      debugPrint('Stromversorgung nicht lesbar: $e');
    }
    return null;
  }

  static Duration? ohneEingabe() {
    try {
      if (Platform.isMacOS) return _mac.ohneEingabe();
      if (Platform.isWindows) return _windows.ohneEingabe();
    } catch (e) {
      debugPrint('Leerlauf nicht lesbar: $e');
    }
    return null;
  }

  static const _linuxStrom = '/sys/class/power_supply';

  /// Wie Linux es sagt: Ein `Mains`-Eintrag mit `online` = 1 heisst
  /// Netzteil, einer mit 0 heisst Akku. Ohne jeden Akku (ein Arbeitsplatz-
  /// rechner) ist er immer am Netz. Öffentlich für den Test, mit einem
  /// nachgebauten Ordner.
  @visibleForTesting
  static bool? amNetzteilLinux(Directory ordner) {
    if (!ordner.existsSync()) return null;
    bool? netz;
    var akku = false;
    for (final e in ordner.listSync()) {
      String? lies(String name) {
        final f = File(p.join(e.path, name));
        return f.existsSync() ? f.readAsStringSync().trim() : null;
      }

      switch (lies('type')) {
        case 'Mains':
          final online = lies('online');
          if (online == '1') return true;
          if (online == '0') netz = false;
        case 'Battery':
          akku = true;
      }
    }
    if (netz != null) return netz;
    return akku ? null : true;
  }

  static final _mac = _Mac();
  static final _windows = _Windows();
}

class _Mac {
  late final _restzeit =
      DynamicLibrary.open(
        '/System/Library/Frameworks/IOKit.framework/IOKit',
      ).lookupFunction<Double Function(), double Function()>(
        'IOPSGetTimeRemainingEstimate',
      );

  late final _sekundenSeit =
      DynamicLibrary.open(
        '/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics',
      ).lookupFunction<
        Double Function(Int32, Uint32),
        double Function(int, int)
      >('CGEventSourceSecondsSinceLastEventType');

  /// `kIOPSTimeRemainingUnlimited` (-2) heisst: am Netz – auch bei einem
  /// Rechner ganz ohne Akku. Auf Akku kommt die Restzeit in Sekunden oder
  /// `kIOPSTimeRemainingUnknown` (-1), solange sie noch geschätzt wird.
  bool amNetzteil() => _restzeit() == -2.0;

  /// `kCGEventSourceStateCombinedSessionState` (0) und
  /// `kCGAnyInputEventType` (alle Bits gesetzt).
  Duration ohneEingabe() =>
      Duration(milliseconds: (_sekundenSeit(0, 0xFFFFFFFF) * 1000).round());
}

class _Windows {
  late final _kernel = DynamicLibrary.open('kernel32.dll');
  late final _user = DynamicLibrary.open('user32.dll');

  late final _anlegen = _kernel
      .lookupFunction<
        Pointer<Uint8> Function(Uint32, IntPtr),
        Pointer<Uint8> Function(int, int)
      >('LocalAlloc');
  late final _freigeben = _kernel
      .lookupFunction<
        Pointer<Void> Function(Pointer<Uint8>),
        Pointer<Void> Function(Pointer<Uint8>)
      >('LocalFree');
  late final _stromstand = _kernel
      .lookupFunction<
        Int32 Function(Pointer<Uint8>),
        int Function(Pointer<Uint8>)
      >('GetSystemPowerStatus');
  late final _letzteEingabe = _user
      .lookupFunction<
        Int32 Function(Pointer<Uint8>),
        int Function(Pointer<Uint8>)
      >('GetLastInputInfo');
  late final _takt = _kernel.lookupFunction<Uint32 Function(), int Function()>(
    'GetTickCount',
  );

  static const _nullen = 0x40; // LMEM_ZEROINIT

  T _mitSpeicher<T>(int bytes, T Function(Pointer<Uint8> s) tue) {
    final s = _anlegen(_nullen, bytes);
    if (s == nullptr) throw StateError('LocalAlloc');
    try {
      return tue(s);
    } finally {
      _freigeben(s);
    }
  }

  /// `SYSTEM_POWER_STATUS`: Byte 0 ist `ACLineStatus` (0 Akku, 1 Netz,
  /// 255 unbekannt), Byte 1 `BatteryFlag` (128: kein Akku).
  bool? amNetzteil() => _mitSpeicher(12, (s) {
    if (_stromstand(s) == 0) return null;
    if (s[1] == 128) return true;
    return switch (s[0]) {
      0 => false,
      1 => true,
      _ => null,
    };
  });

  /// `LASTINPUTINFO` { cbSize = 8, dwTime }; die Zeit ist die von
  /// `GetTickCount` und läuft nach 49 Tagen über.
  Duration? ohneEingabe() => _mitSpeicher(8, (s) {
    s.cast<Uint32>()[0] = 8;
    if (_letzteEingabe(s) == 0) return null;
    final ms = (_takt() - s.cast<Uint32>()[1]) & 0xFFFFFFFF;
    return Duration(milliseconds: ms);
  });
}
