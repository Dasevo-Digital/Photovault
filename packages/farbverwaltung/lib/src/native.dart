@DefaultAsset('package:farbverwaltung/src/native.dart')
library;

import 'dart:ffi';

@Native<Int32 Function(Pointer<Uint8>, Uint32)>(symbol: 'pv_farbe_profil')
external int profil(Pointer<Uint8> daten, int laenge);

@Native<
  Int32 Function(
    Pointer<Uint8>,
    Pointer<Uint8>,
    Uint32,
    Pointer<Uint8>,
    Uint32,
    Pointer<Uint8>,
    Uint32,
    Pointer<Uint8>,
    Uint32,
    Uint32,
    Uint32,
  )
>(symbol: 'pv_farbe_transform')
external int transform(
  Pointer<Uint8> eingang,
  Pointer<Uint8> ausgang,
  int pixel,
  Pointer<Uint8> quellprofil,
  int quelllaenge,
  Pointer<Uint8> zielprofil,
  int ziellaenge,
  Pointer<Uint8> druckprofil,
  int drucklaenge,
  int flags,
  int intent,
);

@Native<Uint32 Function(Uint32, Pointer<Uint8>, Uint32)>(
  symbol: 'pv_farbe_standardprofil',
)
external int standardprofil(int typ, Pointer<Uint8> daten, int kapazitaet);

@Native<Pointer<Char> Function()>(symbol: 'pv_farbe_lizenz')
external Pointer<Char> lizenz();
