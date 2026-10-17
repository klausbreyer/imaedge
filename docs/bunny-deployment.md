# Bunny deployment

The migration follows `texttile/demo-bunny`: one instance in Germany, a mounted
volume to serialize replacements, immutable image digests, WebSockets, and no
CDN caching. Unlike Texttile, imaedge has no SQLite database or permanent image
files to transfer. Hetzner Postgres and Tigris remain in place.

## Pipeline

Bunny app ID: `7h8OXpOEr3k6dyw`. Pull Zone: `6820180`.
Endpoint: `mc-2bwurpor46.bunny.run`. Production CNAME target:
`mc-2bwurpor46.b-cdn.net`.

Migration state on 2026-10-17: public DNS points to Bunny, the production
certificate is issued, and HTTPS is enforced. The deployment key is configured
in GitHub. Fly's ingest queue was paused and drained before stopping its Machine
and disabling automatic starts and restarts. The pipeline now enables Bunny
workers and startup migrations. Hetzner Postgres and Tigris remain unchanged.

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

Runtime secrets are copied from Fly once and remain in Bunny. The pipeline
preserves them, including the signing key, database URL, Tigris credentials,
and admin login. Only public settings from `bunny.json` are overwritten.
Do not use the local `.env`, which points to the development bucket.

## Container and networking

- One container named `app`, shared compute, min/max replicas both 1, region `DE` only.
- A 1 GB `single-instance` volume mounted at `/var/lib/imaedge`. No application data
  is stored there. Bunny uses it to stop the old pod before starting a replacement.
- Upload chunks stay temporary. Interrupted uploads can resume from browser storage.
- TCP startup and readiness checks on port 8080, with HTTP from CDN to origin.
- CDN endpoint with WebSockets enabled, caching disabled, and HTTPS enforced.
- `www.imaedge.org` points to the Bunny CDN hostname, DNS-only in Cloudflare.
- The apex redirect and `assets.imaedge.org` / `dev-assets.imaedge.org` stay in place.

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

## Rollback

Original `www` records (DNS-only, TTL 300): `A 66.241.124.106` and
`AAAA 2a09:8280:1::11a:7d39:0`. The apex redirects to `https://www.imaedge.org/`.
Fly Machine: `d8d3297c171e48`, region `fra`.
An owner-only backup of its runtime settings and Machine configuration is stored
outside Git at `~/Backups/imaedge/20261017-bunny/`.

Keep `fly.toml`, the Fly app, Fly secret, and Tigris organization. Do not delete
them as part of the hosting migration. Tigris can still be billed through Fly.
Before restarting Fly, pause and drain Bunny workers and deploy
`OBAN_ENABLED=false`. Then start the retained Fly Machine, restore its original
auto-start/restart settings and saved DNS records, and verify HTTPS and uploads.
Restore the Fly workflow from Git history if future releases must run on Fly.
The old workflow is disabled in GitHub; re-enable it explicitly for rollback.
Do not run deployments on both hosts concurrently. Database migrations must
remain compatible with the retained release while rollback is needed.

References: [Bunny volume-aware updates](https://bunny.net/docs/magic-containers/rolling-updates),
[certificate issuance before DNS changes](https://bunny.net/docs/cdn/seamless-migration).
