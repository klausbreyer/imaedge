# imaedge MVP Specification

## Goal

imaedge is a generic mobile web tool for collecting original-quality photos from multiple people into one secret-link collection.

The tool does not model trips, days, albums, titles, accounts, or roles. A collection is just an ID with images.

Primary pain points:

- Avoid sending photos between phones before publishing.
- Make uploads resilient on bad mobile connections.
- Keep original files unchanged.
- Allow multiple contributors through one shared URL.
- Provide enough control and debug visibility to trust what happened.

## Product Model

- `/` shows a button to create a new collection.
- A collection is created only after button click.
- Collection URL: `/i/<collection_id>`.
- Collection ID is 24 to 32 Base62 characters, URL-safe, without hyphens.
- Collections are nameless and permanent, even when empty.
- There is no account system and no separate admin role.
- Whoever knows `/i/<collection_id>` can view, upload, delete, sort, retry failed uploads, remove failed uploads, and export.
- All collection pages are `noindex`.
- There are no public collection lists, no sitemap entries, and no crawlable discovery paths.

## Supported Files

MVP supports images only:

- JPEG
- PNG
- WebP

Videos are out of scope for the MVP.

Live Photos are not guaranteed as Live Photos through browser upload. The system stores whatever image file the browser provides.

Original files are stored unchanged. The MVP does not rewrite EXIF metadata.

## Stack

The MVP stack is fixed:

- Phoenix
- Postgres, hosted externally on own infrastructure
- Phoenix on Fly.io
- Tigris object storage
- Oban running inside the Phoenix app process
- One Phoenix node in the MVP
- Phoenix Channels for realtime updates
- Polling fallback every 15 seconds
- Own resumable chunk upload API, no `tusd`

Postgres is initially publicly reachable with TLS. A private network or VPN can be considered later.

## Storage

Postgres stores metadata and status.

Tigris stores:

- Original image files
- Small previews
- Large previews

Temporary upload chunks are stored on the Phoenix app server filesystem. They do not need to survive restarts or deploys. If they disappear, the client can restart upload from its local copy while it still has one.

The MVP uses one Phoenix node. Multi-node upload support is out of scope.

Object keys are grouped by collection and image secret:

```text
collections/<collection_id>/<image_secret>/original.<ext>
collections/<collection_id>/<image_secret>/preview-small.webp
collections/<collection_id>/<image_secret>/preview-large.webp
```

`image_secret` is an independent 128-bit Base62 value and is never reused.

The Tigris bucket is public, with unguessable object paths. Object listing must not be publicly exposed.

Preview and original URLs are direct and durable. After hard delete, the target object should be removed. Short cache leftovers are acceptable.

## Cache Policy

Previews and originals use different cache policies.

- Previews may be cached longer.
- Originals should use a more moderate cache policy, because hard delete should stop access as soon as practical.

Exact `Cache-Control` values are implementation details.

## Upload Flow

Uploads use a persistent local browser queue.

Client-side behavior:

- Files are stored in IndexedDB before upload starts.
- SHA-256 is computed locally in parallel with IndexedDB storage.
- Upload starts only after local storage and hashing both succeeded.
- Local duplicate files within the same collection queue are rejected.
- The client checks the server for exact duplicates in the same collection before upload.
- Free local browser storage is shown in the UI using `navigator.storage.estimate()`.
- If IndexedDB cannot store the selected files, the user must choose a smaller batch.
- There is no non-persistent upload fallback in the MVP.
- Upload concurrency is user-adjustable, default 1.
- Background upload is best effort only. Resume is the real guarantee.

Upload status per file:

- Local storage
- Hashing
- Duplicate check
- Uploading
- Finalizing
- Processing
- Done
- Failed

Progress UI shows:

- Per-file percentage
- Per-file upload speed
- Per-file status
- Retry controls
- Technical error details
- Total progress

Retries:

- Automatic retry with backoff for upload failures.
- After automatic retries are exhausted, manual retry is shown.

## Chunk Upload Protocol

The server owns the chunk size and returns it when creating an upload session.

Initial chunk size:

- 1 MiB

Chunks are addressed by index:

- Chunk 0
- Chunk 1
- Chunk 2
- etc.

