import 'befehlsbasis.dart';

/// Nur die entschlüsselte Ansicht einer offenen oder abgelehnten Änderung.
/// Die dauerhaften Fälle und Vorschaudaten liegen verschlüsselt auf dem Gerät.
class Abgleichsfall {
  const Abgleichsfall({
    required this.kennung,
    required this.am,
    required this.befehl,
    required this.basis,
    this.grund,
    this.ausstehend = false,
    this.lesbar = true,
  });
  final String kennung;
  final DateTime am;
  final Map<String, Object?> befehl;
  final List<Befehlsbasis> basis;
  final String? grund;
  final bool ausstehend, lesbar;
  List<String> get fotoIds => basis.expand((b) => b.fotos).toSet().toList();
}

class Abgleichsvergleich {
  const Abgleichsvergleich({
    required this.fall,
    required this.serverwerte,
    required this.stand,
    required this.geschuetzt,
    required this.entfernt,
    required this.fotonamen,
    this.fotobezeichnungen = const {},
  });
  final Abgleichsfall fall;
  final List<Map<String, Object?>?> serverwerte;
  final String stand;
  final bool geschuetzt, entfernt;
  final List<String> fotonamen;
  final Map<String, String> fotobezeichnungen;
}

class AbgleichsstandGeaendert implements Exception {
  const AbgleichsstandGeaendert();
}

class AbgleichsserverZuAlt implements Exception {
  const AbgleichsserverZuAlt();
}
