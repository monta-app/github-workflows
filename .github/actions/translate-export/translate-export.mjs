#!/usr/bin/env node
//
// Fetch locale files from the translate app's export endpoint.
//
// One file, no dependencies, Node 20 or later, so every repo can run it: CI through
// action.yml, a developer by piping this exact file (pinned to a commit) into node.
// Lifted from monorepo-typescript's scripts/l10n/src/download-locales.ts and
// check-dump-shrink.ts, which only Hub could use. The retry rules, the verbatim
// write and the shrink guard behave as they did there; Hub's daily refresh is the
// parity gate for that.
//
import { execFileSync } from "node:child_process";
import { appendFileSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { parseArgs } from "node:util";

// The permanent address of the contract. It stays the same when translate moves into
// ProductOps, which is why consumers must not name any other host.
export const DEFAULT_EXPORT_URL = "https://translate.vpn.monta.app/api/export";
export const MAX_ATTEMPTS = 3;
// Without a per-attempt ceiling, a connection that is accepted and never answered
// produces no verdict, so the retry rules never run and CI sits until its job cap.
export const REQUEST_TIMEOUT_MS = 60_000;
/** Waits between attempts: one shorter than MAX_ATTEMPTS, as the last attempt does not sleep. */
export const BACKOFF_MS = [5_000, 15_000];
export const DEFAULT_MAX_SHRINK = 50;
// A raw reference token in a file means export-time resolution failed, and users would see it.
const REFERENCE_TOKEN = /\[%key_id:\d+%\]/;
const FORMATS = ["json"];

/**
 * Whether a response is usable, and if not, whether repeating it could help.
 *
 * Retriable: no response (status 0), 429, any 5xx, and a 200 whose body is not a JSON
 * object, which is what a proxy's HTML error page looks like. On 2026-08-31 a single
 * 503 on one language failed Hub's whole refresh, and the next run was clean.
 * Not retriable: any other status. A 4xx (bad slug, unknown language) fails the same
 * way every time, and a 3xx is refused because redirects are not followed.
 */
export function classifyResponse(status, body) {
    if (status !== 200) {
        const retriable = status === 0 || status === 429 || status >= 500;
        return { ok: false, reason: `HTTP ${status}. Body: ${body.slice(0, 300)}`, retriable };
    }
    let parsed;
    try {
        parsed = JSON.parse(body);
    } catch {
        return { ok: false, reason: "response is not JSON", retriable: true };
    }
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
        return { ok: false, reason: "response is not a JSON object", retriable: true };
    }
    return { ok: true, reason: "", retriable: false };
}

export function localeUrl(exportUrl, project, language, format = "json") {
    const query = new URLSearchParams({ project, lang: language, format });
    return `${exportUrl}?${query.toString()}`;
}

export function newExportNotes() {
    return { stale: false, staleMinutes: null, warnings: [] };
}

function describeWarning(language, warning) {
    const entry = typeof warning === "object" && warning !== null ? warning : {};
    if (entry.type === "key-clash") {
        return `\`${String(entry.clashesWith)}\` is lost: \`${String(entry.keyName)}\` has the same name in the nested file`;
    }
    if (entry.keyName !== undefined && entry.referencedKeyId !== undefined) {
        return `\`${String(entry.keyName)}\` (${String(entry.language ?? language)}) is empty: its master key ${String(entry.referencedKeyId)} is missing`;
    }
    return `${language}: ${JSON.stringify(warning)}`;
}

/**
 * Fold one response's headers into `notes`.
 *
 * The export answers 200 even when its mirror is stale (`X-Mirror-Stale`) or a key
 * came out empty (`X-Export-Warnings`), so without reading them a refresh looks complete.
 */
