import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from arc_job_report import render  # noqa: E402


def run(number, attempt=1, ended="2026-09-28T11:07:46Z", conclusion="success"):
    return {"run_number": number, "run_attempt": attempt, "html_url": f"https://example/runs/{number}",
            "head_sha": f"{number}abcdef", "conclusion": conclusion,
            "run_started_at": "2026-09-28T11:00:00Z", "updated_at": ended}


def job(name, duration, suggested="arc-arm64-4cpu-12gb"):
    return {"job": name, "duration_s": duration, "runner": "arc-arm64-8cpu-24gb-bwt29-runner-2t8gj",
            "dashboard": f"https://grafana/{name.replace(' ', '')}", "cpu_cores": {"avg": 1.0, "max": 2.0},
            "memory_gib": {"peak": 3.0, "limit": 24.0}, "suggested_runner": suggested}


def history_rows(body):
    return [line for line in body.splitlines() if line.startswith("| [#")]


class RenderTest(unittest.TestCase):
    def test_history_keeps_earlier_runs_sorted_replaces_a_reported_run_and_shows_the_change(self):
        body = render(run(12, ended="2026-09-28T11:05:00Z"), [job("Compile", 100)], None)
        body = render(run(10), [job("Compile", 90)], body)
        body = render(run(12, ended="2026-09-28T11:08:00Z"), [job("Compile", 80)], body)

        rows = history_rows(body)
        self.assertEqual([r.split("]")[0] for r in rows], ["| [#10", "| [#12"])
        self.assertIn("| ✅ | 8m 00s | ▲ 14s | Compile (1m 20s) |", rows[1])
        self.assertIn("<summary>✅ <b>8m 00s</b> (▲ 14s vs previous run)", body)

    def test_merges_shards_into_one_row_with_a_link_per_shard_and_the_slowest_in_bold(self):
        body = render(run(1), [job("Tests - shard 1", 110), job("Tests - shard 0", 130), job("Tests - shard 2", 90)], None)

        self.assertIn("| Tests · shards **[0](https://grafana/Tests-shard0)** [1](https://grafana/Tests-shard1) "
                      "[2](https://grafana/Tests-shard2) | 1m 30s – 2m 10s |", body)

    def test_marks_re_runs_and_lists_only_jobs_over_two_minutes_with_a_change(self):
        fits = job("Unit Tests (Fast Feedback)", 150, suggested="arc-arm64-8cpu-24gb")
        body = render(run(12, attempt=2, conclusion="failure"),
                      [job("Compile", 150), job("Plan test shards", 15), fits], None)

        self.assertIn("| ❌ | 7m 46s (re-run) | – |", history_rows(body)[0])
        self.assertIn("| [Unit Tests](https://grafana/UnitTests(FastFeedback)) | 2m 30s |", body)
        self.assertIn("| Compile | ⬇️ 8cpu-24gb → 4cpu-12gb | 2.0 | 3.0 GiB |", body)
        self.assertNotIn("| Plan test shards | ⬇️", body)
        self.assertIn("· 💡 1 runner change</summary>", body)

    def test_omits_the_suggestion_table_when_every_runner_fits(self):
        body = render(run(12), [job("Compile", 150, suggested="arc-arm64-8cpu-24gb")], None)

        self.assertNotIn("Suggested runner changes", body)
        self.assertNotIn("💡", body)


if __name__ == "__main__":
    unittest.main()
