/// Wohin „Photo Vault unterstützen“ führt – am Rechner unter Einstellungen →
/// Über, auf dem Telefon und im Browser unter Konto
/// (packages/server/web/index.html, `konto-unterstuetzen`).
const unterstuetzenAdresse = 'https://ko-fi.com/superkuh86';

/// Ob diese Fassung für einen App-Store gebaut ist – mit
/// `--dart-define=PV_STORE=true`.
///
/// Apple und Google lassen Trinkgeld in einer App nur über ihre eigene
/// Bezahlung zu; ein Link zu Ko-fi wäre dort ein Grund zur Ablehnung. In
/// solchen Fassungen bleibt „Photo Vault unterstützen“ deshalb aus. Die
/// Weboberfläche ist keine Store-App und zeigt ihn immer.
const fuerAppStore = bool.fromEnvironment('PV_STORE');