The same chunk index may be uploaded multiple times. The server overwrites the previous chunk. The final file SHA-256 is the integrity check.

Postgres stores coarse upload session state:

- Collection ID
- Contributor ID
- Original filename
- Size
- MIME type
- Client SHA-256
- Status
- Error information
- Created and updated timestamps

Chunk presence is derived from temp files on disk, not from Postgres.

Finalize is a separate request:

1. Client creates upload session.
2. Client uploads chunks.
3. Client can query missing chunks.
4. Client sends finalize.
5. Server assembles local temp file.
6. Server verifies SHA-256.
7. Server uploads original to Tigris.
8. Server creates or updates server-side processing state.
9. Server starts Oban ingest job.

Finalize responds only after the original is in Tigris and the ingest job has been started.

After successful finalize:

- The client may delete its IndexedDB blob copy.
- The server keeps the assembled local file while ingest is running.

After successful ingest:

- The server deletes the assembled local file.
- The image appears in the gallery.

After final ingest failure:

- The server deletes the assembled local file.
- The original remains in Tigris for retry.
- The failed upload appears in the upload/error area, not in the gallery.
- Any user with the collection link may retry or remove it.
- Removing the failed upload deletes the Tigris original.

## Ingest

Ingest is performed by Oban.

Ingest does:

- Download original from Tigris.
- Verify the original hash.
- Validate that the image is decodable.
- Read selected EXIF fields.
- Generate small WebP preview.
- Generate large WebP preview.
- Upload previews to Tigris.
- Mark image as complete.
- Broadcast realtime update.

Ingest retries:

- 3 automatic attempts with backoff.
- After final failure, the upload moves to failed state.

Image processing uses `Image` and libvips through `vix`.

EXIF is read through libvips/Image first. If this is insufficient for real phone images, a targeted EXIF tool can be added later.

## Previews

Previews are always WebP.

Sizes:

- Small preview: max 480 px longest edge
- Large preview: max 1600 px longest edge

Quality:

- Small: 70
- Large: 82

The grid uses small previews with lazy loading.

Clicking the preview opens the large preview.

Each image tile has a download button for the original.

## Metadata

The system stores targeted metadata only, not a full EXIF dump.

Image fields include:

- ID
- Collection ID
- Image secret
- Original URL
- Small preview URL
- Large preview URL
- Original hash
- Original filename
- Size
- MIME type
- Width
- Height
- Original taken time, if available
- Effective taken time
- Timezone or offset information
- Time source
- GPS fields, if available
- Contributor ID
- Status
- Uploaded timestamp

GPS is stored if available, but not shown in the MVP UI.

The original filename is stored, but not prominently displayed.

## Time And Sorting

Initial ordering:

- Use EXIF original taken time when available.
- If EXIF time has no timezone offset, use the browser/device offset at upload time.
- If no EXIF time exists, use upload time.

The system stores:

- Original taken time, if available
- Effective taken time
- Timezone or offset information
- Time source

Sorting is based on `effective_taken_at`.

Manual sorting:

- Done in the visible grid.
- Each click moves one image exactly one position earlier or later.
- Moving an image updates `effective_taken_at` by interpolating between neighboring images.
- If neighboring images have different offsets, interpolation is done using absolute instants, then displayed in the moved image's own offset.
- If timestamps collide or become too close, the implementation may redistribute nearby effective times with sufficient precision.

Direct editing:

- Users may directly edit date and time.
- Direct date/time edits wait for server confirmation.

Sort button interactions are optimistic. On server error, the UI reloads the current server state and shows an error.

## Downloads And Export

Single-image download uses a generated filename, not the raw original filename.

Filename schema:

```text
0001-YYYYMMDD-HHMMSS-originalname.ext
```

Rules:

- The number follows current gallery order.
- The timestamp uses `effective_taken_at`.
- The original filename is sanitized and length-limited.
- The original file bytes are unchanged.

Export page:

- URL: `/i/<collection_id>/export`
- Same link permission as the main collection.
- Simple HTML page.
- Images appear in current order.
- Uses preview images for display.
- Links to original files.
- No separate export token.
- Contributor ID is not shown on the export page.

