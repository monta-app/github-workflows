import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from arc_job_report import render  # noqa: E402
from job_resources import history, suggest  # noqa: E402


def run(number, attempt=1, ended="2026-09-28T11:07:46Z", conclusion="success"):
    return {"run_number": number, "run_attempt": attempt, "html_url": f"https://example/runs/{number}",
            "head_sha": f"{number}abcdef", "conclusion": conclusion,
            "run_started_at": "2026-09-28T11:00:00Z", "updated_at": ended}


POD = "arc-arm64-8cpu-24gb-bwt29-runner-2t8gj"


def job(name, duration, suggested=None, reason=None):
    return {"job": name, "duration_s": duration, "runner": POD,
            "dashboard": f"https://grafana/{name.replace(' ', '')}", "cpu_cores": {"avg": 1.0, "max": 2.0},
            "memory_gib": {"peak": 3.0, "limit": 24.0}, "suggested_runner": suggested, "reason": reason,
            "history": {"runs": 40, "peak_mem_gib": 6.5, "cpu_p50": 1.2, "cpu_peak": 5.1}}


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

    def test_keeps_a_job_named_like_the_shards_out_of_the_shard_row(self):
        body = render(run(1), [job("Unit Tests (Fast Feedback)", 4), job("Unit Tests - shard 0", 100),
                               job("Unit Tests - shard 1", 110)], None)

        self.assertIn("| [Unit Tests](https://grafana/UnitTests(FastFeedback)) | 4s |", body)
        self.assertIn("| Unit Tests · shards [0](https://grafana/UnitTests-shard0) "
                      "**[1](https://grafana/UnitTests-shard1)** | 1m 40s – 1m 50s |", body)

    def test_marks_re_runs_and_lists_only_jobs_with_a_change_and_why(self):
        body = render(run(12, attempt=2, conclusion="failure"),
                      [job("Compile", 150, "arc-arm64-4cpu-12gb", "trial"), job("Plan test shards", 15)], None)

        self.assertIn("| ❌ | 7m 46s (re-run) | – |", history_rows(body)[0])
        self.assertIn("1.3 × the job's peak over the last 7d", body)
        self.assertIn("| Job | Change | Why | Peak memory (7d) | CPU median / peak | Runs (7d) |", body)
        self.assertIn("| [Compile](https://grafana/Compile) | ⬇️ 8cpu-24gb → 4cpu-12gb | trial: may be slower | "
                      "6.5 GiB | 1.2 / 5.1 | 40 |", body)
        self.assertNotIn("[Plan test shards](https://grafana/Plantestshards) | ⬇️", body)
        self.assertIn("· 💡 1 runner change</summary>", body)

    def test_groups_parenthesised_shards_in_both_tables_apart_from_a_job_with_the_bare_name(self):
        shards = [job("Test (shard 2)", 200, "arc-arm64-4cpu-12gb", "trial"),
                  job("Test (shard 1)", 240, "arc-arm64-4cpu-12gb", "trial"),
                  job("Test (shard 3)", 180, "arc-arm64-16cpu-48gb", "faster")]
        shards[1]["history"] = {"runs": 12, "peak_mem_gib": 7.0, "cpu_p50": 3.9, "cpu_peak": 7.6}
        body = render(run(1), [*shards, job("Test", 6)], None)

        self.assertIn("| [Test](https://grafana/Test) | 6s |", body)
        self.assertIn("| Test · shards **[1](https://grafana/Test(shard1))** [2](https://grafana/Test(shard2)) "
                      "[3](https://grafana/Test(shard3)) | 3m 00s – 4m 00s |", body)
        self.assertIn("| Test · shards [1](https://grafana/Test(shard1)) [2](https://grafana/Test(shard2)) | "
                      "⬇️ 8cpu-24gb → 4cpu-12gb | trial: may be slower | 7.0 GiB | 3.9 / 7.6 | 12 |", body)
        self.assertIn("| Test · shards [3](https://grafana/Test(shard3)) | ⬆️ 8cpu-24gb → 16cpu-48gb |", body)
        self.assertIn("· 💡 2 runner changes</summary>", body)

    def test_shows_the_full_name_of_matrix_jobs_that_would_share_a_short_name(self):
        body = render(run(1), [job("integration-tests (integration, app)", 300),
                               job("integration-tests (services, unit)", 200, "arc-arm64-16cpu-48gb", "memory"),
                               job("static-checks (php)", 100)], None)

        self.assertIn("| [integration-tests (integration, app)](https://grafana/integration-tests(integration,app)) "
                      "| 5m 00s |", body)
        self.assertIn("| [integration-tests (services, unit)](https://grafana/integration-tests(services,unit)) "
                      "| 3m 20s |", body)
        self.assertIn("| [static-checks](https://grafana/static-checks(php)) | 1m 40s |", body)
        self.assertIn("| [integration-tests (services, unit)](https://grafana/integration-tests(services,unit)) "
                      "| ⬆️ 8cpu-24gb → 16cpu-48gb | needs memory |", body)

    def test_groups_dashed_shards_and_sorts_a_job_with_a_suffix_by_its_shown_name(self):
        body = render(run(1), [job("unit-tests (shard-2)", 100), job("unit-tests (shard-1)", 90),
                               job("unit-tests (fast)", 5)], None)

        rows = [line for line in body.splitlines() if line.startswith("| [unit-tests]") or line.startswith("| unit-tests")]
        self.assertEqual(rows, ["| [unit-tests](https://grafana/unit-tests(fast)) | 5s |",
                                "| unit-tests · shards [1](https://grafana/unit-tests(shard-1)) "
                                "**[2](https://grafana/unit-tests(shard-2))** | 1m 30s – 1m 40s |"])

    def test_omits_the_suggestion_table_when_every_runner_fits(self):
        body = render(run(12), [job("Compile", 150)], None)

        self.assertNotIn("Suggested runner changes", body)
        self.assertNotIn("💡", body)


