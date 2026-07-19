#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import os
import re
import sqlite3
import subprocess
import sys
import uuid
from pathlib import Path


APP_BUNDLE_ID = "com.yamstack.viim"
CORE_DATA_EPOCH = dt.datetime(2001, 1, 1, tzinfo=dt.timezone.utc)


def main() -> int:
    args = parse_args()
    try:
        workdir = Path(args.output_dir).expanduser().resolve()
        workdir.mkdir(parents=True, exist_ok=True)

        if args.store:
            store_path = Path(args.store).expanduser().resolve()
        else:
            if not args.device:
                raise SystemExit("Provide either --store or --device.")
            store_path = copy_store_from_device(args.device, workdir, args.bundle_id)

        report = build_report(store_path, args.reference_km)
        write_outputs(report, workdir)
        print_summary(report, workdir)
        return 0
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a QA S1 trip report from Viim CoreData."
    )
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--store", help="Path to an exported Viim.sqlite store.")
    source.add_argument("--device", help="devicectl device identifier/name.")
    parser.add_argument(
        "--bundle-id",
        default=APP_BUNDLE_ID,
        help=f"App bundle identifier. Default: {APP_BUNDLE_ID}",
    )
    parser.add_argument(
        "--reference-km",
        type=float,
        help="Reference distance from odometer or Google Maps.",
    )
    parser.add_argument(
        "--output-dir",
        default=default_output_dir(),
        help="Directory where JSON and Markdown reports are written.",
    )
    return parser.parse_args()


def default_output_dir() -> str:
    now = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    return f"qa/artifacts/s1-{now}"


def copy_store_from_device(device: str, output_dir: Path, bundle_id: str) -> Path:
    store_dir = output_dir / "container" / "Library" / "Application Support"
    store_dir.mkdir(parents=True, exist_ok=True)
    copied_store = store_dir / "Viim.sqlite"

    for filename in ["Viim.sqlite", "Viim.sqlite-wal", "Viim.sqlite-shm", "ViimDiagnostics.log"]:
        source = f"Library/Application Support/{filename}"
        destination = store_dir / filename
        command = [
            "xcrun",
            "devicectl",
            "device",
            "copy",
            "from",
            "--device",
            device,
            "--domain-type",
            "appDataContainer",
            "--domain-identifier",
            bundle_id,
            "--source",
            source,
            "--destination",
            str(destination),
        ]
        result = subprocess.run(command, text=True, capture_output=True)
        if result.returncode != 0 and filename == "Viim.sqlite":
            raise RuntimeError(
                "failed to copy Viim.sqlite from device: "
                + (result.stderr.strip() or result.stdout.strip())
                + "\nFallback: export the app container from Xcode Devices & Simulators, "
                + "then run this script with --store '<container>/AppData/Library/Application Support/Viim.sqlite'."
            )
        if result.returncode != 0 and filename == "ViimDiagnostics.log":
            continue

    return copied_store