The export HTML is the MVP exit path. There is no ZIP export in the MVP.

## Contributors

Each browser/device gets a global human-readable Contributor ID.

Examples:

- `quiet-harbor`
- `golden-maple`
- `silent-sunrise`

Rules:

- The Contributor ID is generated automatically.
- It is global per browser/device.
- It is not manually editable in the MVP.
- It is sent with uploads.
- It is stored per image.
- It is shown small on each image tile in `/i/<collection_id>`.
- It is not shown on `/i/<collection_id>/export`.

There is no separate contributor name.

## Gallery UI

The main collection page has separate areas:

1. Upload queue and upload/error area
2. Server-side gallery

The upload queue is local and per collection.

Finished queue entries remain visible briefly, about 5 to 10 seconds, then disappear automatically.

Newly ingested images are briefly highlighted if visible. The page does not auto-scroll.

Realtime updates are applied live. If the user is actively interacting with the grid, updates may be briefly delayed or debounced to avoid visual jumps.

## Delete Behavior

Deleting does not use a confirmation dialog.

Delete has a 10 second undo window:

- The image disappears immediately from all devices.
- Undo is only available on the device that initiated the delete.
- If undo is clicked, the image reappears via realtime update.
- After 10 seconds, original, previews, and metadata are hard deleted.

Short cache leftovers for direct object URLs are acceptable.

## Realtime

Use Phoenix Channels/WebSocket.

Realtime events include:

- Image ingested
- Image deleted
- Delete undone
- Sort changed
- Date/time changed
- Upload processing status changed
- Upload failed
- Failed upload removed

If the Channel is disconnected, clients poll every 15 seconds.

Realtime is a UX feature, not the source of consistency. On reconnect, clients reload current collection state.

## Errors And Debugging

User-facing errors should include technical details.

Errors should show:

- Friendly category where possible
- HTTP status
- Request ID
- Upload ID
- Relevant server or protocol error code

The client keeps a local readable text debug log per collection.

Debug log:

- Stored locally
- Ring-buffer style, limited size
- Shown in an expandable UI section
- Copyable as text
- Clearable by the user

No server-side product event log is part of the MVP.

Normal server logs are required:

- Request ID
- Errors
- Upload IDs where relevant
- Ingest failures

## Rate Limits

The MVP should include simple rate limits.

Limits should not block normal travel usage:

- At least 100 image uploads per day per device/contributor should be allowed.

Recommended limit dimensions:

- Collection creation per IP
- Upload session creation per IP and collection
- Finalize per IP and collection
- Delete operations per IP and collection

Hotel or shared-network scenarios should be considered when setting IP limits.

## Backups

No explicit backup strategy is part of the MVP.

This is a conscious tradeoff. The product treats collections as durable, but the MVP does not yet protect against all app bugs, accidental hard deletes, or operator mistakes.

The export HTML page is the MVP manual exit path.

## First Technical Spike

Spike goal: prove mobile upload and ingest reliability before polishing gallery UX.

Acceptance criteria:

- Test on real Mobile Safari.
- Select 5 images.
- Store selected files in IndexedDB.
- Compute SHA-256 in browser.
- Prevent local duplicates.
- Create upload session.
- Upload using 1 MiB chunks.
- Reload or interrupt mid-upload.
- Resume by detecting missing chunks.
- Finalize upload.
- Server assembles file.
- Server verifies SHA-256.
- Server uploads original to Tigris.
- Oban ingest job runs.
- libvips decodes image.
- EXIF fields are read where available.
- Small and large WebP previews are generated.
- Gallery shows completed images.
- Simulated ingest failure retries 3 times.
- Final ingest failure appears in upload/error area.
- Retry works.
- Remove failed upload deletes the temporary Tigris original.

## Explicit Non-Goals For MVP

- Accounts
- Separate owner/admin links
- Trip, day, album, or title modeling
- Videos
- Live Photo preservation guarantees
- ZIP export
- WordPress plugin
- EXIF rewriting
- Multi-node upload support
- PWA install flow
- Service Worker background upload guarantees
- Full offline gallery
- Full EXIF raw dump
- Server-side collection audit log
- Explicit backup system
