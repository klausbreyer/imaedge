# AGENTS.md

This file is the working context for AI agents in the imaedge repository.

## Hard Rules

- Never use em dashes in any output or committed text. Use commas, parentheses, colons, or separate sentences.
- Do not print secrets from `.env`, Fly secrets, Tigris credentials, or database credentials.
- Do not revert user changes unless the user explicitly asks for that.
- Prefer small, scoped changes. Keep unrelated refactors out of task work.
- When starting in a new worktree, first update main from the remote and rebase the current branch onto the updated main before beginning task work, unless the user explicitly says otherwise.
- Use `rg` for searching.
- Use `apply_patch` for manual file edits.
- Run `mix precommit` before handing off code changes when feasible.

## Product

imaedge is a generic mobile web tool for collecting original-quality photos from multiple people into one secret-link collection.

The product deliberately does not model trips, days, albums, titles, accounts, owners, or roles. A collection is just a secret ID with images.

Core routes:

- `/` creates a new collection after the user clicks the create button.
- `/i/<collection_id>` is the shared collection page.
- `/i/<collection_id>/export` is the HTML export page with previews and original links.

Access model:

- There is no login.
- There is no admin role.
- Whoever knows the collection URL can view, upload, delete, sort, retry failed uploads, remove failed uploads, and export.
- Collection IDs must be long, Base62, URL-safe, and without hyphens.
- Collection pages should not be discoverable. Keep `noindex`, no public lists, and no sitemap paths.

Supported files:

- JPEG
- PNG
- WebP

Videos are out of scope for the MVP. Live Photos are not guaranteed through browser upload. Store whatever image file the browser provides.

## Stack

The stack is fixed for this project:

- Phoenix
- Postgres hosted outside Fly
- Fly.io for the Phoenix app
- Tigris object storage
- Oban inside the Phoenix app process
- One Phoenix node for the MVP
- Phoenix Channels for realtime updates
- Polling fallback every 15 seconds
- Own resumable chunk upload API, no `tusd`
- Minimal JavaScript, vanilla unless a real need appears

Do not introduce Cloudflare for this project unless the user explicitly changes the decision.

## Local Development

Use the Makefile:

```sh
make prepare
make test
make start
```

`make start` loads `/Users/kb0/versioned/imaedge/.env`, runs migrations, and starts Phoenix.

The local dev environment is not hosted. It should behave like production as much as practical, including object storage.

Important local files:

- `.env`, local credentials, ignored, do not print it
- `.env.example`, placeholder configuration
- `sqlca.pem`, database CA certificate for SSL verification
- `.codex/environments/environment.toml`, Codex actions copied from the onsetto style

If the user asks to stop the server, stop any running local Phoenix process and let the user restart it manually.

## Production

Fly app:

- `imaedge`

Fly org:

- `klaus-imaedge-breyer`

Tigris buckets:

- Production: `imaedge-prod`
- Local development: `imaedge-dev-local`

Deployment uses `fly.toml` and the Dockerfile. Release migrations are run through `Imaedge.Release`.

Required production secrets:

