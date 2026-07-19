import importlib.util
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("s1_trip_report.py")
SPEC = importlib.util.spec_from_file_location("s1_trip_report", MODULE_PATH)
s1_trip_report = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(s1_trip_report)


class S1TripReportTests(unittest.TestCase):
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
