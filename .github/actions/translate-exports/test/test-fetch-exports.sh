#!/usr/bin/env bash
# Tests fetch-exports.sh against a fake curl that serves fixtures by query string.
#   bash .github/actions/translate-exports/test/test-fetch-exports.sh
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/fetch-exports.sh"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/bin"

# Fake curl: answers <dir>/<query>.body with the status in <query>.code (default 200) and
# headers in <query>.headers; exits 7 (cannot connect) when FAKE_DOWN is set.
cat > "$root/bin/curl" <<'EOF'
#!/usr/bin/env bash
out=""; hdr=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;; -D) hdr="$2"; shift 2 ;; -w|--max-time|--retry|--retry-delay) shift 2 ;;
    -*) shift ;; *) url="$1"; shift ;;
  esac
done
[ -n "${FAKE_DOWN:-}" ] && exit 7
q="${url#*/export?}"; f="$FAKE_DIR/$(printf '%s' "$q" | tr '/&=' '___')"
[ -f "$f.body" ] || { printf 'not found' > "$out"; : > "$hdr"; printf '404'; exit 0; }
cp "$f.body" "$out"; if [ -f "$f.headers" ]; then cp "$f.headers" "$hdr"; else : > "$hdr"; fi
printf '%s' "$(cat "$f.code" 2>/dev/null || echo 200)"
EOF
chmod +x "$root/bin/curl"

