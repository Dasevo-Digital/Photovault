# Privacy Policy

As of 2 September 2026 · Photo Vault 3.3.1

## In short

Photo Vault is a photo manager that runs **on your own computer**. There
is no user account, no sign-in and no server operated by the publisher.
Photos, videos, face recognition, tags, places and the family tree stay
local. There is **no telemetry, no analytics and no advertising**.

Network connections happen only where listed below, and all of them
except map tiles require an explicit action on your part.

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
Thunderforest or Mapbox. The last three need an access key you supply
yourself. Tiles are cached locally; an area once loaded is not requested
again.

**Image recognition models.** Only when you download them explicitly in
Settings, from `huggingface.co` and `github.com`.

**Place data.** Only when you download it explicitly in Settings, from
`download.geonames.org`.

**Locating yourself.** Only when you press the location button on the
map. On Windows and macOS the app asks the operating system's location
service, which transmits identifiers of nearby Wi-Fi networks to
Microsoft or Apple respectively; their privacy policy then applies. The
feature does not exist on Linux.

**Nothing else.** The app does not check for updates, does not report
crashes and sends no identifiers.

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

## Responsible party

    <insert name and contact address here>

Questions about this policy go to the same address.