def build_report(store_path: Path, reference_km: float | None) -> dict:
    if not store_path.exists():
        raise FileNotFoundError(store_path)

    with sqlite3.connect(f"file:{store_path}?mode=ro", uri=True) as connection:
        connection.row_factory = sqlite3.Row
        tables = table_names(connection)
        trips = read_trips(connection, tables)
        active_drafts = read_active_drafts(connection, tables)
        active_sample_count = read_active_sample_count(connection, tables)
        telemetry = read_quality_telemetry(connection, tables)
        persistent_capture_outcomes = read_capture_outcomes(connection, tables)

    latest_trip = trips[0] if trips else None
    latest_trip_age_hours = None
    if latest_trip and latest_trip["endDate"]:
        latest_end = dt.datetime.fromisoformat(latest_trip["endDate"])
        latest_trip_age_hours = round(
            (dt.datetime.now(dt.timezone.utc) - latest_end).total_seconds() / 3600,
            2,
        )

    if latest_trip and reference_km is not None and reference_km > 0:
        latest_trip["referenceKm"] = reference_km
        latest_trip["distanceErrorPercent"] = round(
            abs(latest_trip["distanceKm"] - reference_km) / reference_km * 100,
            2,
        )

    diagnostics_path = store_path.parent / "ViimDiagnostics.log"
    recent_diagnostics = read_recent_diagnostics(diagnostics_path)
    build_identity = read_build_identity(diagnostics_path)
    capture_audit = read_capture_audit(diagnostics_path)

    return {
        "generatedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "storePath": str(store_path),
        "tripCount": len(trips),
        "activeDraftCount": len(active_drafts),
        "activeSampleCount": active_sample_count,
        "qualityTelemetryCount": len(telemetry),
        "latestTripAgeHours": latest_trip_age_hours,
        "localTripsTodayCount": trips_today_count(trips),
        "diagnosticsLogPresent": diagnostics_path.exists(),
        "buildIdentity": build_identity,
        "captureSessionCount": capture_audit["sessionCount"],
        "captureSessionsWithoutOutcome": capture_audit["withoutOutcome"],
        "persistentCaptureOutcomeCount": len(persistent_capture_outcomes),
        "latestTrip": latest_trip,
        "trips": trips,
        "activeDrafts": active_drafts,
        "recentQualityTelemetry": telemetry[:10],
        "recentCaptureOutcomes": persistent_capture_outcomes[:20],
        "recentDiagnostics": recent_diagnostics,
    }


def table_names(connection: sqlite3.Connection) -> set[str]:
    rows = connection.execute(
        "SELECT name FROM sqlite_master WHERE type = 'table'"
    ).fetchall()
    return {row["name"] for row in rows}


def read_trips(connection: sqlite3.Connection, tables: set[str]) -> list[dict]:
    if "ZTRIP" not in tables:
        return []

    columns = table_columns(connection, "ZTRIP")
    max_gap = "ZMAXSAMPLEGAPSEC" if "ZMAXSAMPLEGAPSEC" in columns else "0"
    p95_gap = "ZP95SAMPLEGAPSEC" if "ZP95SAMPLEGAPSEC" in columns else "0"
    coverage = "ZCOVERAGERATIO" if "ZCOVERAGERATIO" in columns else "0"
    burst_count = "ZBURSTCOUNT" if "ZBURSTCOUNT" in columns else "0"
    fuel_liters = "ZFUELLITERS" if "ZFUELLITERS" in columns else "NULL"
    fuel_formula = "ZFUELFORMULAVERSION" if "ZFUELFORMULAVERSION" in columns else "'legacy'"
    rows = connection.execute(
        f"""
        SELECT
            ZID, ZSTARTDATE, ZENDDATE, ZDISTANCEKM, ZDURATIONSEC,
            ZAVGSPEEDKMH, ZMAXSPEEDKMH, ZQUALITYSCORE, ZQUALITYCONFIDENCE,
            ZQUALITYREASONCODES, ZREJECTEDSEGMENTCOUNT, ZVALIDSEGMENTCOUNT,
            ZGPSACCURACYAVG, ZGPSACCURACYP95, ZPOLYLINE,
            {max_gap} AS ZMAXSAMPLEGAPSEC,
            {p95_gap} AS ZP95SAMPLEGAPSEC,
            {coverage} AS ZCOVERAGERATIO,
            {burst_count} AS ZBURSTCOUNT,
            {fuel_liters} AS ZFUELLITERS,
            {fuel_formula} AS ZFUELFORMULAVERSION
        FROM ZTRIP
        ORDER BY ZENDDATE DESC
        """
    ).fetchall()

    trips = []
    for row in rows:
        route_points = decode_route_points(row["ZPOLYLINE"])
        trips.append(
            {
                "id": decode_uuid(row["ZID"]),
                "startDate": decode_coredata_date(row["ZSTARTDATE"]),
                "endDate": decode_coredata_date(row["ZENDDATE"]),
                "distanceKm": round(float(row["ZDISTANCEKM"] or 0), 4),
                "durationSec": int(row["ZDURATIONSEC"] or 0),
                "avgSpeedKmh": round(float(row["ZAVGSPEEDKMH"] or 0), 2),
                "maxSpeedKmh": round(float(row["ZMAXSPEEDKMH"] or 0), 2),
                "qualityScore": int(row["ZQUALITYSCORE"] or 0),
                "qualityConfidence": row["ZQUALITYCONFIDENCE"],
                "qualityReasonCodes": split_codes(row["ZQUALITYREASONCODES"]),
                "rejectedSegmentCount": int(row["ZREJECTEDSEGMENTCOUNT"] or 0),
                "validSegmentCount": int(row["ZVALIDSEGMENTCOUNT"] or 0),
                "gpsAccuracyAvg": round(float(row["ZGPSACCURACYAVG"] or -1), 2),
                "gpsAccuracyP95": round(float(row["ZGPSACCURACYP95"] or -1), 2),
                "maxSampleGapSec": round(float(row["ZMAXSAMPLEGAPSEC"] or 0), 2),
                "p95SampleGapSec": round(float(row["ZP95SAMPLEGAPSEC"] or 0), 2),
                "coverageRatio": round(float(row["ZCOVERAGERATIO"] or 0), 4),
                "burstCount": int(row["ZBURSTCOUNT"] or 0),
                "fuelLiters": round(float(row["ZFUELLITERS"]), 6) if row["ZFUELLITERS"] is not None else None,
                "fuelFormulaVersion": row["ZFUELFORMULAVERSION"],
                "routePointCount": len(route_points),
                "firstRoutePoint": route_points[0] if route_points else None,
                "lastRoutePoint": route_points[-1] if route_points else None,
            }
        )
    return trips


