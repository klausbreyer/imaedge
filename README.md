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
