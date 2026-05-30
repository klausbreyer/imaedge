# Imaedge

## Why this exists

Because we now live in times where you can build a solution faster than you can spend time being annoyed about the problem, I built imaedge.

The problem was simple, and we have had it on every trip so far: my wife and I want to collect our photos together, but none of the usual options really fits.

Apple does not work for us because shared photo albums compress the images. Google Photos does not work either because you always have to sync everything. On top of that, we need the images back in their original quality afterwards, so we can fill WordPress with them while we are on the road and later turn them into a photo album.

With imaedge, anyone can create a secret link and share it with others. Everyone with the link can upload photos into a shared collection, and the original files stay intact.

You can also adjust the order of the images by changing the date from the EXIF data. I paid special attention to the upload itself too: images are uploaded in small chunks. In the places where we often travel, reception is bad. Normal uploads take forever, break, or leave you guessing what state the upload is actually in.

imaedge is open source, in case you want to host it for yourself.

If you ever want to collect original photos together, without accounts, without compression, without constant syncing, and without a lot of fuss: that is what this is built for.

## Warum es das gibt

Weil wir inzwischen in Zeiten leben, in denen man schneller eine Lösung gebaut hat, als man sich lange über das Problem aufregt, habe ich imaedge gebaut.

Das Problem war einfach, und wir hatten es bisher in jedem Urlaub: Meine Frau und ich wollen unsere Fotos gemeinsam sammeln, aber keine der üblichen Lösungen passt so richtig.

Apple funktioniert für uns nicht, weil geteilte Fotoalben die Bilder komprimieren. Google Fotos funktioniert auch nicht, weil man immer alles synchronisieren muss. Noch dazu brauchen wir die Bilder danach wieder im Original, um von unterwegs WordPress damit zu befüllen und später ein Fotoalbum daraus zu machen.

Damit kann jeder einen geheimen Link erstellen und mit anderen teilen. Alle mit dem Link können Fotos in eine gemeinsame Sammlung hochladen, und die Originaldateien bleiben erhalten.

Man kann außerdem die Reihenfolge der Bilder anpassen, indem man das Datum aus den EXIF-Daten ändert. Besonders wichtig war mir auch der Upload selbst: Die Bilder werden in kleine Chunks aufgeteilt hochgeladen. Gerade dort, wo wir oft Urlaub machen, ist der Empfang schlecht. Normale Uploads dauern ewig, brechen ab, oder man weiß nicht, in welchem Zustand sie gerade sind.

imaedge ist Open Source, falls ihr es für euch selbst aufsetzen wollt.

Falls ihr also mal gemeinsam Originalfotos sammeln wollt, ohne Account, ohne Komprimierung, ohne dauerndes Synchronisieren und ohne großes Theater: Dafür ist es gebaut.

## Local development

Install dependencies and set up the database:

```sh
mix setup
```

Local development can use the local filesystem object store, or the same Tigris object storage path as production.

For Tigris-backed local development, create a local env file from `.env.example` and fill in the Tigris dev bucket credentials:

```sh
cp .env.example .env.local
```

The dev bucket currently used by the project is:

```text
imaedge-dev-local
```

The dev bucket custom domain is:

```text
https://dev-assets.imaedge.org
```

Load the local env file before starting Phoenix, for example:

```sh
set -a
source .env.local
set +a
mix phx.server
```

Without `BUCKET_NAME`, development falls back to `priv/static/objects`.

## Fly production

The production Fly app is:

```text
imaedge
```

The production Tigris bucket is:

```text
imaedge-prod
```

Deployments use `fly.toml`, run release migrations, and keep Oban inside the app process.

Required Fly secrets:

```text
DATABASE_URL
SECRET_KEY_BASE
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_ENDPOINT_URL_S3
AWS_REGION
BUCKET_NAME
```

Public object URLs are configured in `fly.toml` with:

```text
TIGRIS_PUBLIC_BASE_URL=https://assets.imaedge.org
```

The production bucket custom domain setup is:

```sh
flyctl storage update imaedge-prod --custom-domain assets.imaedge.org
```

DNS needs a CNAME record:

```text
assets.imaedge.org CNAME imaedge-prod.t3.tigrisbucket.io
```

Keep the CNAME in place so Tigris can issue and renew TLS certificates. If the domain is managed through Cloudflare or a similar DNS provider, keep the record in DNS-only mode so TLS terminates at Tigris.

The dev bucket uses the same setup:

```sh
flyctl storage update imaedge-dev-local --custom-domain dev-assets.imaedge.org
```

DNS needs this CNAME record:

```text
dev-assets.imaedge.org CNAME imaedge-dev-local.t3.tigrisbucket.io
```

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
