import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";
import { fileURLToPath } from "node:url";

import {
    BACKOFF_MS,
    DEFAULT_EXPORT_URL,
    MAX_ATTEMPTS,
    REQUEST_TIMEOUT_MS,
    classifyResponse,
    countLeaves,
    downloadLocales,
    exportNotesMarkdown,
    fetchLocale,
    filterByKeyPrefix,
    findNewReferenceTokenLeaks,
    guardFile,
    localeUrl,
    main,
    newExportNotes,
    parseCli,
    readExportHeaders,
    targetPath,
} from "../translate-export.mjs";

const SCRIPT = fileURLToPath(new URL("../translate-export.mjs", import.meta.url));
const REQUEST = { exportUrl: DEFAULT_EXPORT_URL, project: "product-hub-fe-react", language: "da", format: "json" };

function response(status, body, headers = {}) {
    return { status, headers: new Headers(headers), text: async () => body };
}

function scripted(...responses) {
    const calls = [];
    const fetchImpl = async (url, init) => {
        calls.push({ url, init });
        const next = responses.shift();
        if (next instanceof Error) throw next;
        return next;
    };
    return { fetchImpl, calls };
}

function quiet() {
    const lines = [];
    return { log: (line) => lines.push(line), lines };
}

function tempDir() {
    return mkdtempSync(join(tmpdir(), "translate-export-"));
}

function git(cwd, ...args) {
    execFileSync("git", args, { cwd, stdio: "ignore" });
}

function repoWith(files) {
    const dir = tempDir();
    git(dir, "init", "-q");
    git(dir, "config", "user.email", "test@example.com");
    git(dir, "config", "user.name", "test");
    for (const [name, content] of Object.entries(files)) {
        mkdirSync(join(dir, name, ".."), { recursive: true });
        writeFileSync(join(dir, name), content);
    }
    git(dir, "add", ".");
    git(dir, "commit", "-q", "-m", "seed");
    return dir;
}

function manyKeys(count, prefix = "k") {
    return Object.fromEntries(Array.from({ length: count }, (_, i) => [`${prefix}${i}`, `v${i}`]));
}

describe("classifyResponse", () => {
    it("accepts a 200 carrying a JSON object", () => {
        assert.deepEqual(classifyResponse(200, '{"a":"b"}'), { ok: true, reason: "", retriable: false });
    });
    it("retries 429, 5xx and a failure to connect (status 0)", () => {
        for (const status of [0, 429, 500, 503]) {
            assert.equal(classifyResponse(status, "").retriable, true, `status ${status}`);
        }
    });
    it("retries a 200 whose body is not a JSON object, which is what a proxy error page looks like", () => {
        assert.equal(classifyResponse(200, "<html>bad gateway</html>").retriable, true);
        assert.equal(classifyResponse(200, "[1,2]").retriable, true);
        assert.equal(classifyResponse(200, "null").retriable, true);
    });
    it("does not retry a 4xx or a redirect", () => {
        assert.equal(classifyResponse(404, "").retriable, false);
        assert.equal(classifyResponse(302, "").retriable, false);
    });
    it("puts the start of the body in the reason", () => {
        assert.match(classifyResponse(400, '{"error":"Unknown project"}').reason, /HTTP 400.*Unknown project/);
    });
});

describe("localeUrl", () => {
    it("asks for one project, one language and the format, in the order Hub's script did", () => {
        assert.equal(
            localeUrl(DEFAULT_EXPORT_URL, "product-hub-fe-react", "fr_CA"),
            "https://translate.vpn.monta.app/api/export?project=product-hub-fe-react&lang=fr_CA&format=json"
        );
    });
});