def sized(peak_mem_gib=3.0, cpu_p50=1.0, cpu_peak=2.0, runs=40, oom=0, runner=POD):
    return suggest(runner, "arm64", peak_mem_gib, cpu_p50, cpu_peak, runs, oom)


class SuggestTest(unittest.TestCase):
    def test_memory_is_a_hard_floor_with_headroom(self):
        self.assertEqual(sized(peak_mem_gib=19.0), ("arc-arm64-16cpu-48gb", "memory"))
        self.assertIsNone(sized(peak_mem_gib=18.0, cpu_p50=5.0))

    def test_an_oom_kill_always_moves_up_a_size(self):
        self.assertEqual(sized(peak_mem_gib=10.0, oom=1), ("arc-arm64-16cpu-48gb", "memory"))

    def test_cpu_bound_most_of_the_job_suggests_a_bigger_size_as_faster(self):
        self.assertEqual(sized(peak_mem_gib=5.0, cpu_p50=7.0, cpu_peak=8.0), ("arc-arm64-16cpu-48gb", "faster"))

    def test_downsizes_to_the_smallest_size_holding_memory_and_median_cpu(self):
        self.assertEqual(sized(peak_mem_gib=2.0, cpu_p50=0.8, cpu_peak=1.5), ("arc-arm64-2cpu-4gb", "fits"))
        self.assertEqual(sized(peak_mem_gib=2.0, cpu_p50=1.5, cpu_peak=5.0), ("arc-arm64-2cpu-4gb", "trial"))
        self.assertEqual(sized(peak_mem_gib=2.0, cpu_p50=3.0, cpu_peak=5.0), ("arc-arm64-4cpu-12gb", "trial"))

    def test_never_downsizes_on_fewer_runs_than_the_minimum(self):
        self.assertIsNone(sized(peak_mem_gib=2.0, runs=4))
        self.assertEqual(sized(peak_mem_gib=30.0, runs=0), ("arc-arm64-16cpu-48gb", "memory"))

    def test_leaves_runners_outside_the_catalog_alone(self):
        self.assertIsNone(sized(peak_mem_gib=40.0, runner="self-hosted-arm64-2xl-f968t-runner-878jv"))


class HistoryTest(unittest.TestCase):
    def test_selects_the_jobs_by_escaped_name_and_reads_every_series_per_job(self):
        import job_resources
        queries = []

        def fake_get(api, query):
            queries.append(query)
            value = {"max by (job_name) (max_over_time(arc:job_memory": 2 * 2**30}
            v = next((v for k, v in value.items() if query.startswith(k)), 3)
            return [{"metric": {"job_name": "Build (staging)"}, "value": [0, str(v)]}]

        job_resources.get, real = fake_get, job_resources.get
        try:
            h = history("monta-app/repo", ["Build (staging)", "Build (staging)", 'Lint "x"'])
        finally:
            job_resources.get = real

        self.assertEqual(h, {"Build (staging)": {"runs": 3, "peak_mem_gib": 2.0, "cpu_p50": 3.0, "cpu_peak": 3.0}})
        self.assertIn('job_name=~"Build \\\\(staging\\\\)|Lint \\"x\\""', queries[0])


if __name__ == "__main__":
    unittest.main()
