#!/usr/bin/env python3
"""Load courses2.json into the ucas_dev database.

The JSON is a flat list of course study options. It is loaded into the
normalized schema defined by priv/repo/migrations/20260918160306_create_tables.exs:

    provider ─┬─ campus
              └─ course ── course_study_option ─┬─ academic_year
                                                ├─ qualification
                                                ├─ study_mode
                                                └─ campus

Providers, courses and study options carry their own UUIDs in the JSON.
Campuses and qualifications do not, so stable UUIDv5 values are derived
from their natural keys so re-running the script is idempotent.

Usage:
    python3 load_courses.py [path/to/courses2.json]
"""

import json
import os
import sys
import uuid

import psycopg2
from psycopg2.extras import execute_values

# Namespace for derived UUIDs (campuses, qualifications).
NAMESPACE = uuid.UUID("5d5d0d9a-6f4b-4e2a-9d7d-2f2b0d3c1a11")

DB_CONFIG = {
    "host": os.environ.get("PGHOST", "localhost"),
    "port": os.environ.get("PGPORT", "5432"),
    "dbname": os.environ.get("PGDATABASE", "ucas_dev"),
    "user": os.environ.get("PGUSER", "postgres"),
    "password": os.environ.get("PGPASSWORD", "postgres"),
}


def derive_uuid(*parts):
    return str(uuid.uuid5(NAMESPACE, "\x00".join(str(p) for p in parts)))


def clean(value):
    """Normalize JSON nulls/empty strings to Python None."""
    if value is None:
        return None
    value = value.strip()
    return value or None


def load_courses(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def insert_providers(cur, rows):
    providers = {
        r["provider_uuid"]: clean(r["provider_name"]) or "Unknown provider"
        for r in rows
    }
    execute_values(
        cur,
        """
        INSERT INTO provider (id, name) VALUES %s
        ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name
        """,
        list(providers.items()),
    )
    print(f"provider: {len(providers)} rows")


def insert_qualifications(cur, rows):
    names = sorted({clean(r["qualification"]) for r in rows} - {None})
    execute_values(
        cur,
        """
        INSERT INTO qualification (id, name) VALUES %s
        ON CONFLICT (id) DO NOTHING
        """,
        [(derive_uuid("qualification", name), name) for name in names],
    )
    print(f"qualification: {len(names)} rows")
    return {name: derive_uuid("qualification", name) for name in names}


def insert_academic_years(cur, rows):
    years = sorted({clean(r["academic_year"]) for r in rows} - {None})
    execute_values(
        cur,
        """
        INSERT INTO academic_year (year) VALUES %s
        ON CONFLICT (year) DO NOTHING
        """,
        [(year,) for year in years],
    )
    cur.execute("SELECT year, id FROM academic_year")
    mapping = dict(cur.fetchall())
    print(f"academic_year: {len(mapping)} rows")
    return mapping


def insert_study_modes(cur, rows):
    names = sorted({clean(r["study_mode"]) for r in rows} - {None})
    execute_values(
        cur,
        """
        INSERT INTO study_mode (name) VALUES %s
        ON CONFLICT (name) DO NOTHING
        """,
        [(name,) for name in names],
    )
    cur.execute("SELECT name, id FROM study_mode")
    mapping = dict(cur.fetchall())
    print(f"study_mode: {len(mapping)} rows")
    return mapping


def insert_campuses(cur, rows):
    """Campuses have no UUID in the source, so derive one per (provider, name)."""
    campuses = {
        (r["provider_uuid"], clean(r["campus"]))
        for r in rows
        if clean(r["campus"]) is not None
    }
    values = [
        (derive_uuid("campus", provider_uuid, name), provider_uuid, name)
        for provider_uuid, name in campuses
    ]
    execute_values(
        cur,
        """
        INSERT INTO campus (id, provider_id, name) VALUES %s
        ON CONFLICT (id) DO NOTHING
        """,
        values,
    )
    print(f"campus: {len(values)} rows")
    return {key: derive_uuid("campus", *key) for key in campuses}


def insert_courses(cur, rows):
    """Insert one course per source course_uuid.

    The course UUID is the unique identifier; course_code is not unique (the
    same code can appear for several providers, and occasionally for one
    provider), so courses are keyed by UUID and code is a non-unique index.
    """
    courses = {
        r["course_uuid"]: (
            r["course_uuid"],
            r["provider_uuid"],
            clean(r["course_code"]),
            clean(r["course_name"]),
        )
        for r in rows
    }
    execute_values(
        cur,
        """
        INSERT INTO course (id, provider_id, code, name) VALUES %s
        ON CONFLICT (id) DO UPDATE
        SET provider_id = EXCLUDED.provider_id,
            code = EXCLUDED.code,
            name = EXCLUDED.name
        """,
        list(courses.values()),
    )
    print(f"course: {len(courses)} rows")


def insert_study_options(cur, rows, years, qualifications, study_modes, campuses):
    values = []
    skipped = 0
    for r in rows:
        start_date = clean(r["start_date"])
        if start_date is None:
            skipped += 1
            continue

        campus = clean(r["campus"])
        campus_id = campuses.get((r["provider_uuid"], campus)) if campus else None

        values.append(
            (
                r["study_option_id"],
                r["course_uuid"],
                years[clean(r["academic_year"])],
                qualifications[clean(r["qualification"])],
                study_modes[clean(r["study_mode"])],
                campus_id,
                clean(r["duration"]),
                start_date,
                clean(r["entry_requirements"]),
            )
        )

    if values:
        execute_values(
            cur,
            """
            INSERT INTO course_study_option
                (id, course_id, academic_year_id, qualification_id,
                 study_mode_id, campus_id, duration, start_date, entry_requirements)
            VALUES %s
            ON CONFLICT (id) DO UPDATE
            SET course_id = EXCLUDED.course_id,
                academic_year_id = EXCLUDED.academic_year_id,
                qualification_id = EXCLUDED.qualification_id,
                study_mode_id = EXCLUDED.study_mode_id,
                campus_id = EXCLUDED.campus_id,
                duration = EXCLUDED.duration,
                start_date = EXCLUDED.start_date,
                entry_requirements = EXCLUDED.entry_requirements
            """,
            values,
        )
    print(f"course_study_option: {len(values)} inserted/updated ({skipped} skipped due to missing start_date)")


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "courses2.json"
    rows = load_courses(path)
    print(f"Loaded {len(rows)} records from {path}")

    conn = psycopg2.connect(**DB_CONFIG)
    try:
        with conn:
            with conn.cursor() as cur:
                insert_providers(cur, rows)
                qualifications = insert_qualifications(cur, rows)
                years = insert_academic_years(cur, rows)
                study_modes = insert_study_modes(cur, rows)
                campuses = insert_campuses(cur, rows)
                insert_courses(cur, rows)
                insert_study_options(
                    cur, rows, years, qualifications, study_modes, campuses
                )
    finally:
        conn.close()

    print("Done.")


if __name__ == "__main__":
    main()