pass=0; failed=0
check() { if eval "$2"; then pass=$((pass + 1)); else failed=$((failed + 1)); echo "FAIL: $1"; fi; }
serve() { printf '%s' "$2" > "$FAKE_DIR/$(printf '%s' "$1" | tr '/&=' '___').body"; }
case_dir() { # fresh workspace with committed files
  ws="$root/ws-$1"; rm -rf "$ws"; mkdir -p "$ws/res/i18n" "$ws/lang/da"
  printf '{"project": "p", "keys": [{"keyId": 1}]}\n' > "$ws/res/fallback.json"
  printf 'a = A\nb = B\n' > "$ws/res/i18n/messages_da.properties"
  printf "<?php\n\nreturn array (\n  'x' => 'X',\n);\n" > "$ws/lang/da/plans.php"
  export FAKE_DIR="$root/fake-$1"; rm -rf "$FAKE_DIR"; mkdir -p "$FAKE_DIR"
}
run() { (cd "$ws" && PATH="$root/bin:$PATH" TRANSLATE_API=http://t/api EXPORTS="$1" bash "$SCRIPT") > "$root/out" 2>&1; echo $? > "$root/rc"; }
rc() { [ "$(cat "$root/rc")" = "$1" ]; }
said() { grep -q -- "$1" "$root/out"; }

case_dir legacy
serve "project=p&format=raw" '{"project":"p","keys":[{"keyId":1},{"keyId":2}]}'
run "p=res/fallback.json"
printf '%s' '{"project":"p","keys":[{"keyId":1},{"keyId":2}]}' | jq --indent 2 . > "$root/expected.json"
check "the project=path shorthand still bakes the raw export, pretty-printed" "rc 0 && cmp -s '$ws/res/fallback.json' '$root/expected.json'"

case_dir props
serve "project=s&format=properties&lang=da&platform=all" $'a = A\nb = B2\nc = C\n'
run "project=s&format=properties&lang=da&platform=all -> res/i18n/messages_da.properties"
check "a properties export is written exactly as served" "rc 0 && [ \"\$(cat '$ws/res/i18n/messages_da.properties')\" = \$'a = A\nb = B2\nc = C' ]"

case_dir laravel
serve "project=s&format=laravel&lang=da" '{"files":{"da/plans.php":"<?php\n\nreturn array (\n  '"'"'x'"'"' => '"'"'Y'"'"',\n);\n","da/new.php":"<?php\n\nreturn array (\n  '"'"'n'"'"' => '"'"'N'"'"',\n);\n"}}'
run "project=s&format=laravel&lang=da -> lang"
check "format=laravel writes every file into the directory" "rc 0 && grep -q \"'x' => 'Y'\" '$ws/lang/da/plans.php' && grep -q \"'n' => 'N'\" '$ws/lang/da/new.php'"

case_dir down
FAKE_DOWN=1 run "p=res/fallback.json"
check "an unreachable translate keeps the committed file and warns" "rc 0 && said '::warning' && said 'HTTP 000' && grep -q '\"keyId\": 1' '$ws/res/fallback.json'"

case_dir partial
serve "project=s&format=properties&lang=da" $'a = A\nb = B\nz = Z\n'
run $'project=s&format=properties&lang=da -> res/i18n/messages_da.properties\np=res/fallback.json'
check "nothing is written unless every request succeeded" "rc 0 && said 'HTTP 404' && [ \"\$(cat '$ws/res/i18n/messages_da.properties')\" = \$'a = A\nb = B' ]"

case_dir shrink
printf 'a = A\nb = B\nc = C\nd = D\ne = E\nf = F\ng = G\nh = H\ni = I\nj = J\n' > "$ws/res/i18n/messages_da.properties"
serve "project=s&format=properties&lang=da" $'a = A\nb = B\nc = C\nd = D\ne = E\nf = F\ng = G\nh = H\ni = I\n'
run "project=s&format=properties&lang=da -> res/i18n/messages_da.properties"
check "a file losing more than 5% of its strings keeps every committed file" "rc 0 && said 'shrink from 10 to 9' && grep -q '^j = J' '$ws/res/i18n/messages_da.properties'"

case_dir shrinkok
serve "project=s&format=properties&lang=da" $'a = A\n'
(cd "$ws" && PATH="$root/bin:$PATH" TRANSLATE_API=http://t/api MAX_SHRINK_PERCENT=50 EXPORTS="project=s&format=properties&lang=da -> res/i18n/messages_da.properties" bash "$SCRIPT") > "$root/out" 2>&1; echo $? > "$root/rc"
check "max-shrink-percent lets a planned removal through" "rc 0 && [ \"\$(cat '$ws/res/i18n/messages_da.properties')\" = 'a = A' ]"

case_dir badfile
serve "project=s&format=laravel&lang=da" '{"files":{"../../etc/x.php":"<?php"}}'
run "project=s&format=laravel&lang=da -> lang"
check "a laravel answer naming a file outside the directory writes nothing" "rc 0 && said 'unexpected file' && [ ! -e '$root/etc/x.php' ] && grep -q \"'x' => 'X'\" '$ws/lang/da/plans.php'"

case_dir wrongproject
serve "project=p&format=raw" '{"project":"other","keys":[{"keyId":1}]}'
run "p=res/fallback.json"
check "a raw export of another project is refused" "rc 0 && said 'not the expected JSON' && grep -q '\"keyId\": 1' '$ws/res/fallback.json'"

case_dir stale
serve "project=p&format=raw" '{"project":"p","keys":[{"keyId":1}]}'
printf 'X-Mirror-Stale: true\r\n' > "$FAKE_DIR/project_p_format_raw.headers"
run "p=res/fallback.json"
check "a stale export is still baked, with a warning" "rc 0 && said 'Stale export' && said 'Baked 1 file'"

# lang={lang}: one line per language the project has in translate.
projects() { printf '%s' "$1" > "$FAKE_DIR/http:__t_api_projects.body"; }
case_dir expand
printf 'a = A\n' > "$ws/res/i18n/messages.properties"
projects '{"projects":[{"slug":"s","languages":["en","da","fo_FO"]}]}'
serve "project=s&format=properties&lang=en" $'a = A-en\n'
serve "project=s&format=properties&lang=da" $'a = A-da\nb = B-da\n'
serve "project=s&format=properties&lang=fo_FO" $'a = A-fo\n'
run $'project=s&format=properties&lang=en -> res/i18n/messages.properties\nproject=s&format=properties&lang={lang} -> res/i18n/messages_{lang}.properties'
check "lang={lang} repeats a line for every language, and an explicit line keeps its language" "rc 0 && [ \"\$(cat '$ws/res/i18n/messages.properties')\" = 'a = A-en' ] && grep -q 'B-da' '$ws/res/i18n/messages_da.properties' && [ -f '$ws/res/i18n/messages_fo_FO.properties' ] && [ ! -e '$ws/res/i18n/messages_en.properties' ] && said 'Baked 3 file'"

case_dir expandfail
projects '{"projects":[{"slug":"s","languages":["en","da"]}]}'
serve "project=s&format=properties&lang=en" $'a = A\n'
run "project=s&format=properties&lang={lang} -> res/i18n/messages_{lang}.properties"
check "one failing language in a repeat keeps every committed file" "rc 0 && said 'HTTP 404' && [ ! -e '$ws/res/i18n/messages_en.properties' ] && [ \"\$(cat '$ws/res/i18n/messages_da.properties')\" = \$'a = A\nb = B' ]"

case_dir noprojects
run "project=s&format=properties&lang={lang} -> res/i18n/messages_{lang}.properties"
check "an unreadable project list keeps every committed file" "rc 0 && said 'project list' && [ \"\$(cat '$ws/res/i18n/messages_da.properties')\" = \$'a = A\nb = B' ]"

case_dir unknownproject
projects '{"projects":[{"slug":"other","languages":["en"]}]}'
run "project=s&format=properties&lang={lang} -> res/i18n/messages_{lang}.properties"
check "a project translate doesn't list keeps every committed file" "rc 0 && said 'no languages' && [ ! -e '$ws/res/i18n/messages_en.properties' ]"

case_dir nolangcall
serve "project=p&format=raw" '{"project":"p","keys":[{"keyId":1}]}'
run "p=res/fallback.json"
check "lines without {lang} don't need the project list" "rc 0 && said 'Baked 1 file'"

for bad in "project=s&format=properties&lang={lang} -> res/i18n/messages.properties" "project=s&format=properties&lang={x} -> res/i18n/m_{x}.properties" "project=s&format=properties&lang=da -> res/i18n/m_{lang}.properties" "project=s&format=properties&lang={lang} -> nodir/m_{lang}.properties" "project=s&format=laravel&lang={lang} -> lang/{lang}"; do
  case_dir badtemplate
  run "$bad"
  check "refuses '$bad'" "rc 1 && said '::error'"
done

for bad in "p=../outside.json" "p=/etc/passwd" "p=res/missing.json" "project=s&format=xliff -> res/fallback.json" "format=raw -> res/fallback.json" "project=s&format=laravel -> res/fallback.json" "just text" "project=s&format=raw&x=\$(id) -> res/fallback.json"; do
  case_dir bad
  run "$bad"
  check "refuses '$bad'" "rc 1 && said '::error'"
done

case_dir empty
run "   "
check "an input with no lines is an error" "rc 1"

echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