export function readExportHeaders(language, headers, notes) {
    if (!headers) {
        return;
    }
    if (headers.get("X-Mirror-Stale") === "true") {
        notes.stale = true;
        const age = Number.parseInt(headers.get("X-Mirror-Age-Minutes") ?? "", 10);
        if (Number.isFinite(age)) {
            notes.staleMinutes = Math.max(notes.staleMinutes ?? 0, age);
        }
    }
    const raw = headers.get("X-Export-Warnings");
    if (raw === null || raw === "") {
        return;
    }
    let parsed = null;
    try {
        parsed = JSON.parse(raw);
    } catch {
        // An unreadable header becomes a line of its own below rather than vanishing.
    }
    const lines = Array.isArray(parsed)
        ? parsed.map((warning) => describeWarning(language, warning))
        : [`${language}: unreadable X-Export-Warnings header: ${raw.slice(0, 300)}`];
    for (const line of lines) {
        if (!notes.warnings.includes(line)) {
            notes.warnings.push(line);
        }
    }
}

function staleAge(notes) {
    return notes.staleMinutes === null ? "of unknown age" : `${notes.staleMinutes} minutes old`;
}

/** Markdown for the job summary and a PR comment; empty when the export had nothing to say. */
export function exportNotesMarkdown(notes, maxWarnings = 50) {
    if (!notes.stale && notes.warnings.length === 0) {
        return "";
    }
    const out = ["### Translate export notes", ""];
    if (notes.stale) {
        out.push(
            `- ⚠️ **Stale export** (\`X-Mirror-Stale\`): the translate app's copy was ${staleAge(notes)}, so these files may miss recent translation changes.`
        );
    }
    if (notes.warnings.length > 0) {
        out.push(`- ⚠️ **${notes.warnings.length} export warning(s)** (\`X-Export-Warnings\`):`);
        for (const line of notes.warnings.slice(0, maxWarnings)) {
            out.push(`  - ${line}`);
        }
        if (notes.warnings.length > maxWarnings) {
            out.push(`  - …and ${notes.warnings.length - maxWarnings} more (see the workflow log).`);
        }
    }
    return `${out.join("\n")}\n`;
}

/** Write the notes to EXPORT_NOTES_FILE and GITHUB_STEP_SUMMARY. Never fails the download. */
export function reportExportNotes(notes, env, log) {
    const markdown = exportNotesMarkdown(notes);
    if (env.EXPORT_NOTES_FILE) {
        writeFileSync(env.EXPORT_NOTES_FILE, markdown);
    }
    if (markdown === "") {
        return;
    }
    if (notes.stale) {
        log(`::warning::Translate export is stale (${staleAge(notes)}) — the refresh may miss recent changes.`);
    }
    if (notes.warnings.length > 0) {
        log(`::warning::Translate export sent ${notes.warnings.length} warning(s); see the job summary.`);
    }
    log(exportNotesMarkdown(notes, Number.POSITIVE_INFINITY));
    if (env.GITHUB_STEP_SUMMARY) {
        appendFileSync(env.GITHUB_STEP_SUMMARY, markdown);
    }
}

const realSleep = (ms) => new Promise((done) => setTimeout(done, ms));

/**
 * One language, retried per classifyResponse. Returns the body verbatim.
 *
 * Verbatim matters: Hub writes these bytes and formats them afterwards, as it always
 * has. Re-serialising here would change the committed formatting and put a spurious
 * diff in front of every developer on their first run.
 */