- `DATABASE_URL`
- `SECRET_KEY_BASE`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_ENDPOINT_URL_S3`
- `AWS_REGION`
- `BUCKET_NAME`

The database URL uses SSL verification. The CA file is copied into the image as `/app/sqlca.pem`.

## Storage Model

Postgres stores metadata and status.

Tigris stores:

- Original image files
- Small previews
- Large previews

Original files must be stored unchanged. Do not rewrite EXIF metadata in the MVP.

Temporary upload chunks are stored on the Phoenix app server filesystem. They do not need to survive restarts or deploys. If temp files disappear, the client can restart while it still has the file in IndexedDB.

Object key pattern:

```text
collections/<collection_id>/<image_secret>/original.<ext>
collections/<collection_id>/<image_secret>/preview-small.webp
collections/<collection_id>/<image_secret>/preview-large.webp
```

`image_secret` is independent from the public image ID and must not be reused.

The Tigris bucket may be public for direct object URLs, but object paths must be unguessable and bucket listing must not be public.

## Upload Flow

Uploads use a persistent local browser queue.

Client behavior:

- Store selected files in IndexedDB before upload starts.
- Compute SHA-256 locally.
- Upload only after local storage and hashing both succeeded.
- Reject exact duplicates in the same local queue.
- Ask the server for duplicate SHA-256 in the same collection before upload.
- Show free browser storage using `navigator.storage.estimate()`.
- Free IndexedDB storage after successful finalize or after the server reports that the upload is already accepted.
- Default parallel uploads to 1.
- Let the user change parallel uploads in the interface.
- Background upload is best effort only. Resume is the guarantee.

Server behavior:

- The server owns the chunk size.
- Initial chunk size is 1 MiB.
- Chunks are addressed by numeric index.
- Re-uploading the same chunk index is allowed and overwrites the temp chunk.
- Final SHA-256 verification is the integrity check.
- Chunk presence is derived from temp files, not from Postgres.
- Finalize is a separate request.
- Finalize must be idempotent once the original was accepted.
- Once a session is `processing` or `done`, chunk uploads must not move it back to `uploading`.

Finalize sequence:

1. Client creates upload session.
2. Client uploads chunks.
3. Client can query missing chunks.
4. Client sends finalize.
5. Server assembles the local temp file.
6. Server verifies SHA-256.
7. Server uploads original to Tigris.
8. Server creates processing image state.
9. Server enqueues Oban ingest.

Finalize responds only after the original is in Tigris and the ingest job has been started.

## Ingest

Ingest runs in Oban.

Ingest should:

- Fetch original from Tigris.
- Verify the image is decodable.
- Read selected EXIF fields when available.
- Generate small WebP preview.
- Generate large WebP preview.
- Upload previews to Tigris.
- Mark image as complete.
- Broadcast realtime updates.

Ingest failure policy:

- Retry automatically through Oban.
- After final failure, keep the original in Tigris.
- Show the failed upload in the server processing area, not in the gallery.
- Any user with the collection link can retry or remove a failed upload.
- Removing a failed upload should delete the related Tigris objects.

## Sorting And Time

The gallery sorts by `effective_taken_at`, then ID.

Timestamp source:

- Use EXIF time if present.
- Fall back to upload time if EXIF time is unavailable.
- Store upload time as metadata, but do not rewrite the original file.

Manual reorder updates metadata in the database. Do not mutate EXIF for sorting.

If adjacent images have different time zones, convert through UTC before calculating a new midpoint.

## UI Guidelines

This is a tool, not a marketing page.

- Keep the interface direct and usable on mobile.
- Do not add a landing page unless the user explicitly asks.
- Keep JavaScript minimal and local to the feature.
- Prefer vanilla JS for upload queue behavior.
- Keep the debug log client-side and copyable.
- Do not create nested card layouts.
- Avoid decorative visual noise.
- Gallery preview click opens a larger preview.
- Per-image download button downloads the original.
- Preview grids should stay visible while actions are available.

## Phoenix And Elixir Conventions

- Use existing Phoenix patterns in this repo.
- Use `Req` for HTTP requests. Do not add `httpoison`, `tesla`, or `httpc`.
- Use Ecto changesets and queries instead of ad hoc SQL unless there is a clear reason.
- Use `DateTime`, `NaiveDateTime`, `Time`, and `Calendar` from the standard library unless a dependency is already present.
- Do not call `String.to_atom/1` on user input.
- Do not use `Process.sleep/1` in tests when a deterministic synchronization approach is available.
- Use `mix ecto.gen.migration name_with_underscores` for new migrations.
- Prefer focused tests around upload, storage, and ingest invariants.

## Current Areas That Are Sensitive

Be careful around:

- Tigris SigV4 signing in `Imaedge.Storage.Tigris`.
- Idempotent finalize behavior in `Imaedge.Uploads`.
- IndexedDB queue cleanup in `assets/js/upload_queue.js`.
- Hetzner Postgres SSL config in `Imaedge.Repo.RuntimeConfig`.
- Oban worker behavior in `Imaedge.Workers.IngestWorker`.

## Useful Checks

Common commands:

```sh
mix compile
mix test
mix precommit
make start
```

Manual Tigris-backed upload checks should use `.env`, but never print its contents:

```sh
set -a
source .env
set +a
mix run -e 'IO.inspect(:ok)'
```

When testing a stuck upload, inspect collection, upload session, image state, and Oban jobs before changing code.