def read_active_drafts(connection: sqlite3.Connection, tables: set[str]) -> list[dict]:
    if "ZACTIVETRIPDRAFT" not in tables:
        return []

    columns = {
        row["name"]
        for row in connection.execute("PRAGMA table_info(ZACTIVETRIPDRAFT)").fetchall()
    }
    phase_column = "ZPHASE" if "ZPHASE" in columns else "'active'"
    rows = connection.execute(
        f"""
        SELECT
            ZID, ZSTARTEDAT, ZLASTUPDATEDAT, ZLASTMOVINGAT,
            ZDISTANCEMETERS, ZSAMPLECOUNT, ZVEHICLETYPE, {phase_column} AS ZPHASE
        FROM ZACTIVETRIPDRAFT
        ORDER BY ZSTARTEDAT DESC
        """
    ).fetchall()

    drafts = []
    for row in rows:
        drafts.append(
            {
                "id": decode_uuid(row["ZID"]),
                "startedAt": decode_coredata_date(row["ZSTARTEDAT"]),
                "lastUpdatedAt": decode_coredata_date(row["ZLASTUPDATEDAT"]),
                "lastMovingAt": decode_coredata_date(row["ZLASTMOVINGAT"]),
                "distanceMeters": round(float(row["ZDISTANCEMETERS"] or 0), 2),
                "sampleCount": int(row["ZSAMPLECOUNT"] or 0),
                "vehicleType": row["ZVEHICLETYPE"],
                "phase": row["ZPHASE"],
            }
        )
    return drafts


def read_active_sample_count(connection: sqlite3.Connection, tables: set[str]) -> int:
    if "ZACTIVETRIPSAMPLE" not in tables:
        return 0

    row = connection.execute("SELECT COUNT(*) AS count FROM ZACTIVETRIPSAMPLE").fetchone()
    return int(row["count"] or 0)