export async function fetchLocale(request, deps = {}) {
    const fetchImpl = deps.fetchImpl ?? fetch;
    const sleep = deps.sleep ?? realSleep;
    const log = deps.log ?? console.warn;
    const url = localeUrl(request.exportUrl, request.project, request.language, request.format);

    let last = "unknown failure";
    let spent = 0;
    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
        spent = attempt;
        let status = 0;
        let body = "";
        let headers;
        try {
            // fetch follows redirects by default and would write whatever the target
            // returned into a shipped locale file; curl without -L, which this replaced, did not.
            const response = await fetchImpl(url, { signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS), redirect: "manual" });
            status = response.status;
            headers = response.headers;
            body = await response.text();
        } catch (error) {
            body = error instanceof Error ? error.message : String(error);
        }

        const verdict = classifyResponse(status, body);
        if (verdict.ok) {
            if (deps.notes) {
                readExportHeaders(request.language, headers, deps.notes);
            }
            return body;
        }
        last = verdict.reason;
        if (!verdict.retriable || attempt === MAX_ATTEMPTS) {
            break;
        }
        const wait = BACKOFF_MS[attempt - 1];
        log(`  transient export failure for lang=${request.language} (${last}) — retrying in ${wait / 1000}s (attempt ${attempt}/${MAX_ATTEMPTS})`);
        await sleep(wait);
    }
    // `spent`, not MAX_ATTEMPTS: a 4xx stops after one attempt.
    throw new Error(`Export API failed for lang=${request.language} after ${spent} attempt${spent === 1 ? "" : "s"}: ${last}`);
}

/**
 * Keep only the top-level keys that start with `prefix`.
 *
 * Replaces Lokalise's --filter-filenames for a repo that owns a slice of a shared
 * project (shop-design-tool reads its keys out of Hub React). The mirror holds no
 * filename assignments, so the key name is the only selector available.
 */
export function filterByKeyPrefix(body, prefix) {
    const parsed = JSON.parse(body);
    const kept = {};
    for (const [key, value] of Object.entries(parsed)) {
        if (key.startsWith(prefix)) {
            kept[key] = value;
        }
    }
    return `${JSON.stringify(kept, null, 2)}\n`;
}

/** Leaf strings, so a nested file counts what i18next can render rather than its namespaces. */
export function countLeaves(value) {
    if (typeof value === "string") {
        return 1;
    }
    if (typeof value !== "object" || value === null) {
        return 0;
    }
    let total = 0;
    for (const child of Object.values(value)) {
        total += countLeaves(child);
    }
    return total;
}

function leafEntries(value, path = [], out = []) {
    if (typeof value === "string") {
        out.push([path.join("\u0000"), value]);
    } else if (typeof value === "object" && value !== null) {
        for (const [key, child] of Object.entries(value)) {
            leafEntries(child, [...path, key], out);
        }
    }
    return out;
}

/**
 * Keys whose value carries a raw reference token that the committed file did not.
 *
 * Only new leaks block: a token already committed is breakage this download did not
 * cause, and blocking on it would freeze every refresh until it is repaired upstream.
 */
export function findNewReferenceTokenLeaks(committed, working) {
    const previouslyLeaked = new Set(
        leafEntries(committed)
            .filter(([, text]) => REFERENCE_TOKEN.test(text))
            .map(([key]) => key)
    );
    return leafEntries(working)
        .filter(([key, text]) => REFERENCE_TOKEN.test(text) && !previouslyLeaked.has(key))
        .map(([key]) => key.split("\u0000").join("."));
}

/**
 * The file's content at git HEAD, or null when git has none (a new language, or no repo).
 *
 * A mass deletion upstream would otherwise flow silently into the tree, so the guard
 * compares against what is committed rather than against the previous working copy.
 */
export function committedContent(filePath) {
    const directory = dirname(filePath);
    let repoRoot;
    try {
        repoRoot = execFileSync("git", ["rev-parse", "--show-toplevel"], {
            cwd: directory,
            encoding: "utf8",
            stdio: ["ignore", "pipe", "ignore"],
        }).trim();
    } catch {
        return null;
    }
    const repoPath = relative(realpathSync(repoRoot), realpathSync(filePath)).split("\\").join("/");
    try {
        return execFileSync("git", ["show", `HEAD:${repoPath}`], {
            cwd: repoRoot,
            encoding: "utf8",
            // A Hub dump is close to 2 MB; the 1 MB default throws ENOBUFS.
            maxBuffer: 256 * 1024 * 1024,
            stdio: ["ignore", "pipe", "pipe"],
            // git's message must be English for the match below, whatever the host's locale.
            env: { ...process.env, LC_ALL: "C" },
        });
    } catch (error) {
        if (/does not exist in|exists on disk, but not in|bad revision|unknown revision/.test(String(error.stderr))) {
            return null;
        }
        throw error;
    }
}

