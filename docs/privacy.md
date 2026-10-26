# Privacy Policy

As of 26 October 2026 · Photo Vault 3.48.2

## In short

Photo Vault is a photo manager that, without further setup, runs **on your own
computer**. This local mode needs no account or sign-in. You may optionally
operate your own Photo Vault Server or use one selected by you. A connected
library transfers its contents to that server; the mobile app and browser
interface work only with such a server. The publisher operates no central
Photo Vault service. There is **no telemetry, behavioural analytics or
advertising**.

Network connections happen where listed below. Map and terrain data are
loaded when you open the corresponding view. Downloads, location lookup,
update checks and connecting to a server require an explicit action or a
setting you previously selected.

## Where things are kept

**A local library** – photos, videos, database, backups – lives in the folder
you choose. Without a choice of your own it lives in the app's data folder:

- Windows (unpacked build): `%APPDATA%\de.dasevo\photovault\`
- Windows (Store build): `%LOCALAPPDATA%\Packages\…\LocalCache\Roaming\de.dasevo\photovault\`
- macOS: `~/Library/Containers/…/PhotoVault/`
- Linux: `~/.var/app/…/PhotoVault/`

**A connected library** is stored in full on the selected Photo Vault Server.
Desktop and mobile devices keep a local copy of the database and fetch
previews or originals when needed. Changes are synchronised with the server.
The person or organisation operating that server determines its storage,
backup, logging and access rules.

**Locked photos** are encrypted with AES-256-GCM. A random master key is
protected by a key derived from the password with Argon2id. For a local
library it never leaves the computer; for a connected library the encrypted
files are stored on the selected server. Losing the password means losing
access – there is no back door and no recovery by the publisher.

## When the app uses the network

**Map tiles.** Opening the map, a trip, an activity or the terrain view
loads map sections from the chosen tile service. This transmits the
requested tile coordinates and your IP address. The coordinates reveal
which area you are looking at – and therefore, indirectly, where your
photos were taken. Depending on your setting the service is
OpenStreetMap, OpenTopoMap, CyclOSM, Esri/ArcGIS, CARTO, MapTiler,
Thunderforest, Mapbox or Google Maps. Several commercial providers need an
access key you supply yourself. Tiles are cached locally and requested again
only once the validity stated by the service has expired (seven days if it
states none). On explicit request, Settings → Map preloads the tiles around
all photo locations; the map service then learns all areas where photos were
taken at once.

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

**Your Photo Vault Server.** Only after you enter a server address in Settings
and sign in does the desktop app send the server address, account name, device
name and sign-in data to that server. Moving or synchronising a library sends
its database, metadata, originals, previews and later changes. The server may
perform image analysis, create backups and deliver files to signed-in desktop,
mobile and browser devices. A computer configured as a compute helper receives
individual media files from the server and returns the computed results. You
choose the operator and location of this server; its privacy and logging rules
apply in addition to this policy.

**Mobile app.** The mobile app requires a Photo Vault Server. It downloads the
library database and requested previews or originals, sends changes back and,
when explicitly enabled, uploads camera-roll originals and metadata for
backup. Cached data is kept in the phone's protected application storage.

**Accounts and sign-in.** The self-operated server stores account names,
password verifiers, TOTP settings, recovery-code verifiers, device names and
hashed device tokens. You may optionally configure your own OIDC provider.
That provider then receives the ordinary authentication request; the Photo
Vault Server stores the mapping of issuer and the provider's subject
identifier. Passwords and TOTP secrets are not sent to the publisher.

After sign-in, the device stores its bearer token in its own application data
so that it can reconnect. On desktop systems it is kept separately from the
library and is readable only by the user account on macOS and Linux; on mobile
it is held in the protected application area. The token is not additionally
encrypted there. Signing out that device on the server invalidates it.

**Browser, shares and guest contributions.** The browser interface loads
library data and media from the selected server. Share links make selected
content available to anyone holding the link and, where configured, its
password. If the owner accepts guest contributions, uploaded files are first
processed on the server and stored as a sanitised copy without embedded
metadata. The server and its reverse proxy may process technically necessary
connection data such as IP address and time.

**Maps in the browser and the mobile app.** Even with your own server, the
browser interface and the mobile app fetch map tiles **directly** from the
services, not through the Photo Vault Server: the map from OpenStreetMap
(`tile.openstreetmap.org`), the terrain view and the 3D flight elevation data
from AWS Open Data, aerial imagery from Esri/ArcGIS and hiking trails from
Waymarked Trails. These services receive the device's IP address and the
requested tile coordinates, from which the area being viewed can be inferred.
Hiking objects, by contrast, are queried by the server from the Overpass API.

**Support link.** Only when you open the Ko-fi link does the browser navigate
to `ko-fi.com`; its privacy terms then apply. App-store builds do not show this
link.

**No telemetry.** The app does not report crashes, measure usage, or send its
own device or user identifiers.

## Processing by artificial intelligence

For a local library, face recognition, tagging, image captioning, text
recognition and search by image content run **entirely on your computer**. No
image is sent to an external analysis service. Models are downloaded once and
then run locally.

For a connected library, the selected Photo Vault Server performs this work.
Compute helpers you explicitly enable download individual media files from the
server and return features and descriptions. Neither local nor server mode
sends images for analysis to an artificial-intelligence service operated by
the publisher.

## Your rights

The publisher does not collect, store or process library or account data
through Photo Vault. Delete a local library by deleting its folder. For a
connected library, access, correction and deletion also depend on the person
or organisation operating the selected server. Accounts, devices and shares
can be managed there; the operator must remove server files and backups. Remove
the app in the usual way for your operating system.

## Responsibility and contact

The publisher operates no central account system and no Photo Vault Server for
users. For a local library, the user determines purpose, contents and deletion.
For a self-operated or otherwise selected server, its operator is responsible
for processing there. During the requests listed above, the respective
third-party provider processes technically necessary connection data under its
own privacy terms.

Questions and privacy reports can be submitted without publishing personal
contact details through the issue tracker of the official project repository.
Anyone distributing Photo Vault through a store or under their own
organisation must add their own serviceable contact details and any further
mandatory information before publication.