def read_quality_telemetry(
    connection: sqlite3.Connection, tables: set[str]
) -> list[dict]:
    if "ZTRIPQUALITYTELEMETRY" not in tables:
        return []

    columns = table_columns(connection, "ZTRIPQUALITYTELEMETRY")
    max_gap = "ZMAXSAMPLEGAPSEC" if "ZMAXSAMPLEGAPSEC" in columns else "0"
    p95_gap = "ZP95SAMPLEGAPSEC" if "ZP95SAMPLEGAPSEC" in columns else "0"
    coverage = "ZCOVERAGERATIO" if "ZCOVERAGERATIO" in columns else "0"
    burst_count = "ZBURSTCOUNT" if "ZBURSTCOUNT" in columns else "0"
    rows = connection.execute(
        f"""
        SELECT
            ZTRIPID, ZCREATEDAT, ZDECISIONSOURCE, ZVEHICLETYPE,
            ZQUALITYSCORE, ZQUALITYCONFIDENCE, ZQUALITYREASONCODES,
            ZACCEPTEDFORSTORAGE, ZSAMPLECOUNT, ZREJECTEDSEGMENTCOUNT,
            ZVALIDSEGMENTCOUNT,
            {max_gap} AS ZMAXSAMPLEGAPSEC,
            {p95_gap} AS ZP95SAMPLEGAPSEC,
            {coverage} AS ZCOVERAGERATIO,
            {burst_count} AS ZBURSTCOUNT
        FROM ZTRIPQUALITYTELEMETRY
        ORDER BY ZCREATEDAT DESC
        """
    ).fetchall()

    records = []
    for row in rows:
        records.append(
            {
                "tripId": decode_uuid(row["ZTRIPID"]),
                "createdAt": decode_coredata_date(row["ZCREATEDAT"]),
                "decisionSource": row["ZDECISIONSOURCE"],
                "vehicleType": row["ZVEHICLETYPE"],
                "qualityScore": int(row["ZQUALITYSCORE"] or 0),
                "qualityConfidence": row["ZQUALITYCONFIDENCE"],
                "qualityReasonCodes": split_codes(row["ZQUALITYREASONCODES"]),
                "acceptedForStorage": bool(row["ZACCEPTEDFORSTORAGE"]),
                "sampleCount": int(row["ZSAMPLECOUNT"] or 0),
                "rejectedSegmentCount": int(row["ZREJECTEDSEGMENTCOUNT"] or 0),
                "validSegmentCount": int(row["ZVALIDSEGMENTCOUNT"] or 0),
                "maxSampleGapSec": round(float(row["ZMAXSAMPLEGAPSEC"] or 0), 2),
                "p95SampleGapSec": round(float(row["ZP95SAMPLEGAPSEC"] or 0), 2),
                "coverageRatio": round(float(row["ZCOVERAGERATIO"] or 0), 4),
                "burstCount": int(row["ZBURSTCOUNT"] or 0),
            }
        )
    return records


def read_capture_outcomes(
    connection: sqlite3.Connection, tables: set[str]
) -> list[dict]:
    if "ZTRIPCAPTUREOUTCOME" not in tables:
        return []
    rows = connection.execute(
        """
        SELECT ZTRIPID, ZCREATEDAT, ZSTATUS, ZREASON, ZSOURCE, ZSAMPLECOUNT
        FROM ZTRIPCAPTUREOUTCOME
        ORDER BY ZCREATEDAT DESC
        """
    ).fetchall()
    return [
        {
            "tripId": decode_uuid(row["ZTRIPID"]),
            "createdAt": decode_coredata_date(row["ZCREATEDAT"]),
            "status": row["ZSTATUS"],
            "reason": row["ZREASON"],
            "source": row["ZSOURCE"],
            "sampleCount": int(row["ZSAMPLECOUNT"] or 0),
        }
        for row in rows
    ]


def table_columns(connection: sqlite3.Connection, table: str) -> set[str]:
    return {
        row["name"] for row in connection.execute(f"PRAGMA table_info({table})").fetchall()
    }


def decode_route_points(value: bytes | str | None) -> list[dict]:
    if not value:
        return []
    try:
        raw_value = value.decode("utf-8") if isinstance(value, bytes) else value
        decoded = json.loads(raw_value)
    except Exception:
        return []
    if not isinstance(decoded, list):
        return []
    return [compact_route_point(point) for point in decoded if isinstance(point, dict)]