export function guardFile(filePath, { maxShrink = DEFAULT_MAX_SHRINK, allowShrink = false, readCommitted = committedContent } = {}) {
    const committedText = readCommitted(filePath);
    if (committedText === null) {
        return { file: filePath, before: null, after: null, blocked: false, newTokenLeaks: [] };
    }
    const committed = JSON.parse(committedText);
    const working = JSON.parse(readFileSync(filePath, "utf8"));
    const before = countLeaves(committed);
    const after = countLeaves(working);
    return {
        file: filePath,
        before,
        after,
        blocked: !allowShrink && before - after > maxShrink,
        newTokenLeaks: findNewReferenceTokenLeaks(committed, working),
    };
}

export function targetPath(outDir, filePattern, language) {
    return join(outDir, filePattern.split("{lang}").join(language));
}

/**
 * Every language, one at a time, stopping at the first that fails.
 *
 * Files fetched before a failure stay written, as they always have in Hub; the error
 * names the language that broke, so a re-run is obvious.
 */
export async function downloadLocales(options, deps = {}) {
    const log = deps.log ?? console.log;
    const env = deps.env ?? process.env;
    const notes = deps.notes ?? newExportNotes();
    const written = [];
    for (const language of options.languages) {
        let body = await fetchLocale(
            { exportUrl: options.exportUrl, project: options.project, language, format: options.format },
            { ...deps, notes }
        );
        if (options.keyPrefix) {
            body = filterByKeyPrefix(body, options.keyPrefix);
        }
        const target = targetPath(options.outDir, options.file, language);
        mkdirSync(dirname(target), { recursive: true });
        writeFileSync(target, body);
        written.push(target);
        log(`  fetched ${language} → ${target}`);
    }
    reportExportNotes(notes, env, log);
    return written;
}

/** Messages for every guarded file that blocks, empty when all pass. */
export function guardFailures(results, maxShrink) {
    const failures = [];
    for (const result of results) {
        if (result.blocked) {
            failures.push(
                `${result.file} shrank by ${result.before - result.after} strings (more than ${maxShrink}). If this is a planned retirement, re-run with ALLOW_SHRINK=true; otherwise check the translate app before committing anything.`
            );
        }
        if (result.newTokenLeaks.length > 0) {
            failures.push(
                `${result.file} carries new raw reference tokens for: ${result.newTokenLeaks.join(", ")}. Export-time resolution failed; repair the reference in the translate app before committing.`
            );
        }
    }
    return failures;
}

const USAGE = `Usage: translate-export --project <slug> --lang <code>[,<code>…] --out-dir <dir> [options]

  --project <slug>      translate project slug, e.g. product-hub-fe-react
  --lang <codes>        languages to fetch; repeat the flag or separate with commas
  --out-dir <dir>       directory the files are written to
  --file <pattern>      file name per language, {lang} is replaced (default: {lang}.json)
  --format <format>     export format (default: json; available: ${FORMATS.join(", ")})
  --key-prefix <text>   keep only top-level keys starting with this text
  --max-shrink <n>      fail if a file loses more than n strings against git HEAD (default: ${DEFAULT_MAX_SHRINK})
  --allow-shrink        let a planned key retirement through (or ALLOW_SHRINK=true)
  --no-guard            skip the shrink and reference-token checks
  --export-url <url>    override the endpoint (or TRANSLATE_EXPORT_URL; default: ${DEFAULT_EXPORT_URL})

Environment: EXPORT_NOTES_FILE receives the export's stale and warning notes as Markdown,
and GITHUB_STEP_SUMMARY gets the same notes when they are not empty.`;

export class UsageError extends Error {}

