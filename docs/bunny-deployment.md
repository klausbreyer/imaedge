# Bunny deployment

The migration follows `texttile/demo-bunny`: one instance in Germany, a mounted
volume to serialize replacements, immutable image digests, WebSockets, and no
CDN caching. Unlike Texttile, imaedge has no SQLite database or permanent image
files on the app server to transfer. Hetzner Postgres stays in place. Image
objects are copied from Tigris to Bunny Storage without changing their keys.

## Pipeline

Bunny app ID: `7h8OXpOEr3k6dyw`. Pull Zone: `6820180`.
Endpoint: `mc-2bwurpor46.bunny.run`. Production CNAME target:
`mc-2bwurpor46.b-cdn.net`.

Migration state on 2026-10-17: public DNS points to Bunny, the production
certificate is issued, and HTTPS is enforced. The deployment key is configured
in GitHub. Fly's ingest queue was paused and drained before stopping its Machine
and disabling automatic starts and restarts. The pipeline now enables Bunny
workers and startup migrations. Hetzner Postgres remains unchanged.

`.github/workflows/deploy.yml` runs `mix precommit` and deployment safeguard tests,
then publishes `ghcr.io/klausbreyer/imaedge:<commit SHA>` for Linux AMD64.
Build provenance is disabled so Bunny and GitHub compare the same image digest.
When `BUNNY_APP_ID` is set, it updates the existing Bunny container and waits for
one pod on the requested image digest to be ready. Image or runtime changes
require a replacement; a new tag for the same image can keep the existing pod.
Running deployments are never cancelled by newer pushes.
During migration, the `migrate-to-bunny` branch also runs this pipeline.

Configure the deployment key through the hidden CLI prompt:

```sh
gh secret set BUNNYNET_API_KEY --repo klausbreyer/imaedge
gh variable set BUNNY_APP_ID --repo klausbreyer/imaedge --body '<APP_ID>'
```

Application secrets were copied from Fly once and remain in Bunny. The pipeline
preserves the signing key, database URL, and admin login. It resolves storage
credentials from the Bunny zone identified by `storage` in `bunny.json` and
updates the S3 settings together with the image. Only that zone's credentials
and public settings are replaced. No additional GitHub storage secret is needed.
Do not use the local `.env`, which points to the development bucket.

## Container and networking

- One container named `app`, shared compute, min/max replicas both 1, region `DE` only.
- A 1 GB `single-instance` volume mounted at `/var/lib/imaedge`. No application data
  is stored there. Bunny uses it to stop the old pod before starting a replacement.
- Upload chunks stay temporary. Interrupted uploads can resume from browser storage.
- TCP startup and readiness checks on port 8080, with HTTP from CDN to origin.
- CDN endpoint with WebSockets enabled, caching disabled, and HTTPS enforced.
- `www.imaedge.org` points to the Bunny CDN hostname, DNS-only in Cloudflare.
- The apex redirect stays in place. The two asset domains use their storage Pull Zones.

Updates briefly interrupt connections. Do not enable autoscaling or add regions:
upload chunks and Phoenix PubSub are local to one node.

## Handoff

1. Publish the image through GitHub Actions.
2. Create the Bunny app with the existing production secrets, `OBAN_ENABLED=false`,
   and `RUN_MIGRATIONS=false`. Fly continues processing jobs during validation.
3. Validate Bunny HTTP, database access, Tigris access, and WebSocket upgrades.
4. Issue the `www.imaedge.org` certificate using Bunny's external DNS validation
   before replacing the Cloudflare `www` records. Preserve the old records for rollback.
5. Switch `www` to Bunny. Wait for the old DNS TTL and existing connections to drain.
6. Pause the Fly ingest queue and wait for running jobs to finish. Disable Fly
   automatic starts and restart policy, then stop its Machine.
7. Set `OBAN_ENABLED=true` and `RUN_MIGRATIONS=true` in `bunny.json` and deploy through
   GitHub Actions. Verify upload processing before completing the migration.

## Object storage

| Environment | Storage zone | Pull Zone | Location | Public CNAME |
| --- | --- | --- | --- | --- |
| Production | `imaedge-prod` (`1998691`) | `6820279` | Frankfurt, replica in Stockholm | `imaedge-prod.b-cdn.net` |
| Development | `imaedge-dev-local` (`1998692`) | `6820281` | Frankfurt | `imaedge-dev-local.b-cdn.net` |

Both zones use Standard storage with S3 enabled at creation. S3 is currently
in public preview. The application uses only PUT, GET, and DELETE, verified
against Bunny using its existing SigV4 implementation. The S3 endpoint is
`https://de-s3.storage.bunnycdn.com` and the signing region is `de`.

Public URLs remain `https://assets.imaedge.org/<key>` and
`https://dev-assets.imaedge.org/<key>`. DNS records are DNS-only. Certificates
are issued with external DNS validation before changing either CNAME. Image
optimization is disabled, so originals are delivered unchanged. CDN caching
is disabled during migration; storage access requires credentials and listing
is not public.

Migration procedure:

1. Back up the original production credentials and local `.env` outside Git.
2. List both Tigris buckets, copy every object, then read each copy back and
   compare SHA-256. Save source inventories and verified manifests in the backup.
3. Build and test the release through CI with `BUNNY_APP_ID` temporarily unset.
4. Stop writes by undeploying the Bunny app and stopping any local dev server.
   Copy the final delta before switching storage domains and credentials.
5. Wait for the old DNS TTL, restore `BUNNY_APP_ID`, and rerun the pipeline's
   build/deploy job. The pipeline resolves the new storage credentials and
   starts the app. Update the local `.env` to the separate dev zone.
6. Verify a complete upload and both previews, plus existing image hashes.

The old Tigris buckets are retained without changes and still incur storage
charges through Fly until explicitly retired. They do not receive new uploads
after cutover. The owner-only backup includes credentials, manifests, and the
original `.env`; never commit or print these files.

## Rollback

Original `www` records (DNS-only, TTL 300): `A 66.241.124.106` and
`AAAA 2a09:8280:1::11a:7d39:0`. The apex redirects to `https://www.imaedge.org/`.
Fly Machine: `d8d3297c171e48`, region `fra`.
An owner-only backup of its runtime settings and Machine configuration is stored
outside Git at `~/Backups/imaedge/20261017-bunny/`.

Keep `fly.toml`, the Fly app, Fly secret, and Tigris organization. Do not delete
them as part of the migration. Tigris can still be billed through Fly.
After the storage cutover, the retained Fly release has old Tigris credentials:
do not restart it against a stale bucket. First either configure it for the new
Bunny storage or copy new and changed Bunny objects back to Tigris under a write
pause. Restore the storage CNAMEs only after that copy and checksum verification.
The original targets were `imaedge-prod.t3.tigrisbucket.io` and
`imaedge-dev-local.t3.tigrisbucket.io`, both with TTL 300.
Before restarting Fly, pause and drain Bunny workers and deploy
`OBAN_ENABLED=false`. Then start the retained Fly Machine, restore its original
auto-start/restart settings and saved DNS records, and verify HTTPS and uploads.
Restore the Fly workflow from Git history if future releases must run on Fly.
The old workflow is disabled in GitHub; re-enable it explicitly for rollback.
Do not run deployments on both hosts concurrently. Database migrations must
remain compatible with the retained release while rollback is needed.

References: [Bunny volume-aware updates](https://bunny.net/docs/magic-containers/rolling-updates),
[certificate issuance before DNS changes](https://bunny.net/docs/cdn/seamless-migration).
