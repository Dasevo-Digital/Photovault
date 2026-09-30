# Privacy Policy

As of 30 September 2026 · Photo Vault 3.18.1

## In short

Photo Vault is a photo manager that runs **on your own computer**. There
is no user account, no sign-in and no server operated by the publisher.
Photos, videos, face recognition, tags, places and the family tree stay
local. There is **no telemetry, no analytics and no advertising**.

Network connections happen only where listed below. Map and terrain data
are loaded when you open the corresponding view; every other request
requires an explicit action on your part.

## Where things are kept

**Your library** – photos, videos, database, backups – lives in the
folder you choose. Without a choice of your own it lives in the app's
data folder:

- Windows (unpacked build): `%APPDATA%\com.example\photo_vault\`
- Windows (Store build): `%LOCALAPPDATA%\Packages\…\LocalCache\Roaming\com.example\photo_vault\`
- macOS: `~/Library/Containers/…/PhotoVault/`
- Linux: `~/.var/app/…/PhotoVault/`

**Locked photos** are encrypted with AES-256-GCM; the key is derived
from your password (Argon2id) and never leaves the machine. Losing the
password means losing access – there is no back door and no recovery by
the publisher.

## When the app uses the network

**Map tiles.** Opening the map, a trip, an activity or the terrain view
loads map sections from the chosen tile service. This transmits the
requested tile coordinates and your IP address. The coordinates reveal
which area you are looking at – and therefore, indirectly, where your
photos were taken. Depending on your setting the service is
OpenStreetMap, OpenTopoMap, CyclOSM, Esri/ArcGIS, CARTO, MapTiler,
Thunderforest, Mapbox or Google Maps. Several commercial providers need an
access key you supply yourself. Tiles are cached locally; an area once loaded
is not requested again.

**Terrain and hiking information.** Opening the corresponding views loads
elevation data from AWS Open Data and hiking routes from Waymarked Trails.
When you request hiking objects, the app queries the Overpass API. These
requests disclose your IP address and the viewed map section or queried area.
Responses are cached locally where the respective feature supports it.

**Image recognition models.** Only when you download them explicitly in
Settings, from `huggingface.co` and `github.com`.

**Place data.** Only when you download it explicitly in Settings, from
`download.geonames.org`.

**Update check.** Only when you explicitly press “Check for updates” in
Settings. The app requests the public release list from `api.github.com`.
This transmits the technically necessary IP address and ordinary HTTP request,
but no library data. The app does not check automatically and never installs
an update itself.

**Locating yourself.** Only when you press the location button on the
map. On Windows and macOS the app asks the operating system's location
service, which transmits identifiers of nearby Wi-Fi networks to
Microsoft or Apple respectively; their privacy policy then applies. The
feature does not exist on Linux.

**No telemetry.** The app does not report crashes, measure usage, or send its
own device or user identifiers.

## Processing by artificial intelligence

Face recognition, tagging, image captioning, text recognition and search
by image content run **entirely on your computer**. No image and no crop
is transmitted to any service. Models are downloaded once and run
locally afterwards.

## Your rights

Since the publisher collects, stores and processes no personal data
whatsoever, there is nothing held by the publisher to disclose or
delete. Your data is yours. Delete the library by deleting its folder;
remove the app the usual way for your operating system.

## Responsibility and contact

Photo Vault operates no account system and no processing server of its own.
For the exclusively local library, the user determines purpose, contents and
deletion. During the requests listed above, the respective third-party
provider processes technically necessary connection data under its own privacy
terms.

Questions and privacy reports can be submitted without publishing personal
contact details through the issue tracker of the official project repository.
Anyone distributing Photo Vault through a store or under their own
organisation must add their own serviceable contact details and any further
mandatory information before publication.
