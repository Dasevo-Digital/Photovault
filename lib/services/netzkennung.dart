/// Wie sich Photo Vault bei fremden Servern ausweist.
///
/// Die Kartenanbieter (OpenStreetMap, OpenTopoMap, die Höhen- und
/// Luftbildkacheln, Overpass) bitten um einen `User-Agent`, an dem sie die
/// Anwendung erkennen. Bis 3.19.0 stand dort `com.example.photoVault` – der
/// Platzhalter aus der Flutter-Vorlage, den tausende Probe-Apps genauso
/// tragen. Wer ihn sperrt, sperrt alle auf einmal; und erkennen lässt sich
/// an ihm niemand.
///
/// Die Kennung ist bewusst nur der Produktname: kein Rechnername, keine
/// Adresse, nichts, was auf den Nutzer zurückführt. Die Bündelkennung der
/// installierten App bleibt davon unberührt – sie trägt den Datenordner der
/// Bibliothek und wird hier nicht angefasst.
const String netzkennung = 'PhotoVault';

/// Der Kopf, den flutter_map aus `TileLayer.userAgentPackageName` baut
/// (`flutter_map (<Kennung>)`). Wer Kacheln an der Bibliothek vorbei selbst
/// holt, schickt denselben, damit der Anbieter beide Wege als einen sieht.
const String kartenNetzkennung = 'flutter_map ($netzkennung)';
