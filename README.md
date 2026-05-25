# Imaedge

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