describe("fetchLocale", () => {
    it("returns the body verbatim on a clean first response", async () => {
        const body = '{ "b": "2",\n  "a": "1" }';
        const { fetchImpl } = scripted(response(200, body));
        assert.equal(await fetchLocale(REQUEST, { fetchImpl, sleep: async () => {} }), body);
    });
    it("recovers from a transient failure, the case that failed Hub's refresh on 2026-08-31", async () => {
        const { fetchImpl, calls } = scripted(response(503, "connection timeout"), response(200, "{}"));
        const { log } = quiet();
        assert.equal(await fetchLocale(REQUEST, { fetchImpl, sleep: async () => {}, log }), "{}");
        assert.equal(calls.length, 2);
    });
    it("gives up after MAX_ATTEMPTS, names the language, and does not sleep after the last attempt", async () => {
        const { fetchImpl, calls } = scripted(...Array.from({ length: MAX_ATTEMPTS }, () => response(502, "")));
        const sleeps = [];
        const { log } = quiet();
        await assert.rejects(fetchLocale(REQUEST, { fetchImpl, sleep: async (ms) => sleeps.push(ms), log }), /lang=da after 3 attempts: HTTP 502/);
        assert.equal(calls.length, MAX_ATTEMPTS);
        assert.deepEqual(sleeps, BACKOFF_MS);
    });
    it("stops at once on a 4xx and says it made one attempt", async () => {
        const { fetchImpl, calls } = scripted(response(400, "Unknown language"));
        await assert.rejects(fetchLocale(REQUEST, { fetchImpl, sleep: async () => {} }), /after 1 attempt: HTTP 400/);
        assert.equal(calls.length, 1);
    });
    it("treats a thrown network error as retriable", async () => {
        const { fetchImpl } = scripted(new Error("ECONNRESET"), response(200, "{}"));
        const { log } = quiet();
        assert.equal(await fetchLocale(REQUEST, { fetchImpl, sleep: async () => {}, log }), "{}");
    });
    it("bounds every attempt and refuses to follow redirects", async () => {
        const { fetchImpl, calls } = scripted(response(200, "{}"));
        await fetchLocale(REQUEST, { fetchImpl });
        assert.ok(calls[0].init.signal instanceof AbortSignal);
        assert.equal(calls[0].init.redirect, "manual");
        assert.equal(REQUEST_TIMEOUT_MS, 60_000);
    });
    it("has one backoff wait per retry, not per attempt", () => {
        assert.equal(BACKOFF_MS.length, MAX_ATTEMPTS - 1);
    });
});

describe("export notes", () => {
    it("reports a stale export with the largest age seen", () => {
        const notes = newExportNotes();
        readExportHeaders("da", new Headers({ "X-Mirror-Stale": "true", "X-Mirror-Age-Minutes": "170" }), notes);
        readExportHeaders("sv", new Headers({ "X-Mirror-Stale": "true", "X-Mirror-Age-Minutes": "190" }), notes);
        assert.equal(notes.staleMinutes, 190);
        assert.match(exportNotesMarkdown(notes), /190 minutes old/);
    });
    it("ignores the age header when the export is not stale", () => {
        const notes = newExportNotes();
        readExportHeaders("da", new Headers({ "X-Mirror-Age-Minutes": "40" }), notes);
        assert.equal(exportNotesMarkdown(notes), "");
    });
    it("names the key behind an orphan warning and a key clash, once across languages", () => {
        const notes = newExportNotes();
        const warnings = JSON.stringify([
            { keyName: "a.b", referencedKeyId: 783325003, language: "da" },
            { type: "key-clash", keyName: "x::y", clashesWith: "x" },
        ]);
        readExportHeaders("da", new Headers({ "X-Export-Warnings": warnings }), notes);
        readExportHeaders("sv", new Headers({ "X-Export-Warnings": JSON.stringify([{ type: "key-clash", keyName: "x::y", clashesWith: "x" }]) }), notes);
        assert.deepEqual(notes.warnings, [
            "`a.b` (da) is empty: its master key 783325003 is missing",
            "`x` is lost: `x::y` has the same name in the nested file",
        ]);
    });
    it("keeps an unreadable warnings header visible", () => {
        const notes = newExportNotes();
        readExportHeaders("da", new Headers({ "X-Export-Warnings": "not json" }), notes);
        assert.match(notes.warnings[0], /unreadable X-Export-Warnings header/);
    });
    it("cuts a long list short in the Markdown", () => {
        const notes = { stale: false, staleMinutes: null, warnings: Array.from({ length: 60 }, (_, i) => `w${i}`) };
        assert.match(exportNotesMarkdown(notes), /…and 10 more/);
    });
});

describe("filterByKeyPrefix", () => {
    it("keeps only the keys a repo owns in a shared project", () => {
        const out = filterByKeyPrefix(JSON.stringify({ shopDesignToolTitle: "Shop", hubTitle: "Hub", shopDesignToolOk: "OK" }), "shopDesignTool");
        assert.deepEqual(JSON.parse(out), { shopDesignToolTitle: "Shop", shopDesignToolOk: "OK" });
        assert.ok(out.endsWith("\n"));
    });
});

describe("countLeaves and findNewReferenceTokenLeaks", () => {
    it("counts strings inside nested namespaces and plural forms", () => {
        assert.equal(countLeaves({ a: "1", b: { one: "x", other: "y" }, c: { d: { e: "z" } } }), 4);
    });
    it("reports a new leak, nested ones included", () => {
        assert.deepEqual(findNewReferenceTokenLeaks({}, { a: "[%key_id:1%]", n: { b: "[%key_id:2%]" } }), ["a", "n.b"]);
    });
    it("suppresses a leak that is already committed", () => {
        assert.deepEqual(findNewReferenceTokenLeaks({ a: "[%key_id:1%]" }, { a: "[%key_id:1%]" }), []);
    });
});

