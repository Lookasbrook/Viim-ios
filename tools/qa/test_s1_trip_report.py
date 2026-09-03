import importlib.util
import tempfile
import unittest
from pathlib import Path
from subprocess import CompletedProcess
from unittest.mock import patch


MODULE_PATH = Path(__file__).with_name("s1_trip_report.py")
SPEC = importlib.util.spec_from_file_location("s1_trip_report", MODULE_PATH)
s1_trip_report = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(s1_trip_report)


class S1TripReportTests(unittest.TestCase):
    def test_device_copy_fails_if_wal_copy_has_transport_error(self):
        results = [
            CompletedProcess([], 0, "", ""),
            CompletedProcess([], 1, "", "tunnel connection invalidated"),
        ]
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(s1_trip_report.subprocess, "run", side_effect=results):
                with self.assertRaisesRegex(RuntimeError, "Viim.sqlite-wal"):
                    s1_trip_report.copy_store_from_device(
                        "device-id", Path(directory), "com.yamstack.viim"
                    )

    def test_device_copy_allows_wal_and_shm_to_be_genuinely_absent(self):
        results = [
            CompletedProcess([], 0, "", ""),
            CompletedProcess([], 1, "", "source file does not exist"),
            CompletedProcess([], 1, "", "no such file"),
            CompletedProcess([], 1, "", "diagnostics unavailable"),
        ]
        expected = Path("/tmp/verified.sqlite")
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(s1_trip_report.subprocess, "run", side_effect=results):
                with patch.object(
                    s1_trip_report,
                    "create_consistent_snapshot",
                    return_value=expected,
                ):
                    actual = s1_trip_report.copy_store_from_device(
                        "device-id", Path(directory), "com.yamstack.viim"
                    )
        self.assertEqual(actual, expected)

    def test_consistent_snapshot_includes_wal_rows_and_passes_integrity(self):
        with tempfile.TemporaryDirectory() as directory:
            store = Path(directory) / "Viim.sqlite"
            connection = s1_trip_report.sqlite3.connect(store)
            connection.execute("PRAGMA journal_mode=WAL")
            connection.execute("PRAGMA wal_autocheckpoint=0")
            connection.execute("CREATE TABLE evidence (value TEXT NOT NULL)")
            connection.execute("INSERT INTO evidence VALUES ('latest-trip')")
            connection.commit()

            snapshot = s1_trip_report.create_consistent_snapshot(store)

            with s1_trip_report.sqlite3.connect(snapshot) as copied:
                self.assertEqual(
                    copied.execute("SELECT value FROM evidence").fetchone()[0],
                    "latest-trip",
                )
                self.assertEqual(
                    copied.execute("PRAGMA integrity_check").fetchone()[0],
                    "ok",
                )
            connection.close()

    def test_build_identity_uses_latest_launch(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ViimDiagnostics.log"
            path.write_text(
                "2026-07-12T00:00:00Z app.launch version=0.1.0 build=1 sha=old builtAt=old\n"
                "2026-07-12T01:00:00Z app.launch version=0.1.0 build=2 sha=abc123 builtAt=2026-07-12T01:00:00Z\n"
            )

            self.assertEqual(
                s1_trip_report.read_build_identity(path),
                {
                    "version": "0.1.0",
                    "build": "2",
                    "gitSHA": "abc123",
                    "builtAt": "2026-07-12T01:00:00Z",
                },
            )

    def test_capture_audit_counts_only_sessions_without_outcome(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ViimDiagnostics.log"
            path.write_text(
                "trip.capture.start id=AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA source=location\n"
                "trip.capture.outcome id=AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA status=persisted\n"
                "trip.capture.start id=BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB source=location\n"
            )

            self.assertEqual(
                s1_trip_report.read_capture_audit(path),
                {"sessionCount": 2, "withoutOutcome": 1},
            )


if __name__ == "__main__":
    unittest.main()