def compact_route_point(point: dict) -> dict:
    return {
        "timestamp": point.get("timestamp"),
        "latitude": point.get("latitude"),
        "longitude": point.get("longitude"),
        "speedKmh": point.get("speedKmh"),
        "horizontalAccuracy": point.get("horizontalAccuracy"),
        "speedAccuracy": point.get("speedAccuracy"),
    }


def decode_uuid(value) -> str | None:
    if value is None:
        return None
    if isinstance(value, bytes):
        if len(value) == 16:
            return str(uuid.UUID(bytes=value))
        try:
            return str(uuid.UUID(value.decode("utf-8")))
        except Exception:
            return value.hex()
    return str(value)


def decode_coredata_date(value) -> str | None:
    if value is None:
        return None
    try:
        seconds = float(value)
    except (TypeError, ValueError):
        return str(value)
    return (CORE_DATA_EPOCH + dt.timedelta(seconds=seconds)).isoformat()


def split_codes(value: str | None) -> list[str]:
    if not value:
        return []
    return [part for part in value.split(",") if part]


def write_outputs(report: dict, output_dir: Path) -> None:
    json_path = output_dir / "s1-trip-report.json"
    markdown_path = output_dir / "s1-trip-report.md"
    json_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    markdown_path.write_text(render_markdown(report))


def trips_today_count(trips: list[dict]) -> int:
    today = dt.datetime.now().astimezone().date()
    count = 0
    for trip in trips:
        if not trip.get("endDate"):
            continue
        end_date = dt.datetime.fromisoformat(trip["endDate"]).astimezone().date()
        if end_date == today:
            count += 1
    return count


def read_recent_diagnostics(path: Path, limit: int = 80) -> list[str]:
    if not path.exists():
        return []
    try:
        lines = path.read_text(errors="replace").splitlines()
    except Exception:
        return []
    return lines[-limit:]


def read_build_identity(path: Path) -> dict | None:
    if not path.exists():
        return None
    pattern = re.compile(
        r"app\.launch version=(\S+) build=(\S+) sha=(\S+) builtAt=(\S+)"
    )
    for line in reversed(path.read_text(errors="replace").splitlines()):
        match = pattern.search(line)
        if match:
            return {
                "version": match.group(1),
                "build": match.group(2),
                "gitSHA": match.group(3),
                "builtAt": match.group(4),
            }
    return None


def read_capture_audit(path: Path) -> dict:
    if not path.exists():
        return {"sessionCount": 0, "withoutOutcome": 0}
    started = set()
    completed = set()
    for line in path.read_text(errors="replace").splitlines():
        start_match = re.search(r"trip\.capture\.start id=([0-9A-Fa-f-]+)", line)
        if start_match:
            started.add(start_match.group(1).lower())
        outcome_match = re.search(r"trip\.capture\.outcome id=([0-9A-Fa-f-]+)", line)
        if outcome_match:
            completed.add(outcome_match.group(1).lower())
    return {
        "sessionCount": len(started),
        "withoutOutcome": len(started - completed),
    }


