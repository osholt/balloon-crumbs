# Oracle relay deployment

Balloon Crumbs runs as a separate Docker Compose project on the Oracle host that
already serves Tail End Charlie. The two applications share no database,
encryption keys, volumes, API process or retention job.

The only shared boundary is TEC's public Caddy network:

```text
Internet
  -> TEC public Caddy :443
      -> balloon-crumbs-edge:8080
          -> Balloon Crumbs API + PostgreSQL
          -> /plan/ static pilot planner
          -> bounded map/weather/chart provider proxies
```

`deploy/compose.oracle.yaml` removes Balloon Crumbs' public port bindings and
adds only its Caddy container to `ride-relay_default`, under the
`balloon-crumbs-edge` alias. PostgreSQL and the API remain on the private
Balloon Crumbs network. TEC's Caddy routes the dedicated hostname to that alias.

## Host state

- Checkout: `/opt/balloon-crumbs`, detached at an ancestor of `origin/main`.
- Secrets: `/opt/balloon-crumbs/deploy/.env`, mode 600, never committed.
- Compose project: `balloon-crumbs`.
- Public hostname: `relay.balloon-crumbs.tailendcharlie.app`.
- Deploy state: `/var/lib/balloon-crumbs-deploy/production.commit`.

The host configuration selects the Oracle overlay:

```bash
RELAY_DEPLOY_REPO=/opt/balloon-crumbs \
RELAY_DEPLOY_STATE_DIR=/var/lib/balloon-crumbs-deploy \
RELAY_DEPLOY_PRODUCTION_OVERRIDES=compose.oracle.yaml \
  /opt/balloon-crumbs/deploy/relay-deploy.sh production <full-main-commit>
```

## Rollback

Redeploy the previous full commit with the same command. Database migrations are
forward-only, so a rollback must stay compatible with the current schema. The
planner and Caddy are static/reversible; the relay smoke test asserts the image
commit, compatibility document and health response before a production commit
is recorded as deployed. After a first deployment, create and fetch one test
plan through the public planner to prove the database-backed plan round trip.

Rollback immediately if the public health check fails twice, the server reports
a different build commit, the planner assets fail to load, or either provider
proxy can reach an origin outside its single configured provider.
