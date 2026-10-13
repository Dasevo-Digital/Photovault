import 'dart:io';

/// Die Adresse eines Servers aus dem, was jemand eintippt:
/// `fotos.example.de` → `https://fotos.example.de/`. Ohne Schema gilt
/// HTTPS; am Ende steht immer `/`, weil die Pfade der API daran hängen.
/// `null`, wenn es keine Adresse ist.
Uri? serveradresseAus(String text) {
  var t = text.trim();
  if (t.isEmpty) return null;
  if (!t.contains('://')) t = 'https://$t';
  final u = Uri.tryParse(t);
  if (u == null || u.host.isEmpty) return null;
  if (u.scheme != 'https' && u.scheme != 'http') return null;
  return u.replace(path: u.path.endsWith('/') ? u.path : '${u.path}/');
}

/// Ob [adresse] ohne TLS angesprochen werden darf.
///
/// Nur im eigenen Netz: Sonst gingen Name, Passwort und das Token im
/// Klartext über fremde Leitungen. Zum eigenen Netz zählt, was iOS mit
/// `NSAllowsLocalNetworking` ohne TLS durchlässt – Namen ohne Punkt und
/// `.local` –, dazu Adressen aus den privaten Bereichen: Heimnetz,
/// Loopback, Link-Local und der Bereich aus RFC 6598, den VPNs wie
/// Tailscale vergeben. Android lässt Klartext zu; die Grenze zieht diese
/// Prüfung, auf allen Geräten dieselbe.
bool ohneTlsErlaubt(Uri adresse) {
  if (adresse.scheme == 'https') return true;
  final host = adresse.host.toLowerCase();
  final ip = InternetAddress.tryParse(host);
  if (ip == null) return !host.contains('.') || host.endsWith('.local');
  if (ip.isLoopback || ip.isLinkLocal) return true;
  final b = ip.rawAddress;
  if (ip.type == InternetAddressType.IPv6) return (b[0] & 0xfe) == 0xfc;
  // Die Bereiche als Zahlen statt als Text: Im Quelltext stünden sonst
  // Adressen, die wie die eines echten Heimnetzes aussehen.
  return b[0] == 10 ||
      (b[0] == 172 && (b[1] & 0xf0) == 16) ||
      (b[0] == 192 && b[1] == 168) ||
      (b[0] == 100 && (b[1] & 0xc0) == 64);
}