export function parseCli(argv, env = process.env) {
    const { values } = parseArgs({
        args: argv,
        options: {
            project: { type: "string" },
            lang: { type: "string", multiple: true },
            "out-dir": { type: "string" },
            file: { type: "string", default: "{lang}.json" },
            format: { type: "string", default: "json" },
            "key-prefix": { type: "string" },
            "max-shrink": { type: "string" },
            "allow-shrink": { type: "boolean", default: false },
            "no-guard": { type: "boolean", default: false },
            "export-url": { type: "string" },
            help: { type: "boolean", short: "h", default: false },
        },
        strict: true,
        allowPositionals: false,
    });
    if (values.help) {
        return { help: true };
    }
    const languages = (values.lang ?? [])
        .flatMap((value) => value.split(","))
        .map((value) => value.trim())
        .filter(Boolean);
    const missing = [];
    if (!values.project) missing.push("--project");
    if (languages.length === 0) missing.push("--lang");
    if (!values["out-dir"]) missing.push("--out-dir");
    if (missing.length > 0) {
        throw new UsageError(`Missing ${missing.join(", ")}.`);
    }
    if (!FORMATS.includes(values.format)) {
        throw new UsageError(`Unknown --format "${values.format}". Available: ${FORMATS.join(", ")}.`);
    }
    if (!values.file.includes("{lang}") && languages.length > 1) {
        throw new UsageError(`--file "${values.file}" has no {lang}, so every language would overwrite the same file.`);
    }
    const maxShrinkRaw = values["max-shrink"] ?? String(DEFAULT_MAX_SHRINK);
    const maxShrink = Number(maxShrinkRaw);
    if (!Number.isInteger(maxShrink) || maxShrink < 0) {
        throw new UsageError(`--max-shrink must be a whole number, not "${maxShrinkRaw}".`);
    }
    return {
        help: false,
        project: values.project,
        languages,
        outDir: resolve(values["out-dir"]),
        file: values.file,
        format: values.format,
        keyPrefix: values["key-prefix"],
        maxShrink,
        allowShrink: values["allow-shrink"] || env.ALLOW_SHRINK === "true",
        guard: !values["no-guard"],
        exportUrl: values["export-url"] || env.TRANSLATE_EXPORT_URL || DEFAULT_EXPORT_URL,
    };
}

export async function main(argv = process.argv.slice(2), deps = {}) {
    const log = deps.log ?? console.log;
    const logError = deps.logError ?? console.error;
    let options;
    try {
        options = parseCli(argv, deps.env ?? process.env);
    } catch (error) {
        logError(`${error.message}\n\n${USAGE}`);
        return 2;
    }
    if (options.help) {
        log(USAGE);
        return 0;
    }
    let written;
    try {
        written = await downloadLocales(options, deps);
    } catch (error) {
        logError(`::error::${error instanceof Error ? error.message : String(error)}`);
        return 1;
    }
    if (!options.guard) {
        return 0;
    }
    const results = written.map((file) => guardFile(file, { maxShrink: options.maxShrink, allowShrink: options.allowShrink, readCommitted: deps.readCommitted }));
    for (const result of results) {
        if (result.before !== null) {
            log(`${relative(process.cwd(), result.file)}: ${result.before} -> ${result.after} strings`);
        }
    }
    const failures = guardFailures(results, options.maxShrink);
    for (const failure of failures) {
        logError(`::error::${failure}`);
    }
    return failures.length > 0 ? 1 : 0;
}

// `-` is a pipe into node (`curl … | node --input-type=module - …`), the local path.
function isDirectRun() {
    const entry = process.argv[1];
    if (entry === undefined) {
        return false;
    }
    if (entry === "-") {
        return true;
    }
    try {
        return pathToFileURL(realpathSync(entry)).href === import.meta.url;
    } catch {
        return false;
    }
}

if (isDirectRun()) {
    main().then((code) => {
        process.exitCode = code;
    });
}
