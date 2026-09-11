# Check Migration Order

Fails a PR that adds a Flyway migration whose version sorts **before** one already
applied on the base branch, that names a new migration wrongly, or that edits,
renames or deletes a committed migration.

## Why

Flyway runs without `outOfOrder` in our services. A migration whose version sorts
before one that is already applied fails validation, which kills the deploy's
migration step — for services using an ArgoCD `PreSync` hook that means the sync
never completes and the environment silently stays on the old image.

This is not hypothetical. service-charges PR #878 added `V2026.09.02.10.00` and
merged *after* #892 added `V2026.09.04.10.00`; staging applied #892 first, so
`09.02` became pending behind an already-applied version and four consecutive
deploys failed while staging sat on a stale image for a day.

The important detail is that the comparison is against the **tip** of the base
branch, not `git merge-base`. The merge base by definition does not contain
migrations that landed after the branch was cut, so a merge-base comparison
cannot catch the case above — the stale branch looks fine right up until it
merges.

## Usage

Most repos need no inputs. Include it in a job that has checked the repo out with
full history:

```yaml
jobs:
  check-migration-order:
    name: Check Migration Order
    runs-on: linux-arm64
    steps:
      - uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10 # v6
        with:
          ref: ${{ github.event.pull_request.head.sha }}
          fetch-depth: 0
      - uses: monta-app/github-workflows/.github/actions/check-migration-order@main
```

Kotlin repos calling `pull-request-kotlin.yml` get this automatically and need to
add nothing — the job is part of that workflow and self-skips when
`src/main/resources/db/migration` is absent.

### Multi-module repos

Each line of `migration-paths` is an **independent Flyway version namespace**.
Give one line per database:

```yaml
      - uses: monta-app/github-workflows/.github/actions/check-migration-order@main
        with:
          migration-paths: |
            processor-common/src/main/resources/db/migration
            gateway/src/main/resources/db/migration
```

Do not collapse separate databases into a single root. In service-ocpp the
processor's newest migration is from 2026 and the gateway's from 2022, so a
pooled root would reject a perfectly valid new gateway migration for sorting
behind the processor's — a different database entirely.

### Non-standard roots

Repos that keep migrations somewhere else pass their own paths, e.g. a ClickHouse
root alongside the MySQL one:

```yaml
          migration-paths: |
            src/main/resources/db/migration
            src/main/resources/clickhouse/migration
```

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `migration-paths` | no | `src/main/resources/db/migration` | One migration root per line; each is an independent version namespace. Roots absent from both the base branch and the working tree are skipped. |
| `base-ref` | no | `${{ github.base_ref }}` | Branch name to compare against — a branch name, not a full ref. |
| `naming-pattern` | no | `^[BV][0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]{2}\.[0-9]{2}(\.[0-9]{2})?__.+\.sql$` | ERE every newly added migration filename must match. |

Committed migrations are never checked against `naming-pattern` — renaming one to
satisfy a stricter pattern would break its recorded checksum. Existing violations
are therefore left alone rather than reported.

## Notes

- Versions are compared with `sort -V`, so parts compare numerically the way
  Flyway compares them. A lexicographic comparison gets real filenames wrong:
  service-charges has `V2025.08.05.8.51` (single-digit hour), which plain `sort`
  orders *before* `...18.51`, and service-ocpi has `V2026.02.04.1400`.
- The action deepens a shallow clone itself. `git merge-base` on a shallow clone
  silently returns the wrong answer rather than failing, so this is not left to
  the caller to remember.
- Scope is Flyway-style versioned filenames. Version *extraction* (strip a
  leading `B`/`V`, strip `__description`) is Flyway-specific; Laravel- or
  Prisma-style migrations would need a second extraction mode.

## Limitation worth knowing

`pull_request` does not re-fire when the base branch moves, so two PRs opened in
parallel can still both be green and merge out of order. Closing that gap needs
**Require branches to be up to date before merging** on the base branch. Without
it, treat this as a strong nudge rather than a guarantee.

## Local run

```bash
BASE_REF=main \
MIGRATION_PATHS='src/main/resources/db/migration' \
NAMING_PATTERN='^[BV][0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]{2}\.[0-9]{2}(\.[0-9]{2})?__.+\.sql$' \
  .github/actions/check-migration-order/check-migration-order.sh
```
