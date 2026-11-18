# translate-export

Fetches locale files from the translate app's export endpoint
(`https://translate.vpn.monta.app/api/export`) instead of downloading them from Lokalise.

One Node script with no dependencies (`translate-export.mjs`, Node 20 or later). CI runs it
through this action. A developer runs the same file at the same commit, so CI and a local
download cannot drift apart.

## What it does

- Fetches each language in turn. A request gets three attempts with waits of 5 s and 15 s,
  and 60 s per attempt. It retries on 429, 5xx, a failed connection and a body that is not a
  JSON object (a proxy's error page). It does not retry any other 4xx, and it does not
  follow redirects.
- Writes the response body as it arrived. Formatting is the repo's own step afterwards.
- Reads `X-Mirror-Stale` and `X-Export-Warnings`, which the export sends with a 200. Their
  notes go to the job summary and to the `notes-file` output, for a PR comment.
- Guards each written file against git `HEAD`. It fails when a file loses more than
  `max-shrink` strings (default 50), or when a value carries a raw `[%key_id:N%]` token
  that the committed file did not have. A new language with no committed file is skipped.

## Use in a workflow

The runner has to reach the tailnet first.

```yaml
- uses: tailscale/github-action@064b10558093f38325e838ddea35486bdc6b1d5c # v4.4.0
  with:
    authkey: ${{ secrets.TAILSCALE_AUTHKEY }}
    hostname: "github-${{ github.run_id }}"
    args: "--login-server https://headscale.monta.com"

- uses: monta-app/github-workflows/.github/actions/translate-export@<sha>
  with:
    project: product-hub-fe-react
    languages: da,de,en,en_US,es,fr,fr_CA,it,nl,sv
    out-dir: apps/hub/src/domain/common/i18n/locale
```

| Input | Default | |
|---|---|---|
| `project` | | Translate project slug |
| `languages` | | Comma- or space-separated codes |
| `out-dir` | | Where the files go |
| `file` | `{lang}.json` | File name per language |
| `format` | `json` | Only `json` is served today |
| `key-prefix` | | Keep only top-level keys with this prefix, for a repo that owns part of a shared project |
| `max-shrink` | `50` | Strings a file may lose before the guard fails |
| `allow-shrink` | `false` | For a planned key retirement |
| `guard` | `true` | Shrink and token checks |
| `export-url` | | Leave empty. The default address stays the same when translate moves. |
| `notes-file` | `$RUNNER_TEMP/translate-export-notes.md` | Markdown notes, empty when there are none |

## Run it locally

On the tailnet, pin the same commit the workflow uses:

```sh
curl -fsSL https://raw.githubusercontent.com/monta-app/github-workflows/<sha>/.github/actions/translate-export/translate-export.mjs \
  | node --input-type=module - --project product-hub-fe-react --lang da,en --out-dir src/locale
```

`node translate-export.mjs --help` lists every flag. `TRANSLATE_EXPORT_URL` and
`ALLOW_SHRINK=true` work as environment variables too.

## Tests

```sh
node --test .github/actions/translate-export/test/*.test.mjs
```