def render_markdown(report: dict) -> str:
    latest = report.get("latestTrip")
    lines = [
        "# S1 Trip Report",
        "",
        f"- Generated at: `{report['generatedAt']}`",
        f"- Store: `{report['storePath']}`",
        f"- Trip count: `{report['tripCount']}`",
        f"- Active draft count: `{report['activeDraftCount']}`",
        f"- Active sample count: `{report['activeSampleCount']}`",
        f"- Quality telemetry count: `{report['qualityTelemetryCount']}`",
        f"- Local trips today: `{report['localTripsTodayCount']}`",
        f"- Latest trip age: `{report['latestTripAgeHours']} h`",
        f"- Diagnostics log present: `{report['diagnosticsLogPresent']}`",
        f"- Build identity: `{report['buildIdentity']}`",
        f"- Capture sessions: `{report['captureSessionCount']}`",
        f"- Capture sessions without outcome: `{report['captureSessionsWithoutOutcome']}`",
        f"- Persistent terminal outcomes: `{report['persistentCaptureOutcomeCount']}`",
        "",
    ]

    if not latest:
        lines += ["## Latest Trip", "", "No persisted trip found.", ""]
        return "\n".join(lines)

    lines += [
        "## Latest Trip",
        "",
        f"- ID: `{latest['id']}`",
        f"- Start: `{latest['startDate']}`",
        f"- End: `{latest['endDate']}`",
        f"- Distance: `{latest['distanceKm']} km`",
        f"- Duration: `{latest['durationSec']} s`",
        f"- Average speed: `{latest['avgSpeedKmh']} km/h`",
        f"- Max speed: `{latest['maxSpeedKmh']} km/h`",
        f"- Route points: `{latest['routePointCount']}`",
        f"- Valid segments: `{latest['validSegmentCount']}`",
        f"- Rejected segments: `{latest['rejectedSegmentCount']}`",
        f"- GPS accuracy avg/p95: `{latest['gpsAccuracyAvg']} m / {latest['gpsAccuracyP95']} m`",
        f"- GPS gaps max/p95: `{latest['maxSampleGapSec']} s / {latest['p95SampleGapSec']} s`",
        f"- GPS temporal coverage: `{latest['coverageRatio']}` across `{latest['burstCount']}` bursts",
        f"- Estimated fuel: `{latest['fuelLiters']} L` with `{latest['fuelFormulaVersion']}`",
        f"- Quality: `{latest['qualityConfidence']}` score `{latest['qualityScore']}` reasons `{','.join(latest['qualityReasonCodes'])}`",
    ]

    if "referenceKm" in latest:
        lines += [
            f"- Reference distance: `{latest['referenceKm']} km`",
            f"- Distance error: `{latest['distanceErrorPercent']} %`",
        ]

    lines += [
        "",
        "## Trips",
        "",
        "| End local | Distance | Duration | Avg | Max stored | Points | Rejected | Quality |",
        "|---|---:|---:|---:|---:|---:|---:|---|",
    ]
    for trip in report.get("trips", []):
        lines.append(
            "| "
            f"{local_time(trip['endDate'])} | "
            f"{trip['distanceKm']} km | "
            f"{trip['durationSec']} s | "
            f"{trip['avgSpeedKmh']} km/h | "
            f"{trip['maxSpeedKmh']} km/h | "
            f"{trip['routePointCount']} | "
            f"{trip['rejectedSegmentCount']} | "
            f"{trip['qualityConfidence']}:{','.join(trip['qualityReasonCodes'])} |"
        )

    diagnostics = report.get("recentDiagnostics", [])
    lines += [
        "",
        "## Recent Diagnostics",
        "",
    ]
    if diagnostics:
        lines += [f"- `{line}`" for line in diagnostics]
    else:
        lines.append("No persistent diagnostics log found in the app container.")

    lines += [
        "",
        "## Route Bounds",
        "",
        f"- First point: `{latest['firstRoutePoint']}`",
        f"- Last point: `{latest['lastRoutePoint']}`",
        "",
    ]
    return "\n".join(lines)


def local_time(value: str | None) -> str:
    if not value:
        return ""
    return dt.datetime.fromisoformat(value).astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")


def print_summary(report: dict, output_dir: Path) -> None:
    latest = report.get("latestTrip")
    print(f"Report written to: {output_dir}")
    if not latest:
        print("No persisted trip found.")
        return
    print(
        "Latest trip: "
        f"{latest['distanceKm']} km, "
        f"{latest['durationSec']} s, "
        f"{latest['routePointCount']} points, "
        f"{latest['rejectedSegmentCount']} rejected segments"
    )
    if "distanceErrorPercent" in latest:
        print(f"Distance error vs reference: {latest['distanceErrorPercent']}%")


if __name__ == "__main__":
    raise SystemExit(main())
