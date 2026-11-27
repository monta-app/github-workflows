# translate-exports

Overwrites a service's committed translation files with translate's exports just before its
Docker build, so the image ships current text, the way the build used to download from
Lokalise. `component-build.yml` runs it when a caller sets `translate-exports`.

The ARC runners run in the internal cluster with translate and call it in-cluster
(`http://translate-internal.translate-internal.svc.cluster.local:3000/api`), with no
tailnet and no token. GitHub-hosted runners can't reach it, so they build with the
committed files.

## Lines

One request per line:

```yaml
translate-exports: |
  product-financial-services=src/main/resources/translations_fallback.json
  project=product-server-php-backend&format=properties&lang=da&platform=all -> service/src/main/resources/i18n/messages_da.properties
  project=product-be&format=laravel&lang=da,en -> resources/lang
```

- `<query> -> <path>`: any query that `/api/export` takes. It needs `project` and
  `format` (`raw`, `properties`, `arb`, `lokalise-json` or `laravel`).
- `<project>=<path>`: shorthand for `project=<project>&format=raw`.
- `format=raw` is written with `jq --indent 2`. The other formats are written exactly as
  translate serves them, because they are the consumers' own file formats.
- `lang={lang}` repeats the line for every language the project has in translate, with
  `{lang}` in the path replaced too, so a new language reaches the build without a workflow
  change. A line that names one language for the same project and format keeps it, for a
  file named differently:

  ```yaml
  translate-exports: |
    project=product-server-php-backend&format=properties&lang=en&platform=all -> service/src/main/resources/i18n/messages.properties
    project=product-server-php-backend&format=properties&lang={lang}&platform=all -> service/src/main/resources/i18n/messages_{lang}.properties
  ```

  A language without a committed file yet is written as a new file; its directory must be
  committed. If translate's project list can't be read, every committed file stays.
- `format=laravel` answers several files, so its path is a directory. The files land in it
  under their own names (`da/plans.php`). Lines run in order, so a later line's file
  replaces an earlier one's.

## Rules

- **Fails the step:** a line that doesn't parse, an unknown format, a path that is absolute
  or leaves the repository, a file target that isn't committed, or a laravel target that
  isn't a directory. These are the caller's mistakes.
- **Warns and keeps every committed file:** translate unreachable, any answer other than
  HTTP 200, an answer of the wrong shape, or a file that would lose more than
  `max-shrink-percent` (default 5) of its strings. Nothing is written unless every request
  succeeded, so an outage never fails a build or mixes old and new files.
- **Warns but bakes:** an export marked `X-Mirror-Stale`, which is still at least as new as
  the committed copy.

## Tests

```sh
bash .github/actions/translate-exports/test/test-fetch-exports.sh
```