describe("guardFile", () => {
    it("passes growth and small shrinks", () => {
        const repo = repoWith({ "locale/en.json": JSON.stringify(manyKeys(100)) });
        writeFileSync(join(repo, "locale/en.json"), JSON.stringify(manyKeys(60)));
        assert.equal(guardFile(join(repo, "locale/en.json")).blocked, false);
        writeFileSync(join(repo, "locale/en.json"), JSON.stringify(manyKeys(140)));
        assert.equal(guardFile(join(repo, "locale/en.json")).blocked, false);
    });
    it("blocks a shrink beyond the threshold, the mass-deletion case", () => {
        const repo = repoWith({ "locale/da.json": JSON.stringify(manyKeys(100)) });
        writeFileSync(join(repo, "locale/da.json"), JSON.stringify(manyKeys(49)));
        const result = guardFile(join(repo, "locale/da.json"));
        assert.deepEqual([result.before, result.after, result.blocked], [100, 49, true]);
    });
    it("lets a planned retirement through", () => {
        const repo = repoWith({ "locale/da.json": JSON.stringify(manyKeys(100)) });
        writeFileSync(join(repo, "locale/da.json"), "{}");
        assert.equal(guardFile(join(repo, "locale/da.json"), { allowShrink: true }).blocked, false);
    });
    it("skips a new language git has no committed file for, under a non-English host locale too", () => {
        const repo = repoWith({ "locale/en.json": "{}" });
        writeFileSync(join(repo, "locale/sv.json"), "{}");
        const before = process.env.LC_ALL;
        process.env.LC_ALL = "de_DE.UTF-8";
        try {
            assert.equal(guardFile(join(repo, "locale/sv.json")).before, null);
        } finally {
            if (before === undefined) delete process.env.LC_ALL;
            else process.env.LC_ALL = before;
        }
    });
    it("skips a directory outside any git repository", () => {
        const dir = tempDir();
        writeFileSync(join(dir, "en.json"), "{}");
        assert.equal(guardFile(join(dir, "en.json")).before, null);
    });
    it("reads a committed file larger than 1 MB instead of skipping it", () => {
        const big = JSON.stringify(manyKeys(60_000, "a_long_key_name_to_pass_one_megabyte_"));
        assert.ok(big.length > 1024 * 1024);
        const repo = repoWith({ "en.json": big });
        assert.equal(guardFile(join(repo, "en.json")).before, 60_000);
    });
});

describe("parseCli", () => {
    it("takes repeated and comma-separated languages", () => {
        const options = parseCli(["--project", "p", "--lang", "da,sv", "--lang", "en", "--out-dir", "x"], {});
        assert.deepEqual(options.languages, ["da", "sv", "en"]);
        assert.equal(options.exportUrl, DEFAULT_EXPORT_URL);
        assert.equal(options.maxShrink, 50);
        assert.equal(options.guard, true);
    });
    it("reads TRANSLATE_EXPORT_URL and ALLOW_SHRINK from the environment", () => {
        const options = parseCli(["--project", "p", "--lang", "da", "--out-dir", "x"], { TRANSLATE_EXPORT_URL: "http://127.0.0.1:1/api/export", ALLOW_SHRINK: "true" });
        assert.equal(options.exportUrl, "http://127.0.0.1:1/api/export");
        assert.equal(options.allowShrink, true);
    });
    it("names every missing required flag", () => {
        assert.throws(() => parseCli([], {}), /Missing --project, --lang, --out-dir/);
    });
    it("refuses a format the export does not serve yet", () => {
        assert.throws(() => parseCli(["--project", "p", "--lang", "da", "--out-dir", "x", "--format", "arb"], {}), /Unknown --format "arb"/);
    });
    it("refuses a file pattern that would write every language to one file", () => {
        assert.throws(() => parseCli(["--project", "p", "--lang", "da,sv", "--out-dir", "x", "--file", "all.json"], {}), /no \{lang\}/);
    });
    it("refuses an unknown flag", () => {
        assert.throws(() => parseCli(["--project", "p", "--surprise"], {}));
    });
});

