# Notify Deploy Authors Action

DMs everyone whose code is in a deploy, telling them their change is live and pointing them at the dashboard to watch.

## Why it runs after the deploy

There is nothing to monitor until the rollout has finished, so this belongs in the deploy path and nowhere
earlier. The step is gated on the deploy succeeding, which is the point at which "your change is live" is
actually true — anything running before that can only promise a change is on its way, which is not a useful cue
to go and watch a dashboard.

Keeping it a separate job also means it only fires for things that are actually deployed, and that it can never
hold up or affect the deploy itself.

## Usage

```yaml
- name: Notify deploy authors
  uses: monta-app/github-workflows/.github/actions/notify-deploy-authors@main
  with:
    previous-ref: ${{ needs.deploy.outputs.previous-image-tag }}
    current-ref: ${{ needs.deploy.outputs.image-tag }}
    service-name: "Monta PHP Monolith"
    stage: production
    dashboard-url: "https://montaapp.grafana.net/d/ja52q4d/server-error-dashboard?from=now-30m&to=now&timezone=browser&var-container=$__all"
    dashboard-label: "Server Error Dashboard"
    slack-token: ${{ secrets.SLACK_APP_TOKEN }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
    identity-api-url: "https://project-tracker.vpn.internal.monta.app"
```

Gate the step on a successful deploy (`if: needs.deploy.result == 'success'`) — there is no point asking anyone
to watch a rollout that failed.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `previous-ref` | Yes | - | Commit SHA or tag the deploy starts after |
| `current-ref` | Yes | - | Commit SHA or tag the deploy ends on |
| `service-name` | Yes | - | Human-readable service name |
| `dashboard-url` | Yes | - | Dashboard the authors should watch |
| `slack-token` | Yes | - | Needs `users:read.email`, `im:write`, `chat:write` |
| `github-token` | Yes | - | Token that can read the repository |
| `dashboard-label` | No | `Error Dashboard` | Link text for the dashboard |
| `stage` | No | `''` | Only affects wording ("… is now deployed to Production.") |
| `ref-url` | No | `''` | Links the deployed ref, when the caller has a URL for it |
| `identity-api-url` | No | `''` | Identity resolver base URL — see below |
| `monitoring-window` | No | `the next 30 minutes` | How long to ask them to watch |
| `max-authors` | No | `15` | Refuse to send if the range has more authors than this |
| `dry-run` | No | `false` | Print the payloads instead of sending them |
| `strict` | No | `false` | Exit non-zero on failure instead of warning |

## Reaching the author in Slack

This is the hard part. A GitHub login does not get you to a Slack account, and the obvious routes mostly fail:

| Signal | Reality (measured on `monta-app/server`) |
|---|---|
| Public GitHub profile email | Set on 4 of 17 sampled org members |
| …and wrong when it is set | `Casperhr` is `cr@monta.app` on GitHub but `cr@monta.com` in Slack — the lookup fails |
| Commit author email | 43% `users.noreply.github.com`, 24% `@monta.com`, 18% `@monta.app`, 13% personal |

So set `identity-api-url` to project-tracker's resolver, which holds each person's work email — the address
Slack actually knows. Measured on one real deploy range, with the resolver 2 of 2 authors were reachable;
without it, 0 of 2 (one author's GitHub login is literally `838`).

Resolution order per person: the resolver's Slack id → the resolver's work email → the `Co-authored-by:` trailer
email → the public GitHub profile email. Each address is looked up via `users.lookupByEmail`.

The resolver is **VPN-only**, so a GitHub-hosted runner cannot reach it. Join the runner to the tailnet with
`tailscale/github-action` (the `TAILSCALE_AUTHKEY` pattern used elsewhere in this org) or use a self-hosted
runner. Without it the action still runs, just reaching fewer people, and it names everyone it could not reach.

## Behaviour worth knowing

- **It never fails your deploy.** Every runtime problem is a `::warning::` and a zero exit. Use `strict: true`
  while testing the wiring.
- **It refuses to mass-DM.** More than `max-authors` people in the range is treated as wrong refs, not as a
  busy deploy: nothing is sent and the count is logged. A 3-day range on the monolith resolves to 34 authors.
- **Bots are skipped** — both `…[bot]` logins and anyone the resolver flags as a bot or a leaver.
- **One DM per person**, even when they appear both as a commit author and in a `Co-authored-by:` trailer.

## Testing

`./test-local.sh` runs the script against a real ref range with `dry-run` on, so it prints the exact Slack
payloads without messaging anyone. Copy `.env.example` to `.env` first.
