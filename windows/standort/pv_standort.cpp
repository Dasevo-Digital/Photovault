// Fragt Windows' eigene Ortung einmal ab und schreibt eine Zeile JSON.
//
// Warum ein eigenes Programm und kein Methodenkanal wie unter macOS:
// Unter Windows hat diese App bislang gar keinen nativen Kanal - alles
// Plattformnahe laeuft ueber aufgerufene Werkzeuge (heif-dec, raw-identify,
// ffmpeg), gebuendelt in DesktopImageTools. Ein eigener Prozess passt dort
// hinein und hat zwei handfeste Vorteile: Der Ortungsdienst laeuft
// gemessen mehrere Sekunden und kann haengen - in einem eigenen Prozess
// blockiert das die Oberflaeche nicht und laesst sich hart abbrechen.
//
// Ausgabe bei Erfolg (eine Zeile, reines ASCII):
//   {"breite":52.1234567,"laenge":10.1234567,"genauigkeit":19.0,"quelle":"WiFi"}
// Sonst:
//   {"fehler":"keine_erlaubnis"}   Ortung fuer Desktop-Apps abgeschaltet
//   {"fehler":"zeitgrenze"}        keine Antwort binnen zwoelf Sekunden
//   {"fehler":"0x80072ee7"}        Dienst nicht erreichbar (siehe unten)
//
// 0x80072EE7 heisst "Name nicht aufloesbar" und kam auf dem Testrechner
// nicht von Windows, sondern von einem DNS-Filter im Heimnetz, der
// inference.location.live.net auf 0.0.0.0 zeigen liess. Der Fehlercode
// wird deshalb durchgereicht statt verschluckt - er ist die einzige Spur.

#include <winrt/Windows.Devices.Geolocation.h>
#include <winrt/Windows.Foundation.h>

#include <chrono>
#include <cstdio>

using namespace winrt;
using namespace winrt::Windows::Devices::Geolocation;
using namespace winrt::Windows::Foundation;

namespace {

// Woher die Position stammt. Steht mit in der Ausgabe, weil "WiFi" und
// "IPAddress" fuer den Nutzer ein himmelweiter Unterschied sind: Der
// IP-Weg lag in der Messung 271 km daneben, bei behaupteten 25 km.
const char* QuelleName(PositionSource quelle) {
  switch (quelle) {
    case PositionSource::Cellular:   return "Cellular";
    case PositionSource::Satellite:  return "Satellite";
    case PositionSource::WiFi:       return "WiFi";
    case PositionSource::IPAddress:  return "IPAddress";
    case PositionSource::Default:    return "Default";
    case PositionSource::Obfuscated: return "Obfuscated";
    default:                         return "Unknown";
  }
}

}  // namespace

int main() {
  // Mehrfaedig (MTA): Die Abfragen unten blockieren mit .get() bzw.
  // wait_for(). Auf einem STA-Faden legte das die Nachrichtenschleife
  // lahm, die WinRT fuer genau diese Rueckrufe braucht.
  init_apartment();

  try {
    if (Geolocator::RequestAccessAsync().get() != GeolocationAccessStatus::Allowed) {
      std::printf("{\"fehler\":\"keine_erlaubnis\"}\n");
      return 2;
    }

    Geolocator geo;
    geo.DesiredAccuracyInMeters(50);

    // Dieselbe Zeitgrenze wie im macOS-Zweig (ImageConverter.swift):
    // laenger als jede erfolgreiche Abfrage hier gedauert hat.
    auto lauf = geo.GetGeopositionAsync();
    if (lauf.wait_for(std::chrono::seconds(12)) != AsyncStatus::Completed) {
      lauf.Cancel();
      std::printf("{\"fehler\":\"zeitgrenze\"}\n");
      return 4;
    }

    auto koord = lauf.GetResults().Coordinate();
    auto punkt = koord.Point().Position();
    // Accuracy ist ein double und laut Doku immer gesetzt.
    std::printf(
        "{\"breite\":%.7f,\"laenge\":%.7f,\"genauigkeit\":%.1f,\"quelle\":\"%s\"}\n",
        punkt.Latitude, punkt.Longitude, koord.Accuracy(),
        QuelleName(koord.PositionSource()));
    return 0;
  } catch (hresult_error const& fehler) {
    std::printf("{\"fehler\":\"0x%08x\"}\n",
                static_cast<unsigned int>(fehler.code().value));
    return 3;
  }
}