describe("downloadLocales", () => {
    it("writes one file per language through the pattern, notes included", async () => {
        const dir = tempDir();
        const { fetchImpl, calls } = scripted(
            response(200, '{"a":"da"}', { "X-Mirror-Stale": "true", "X-Mirror-Age-Minutes": "200" }),
            response(200, '{"a":"sv"}')
        );
        const notesFile = join(dir, "notes.md");
        const summary = join(dir, "summary.md");
        const { log } = quiet();
        const written = await downloadLocales(
            { exportUrl: DEFAULT_EXPORT_URL, project: "p", languages: ["da", "sv"], outDir: join(dir, "out"), file: "app_{lang}.json", format: "json" },
            { fetchImpl, log, env: { EXPORT_NOTES_FILE: notesFile, GITHUB_STEP_SUMMARY: summary } }
        );
        assert.deepEqual(written, [join(dir, "out/app_da.json"), join(dir, "out/app_sv.json")]);
        assert.equal(readFileSync(written[1], "utf8"), '{"a":"sv"}');
        assert.match(calls[1].url, /lang=sv/);
        assert.match(readFileSync(notesFile, "utf8"), /200 minutes old/);
        assert.match(readFileSync(summary, "utf8"), /Stale export/);
    });
    it("stops at the first broken language, leaving the earlier ones written", async () => {
        const dir = tempDir();
        const { fetchImpl } = scripted(response(200, "{}"), response(404, "Unknown language"));
        const { log } = quiet();
        await assert.rejects(
            downloadLocales({ exportUrl: DEFAULT_EXPORT_URL, project: "p", languages: ["da", "xx"], outDir: dir, file: "{lang}.json", format: "json" }, { fetchImpl, log, env: {} }),
            /lang=xx/
        );
        assert.equal(readFileSync(join(dir, "da.json"), "utf8"), "{}");
    });
    it("writes an empty notes file when the export had nothing to say", async () => {
        const dir = tempDir();
        const { fetchImpl } = scripted(response(200, "{}"));
        const { log } = quiet();
        await downloadLocales({ exportUrl: DEFAULT_EXPORT_URL, project: "p", languages: ["da"], outDir: dir, file: "{lang}.json", format: "json" }, { fetchImpl, log, env: { EXPORT_NOTES_FILE: join(dir, "n.md") } });
        assert.equal(readFileSync(join(dir, "n.md"), "utf8"), "");
    });
});

describe("main", () => {
    it("exits 1 on a mass shrink and 0 when the shrink is allowed", async () => {
        const repo = repoWith({ "locale/da.json": JSON.stringify(manyKeys(100)) });
        const args = ["--project", "p", "--lang", "da", "--out-dir", join(repo, "locale")];
        const errors = [];
        const deps = () => ({ fetchImpl: scripted(response(200, "{}")).fetchImpl, log: () => {}, logError: (line) => errors.push(line), env: {} });
        assert.equal(await main(args, deps()), 1);
        assert.match(errors.join("\n"), /shrank by 100 strings/);
        assert.equal(await main([...args, "--allow-shrink"], deps()), 0);
    });
    it("exits 1 on a new raw reference token", async () => {
        const repo = repoWith({ "locale/da.json": '{"a":"x"}' });
        const errors = [];
        const code = await main(["--project", "p", "--lang", "da", "--out-dir", join(repo, "locale")], {
            fetchImpl: scripted(response(200, '{"a":"[%key_id:9%]"}')).fetchImpl,
            log: () => {},
            logError: (line) => errors.push(line),
            env: {},
        });
        assert.equal(code, 1);
        assert.match(errors.join("\n"), /raw reference tokens for: a/);
    });
    it("exits 2 with usage on bad arguments", async () => {
        const errors = [];
        assert.equal(await main([], { logError: (line) => errors.push(line) }), 2);
        assert.match(errors[0], /Usage: translate-export/);
    });
    it("runs as a file and as a pipe into node, which is the local path", () => {
        const asFile = spawnSync(process.execPath, [SCRIPT, "--help"], { encoding: "utf8" });
        assert.equal(asFile.status, 0);
        assert.match(asFile.stdout, /Usage: translate-export/);
        const piped = spawnSync(process.execPath, ["--input-type=module", "-", "--help"], { input: readFileSync(SCRIPT), encoding: "utf8" });
        assert.equal(piped.status, 0, piped.stderr);
        assert.match(piped.stdout, /Usage: translate-export/);
    });
    it("does not run when imported", () => {
        const probe = spawnSync(process.execPath, ["--input-type=module", "-e", `await import(${JSON.stringify(SCRIPT)}); console.log("imported")`], { encoding: "utf8" });
        assert.equal(probe.stdout.trim(), "imported");
    });
});

describe("targetPath", () => {
    it("replaces every {lang}", () => {
        assert.equal(targetPath("/o", "{lang}/{lang}.json", "da"), "/o/da/da.json");
    });
});
