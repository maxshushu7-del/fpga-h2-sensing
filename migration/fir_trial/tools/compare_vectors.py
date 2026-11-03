"""Strict numeric comparison of exported, accepted transactions; no hardware I/O.

Input values are finite decimal strings in contract-defined units. Transactions
must have unique IDs and matching order. This is not a cycle/protocol checker.
Exit codes: 0 match, 1 mismatch, 2 invalid input or I/O error.
"""
from __future__ import annotations

import argparse
import csv
import json
from decimal import Decimal, InvalidOperation
from fractions import Fraction
from pathlib import Path
from typing import TextIO


def decimal_value(text: str) -> Fraction:
    """Use exact rational arithmetic, avoiding float and Decimal context rounding."""
    try:
        value = Decimal(text.strip())
    except (InvalidOperation, ValueError) as error:
        raise ValueError(f"Not a decimal number: {text!r}") from error
    if not value.is_finite():
        raise ValueError(f"Non-finite number: {text!r}")
    return Fraction(value)


def read_vectors(stream: TextIO, key: str, columns: list[str]) -> list[dict]:
    if not key or not columns or len(set(columns)) != len(columns) or key in columns:
        raise ValueError("Select a nonempty ID column and distinct numeric columns")
    reader = csv.DictReader(stream, strict=True)
    headers = reader.fieldnames or []
    if len(set(headers)) != len(headers):
        raise ValueError("Duplicate CSV headers")
    required = [key, *columns]
    if any(name not in headers for name in required):
        raise ValueError(f"Missing required headers: {required!r}")
    result = []
    seen = set()
    for row in reader:
        if None in row or any(value is None for value in row.values()):
            raise ValueError(f"Malformed CSV row near line {reader.line_num}")
        identifier = row[key].strip()
        if not identifier or identifier in seen:
            raise ValueError(f"Empty or duplicate transaction ID: {identifier!r}")
        seen.add(identifier)
        result.append({"id": identifier,
                       "values": {name: decimal_value(row[name]) for name in columns}})
    if not result:
        raise ValueError("No transactions: an empty run cannot pass")
    return result


def compare_vectors(expected: list[dict], actual: list[dict], columns: list[str],
                    tolerance: Fraction = Fraction(0)) -> dict:
    if tolerance < 0:
        raise ValueError("Tolerance must be nonnegative")
    if not expected or not actual:
        raise ValueError("Both runs must contain transactions")
    expected_ids = [row["id"] for row in expected]
    actual_ids = [row["id"] for row in actual]
    if len(set(expected_ids)) != len(expected_ids) or len(set(actual_ids)) != len(actual_ids):
        raise ValueError("Duplicate transaction IDs")
    expected_map = {row["id"]: row["values"] for row in expected}
    actual_map = {row["id"]: row["values"] for row in actual}
    missing = [identifier for identifier in expected_ids if identifier not in actual_map]
    unexpected = [identifier for identifier in actual_ids if identifier not in expected_map]
    differences = []
    difference_count = 0
    common_count = 0
    for identifier in expected_ids:
        if identifier not in actual_map:
            continue
        common_count += 1
        for name in columns:
            wanted = expected_map[identifier][name]
            observed = actual_map[identifier][name]
            error = abs(observed - wanted)
            if error > tolerance:
                difference_count += 1
                if len(differences) < 20:
                    differences.append({"sample_id": identifier, "column": name,
                                        "expected_exact": str(wanted),
                                        "actual_exact": str(observed),
                                        "abs_error_exact": str(error)})
    order_matches = expected_ids == actual_ids
    passed = not missing and not unexpected and order_matches and difference_count == 0
    return {"status": "PASS" if passed else "FAIL",
            "expected_transactions": len(expected), "actual_transactions": len(actual),
            "compared_transactions": common_count, "columns": columns,
            "absolute_tolerance_exact": str(tolerance), "order_matches": order_matches,
            "missing_ids": missing, "unexpected_ids": unexpected,
            "value_mismatches": difference_count, "first_differences": differences,
            "scope": "numeric accepted-transaction comparison, not cycle timing or hardware"}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected", required=True, type=Path)
    parser.add_argument("--actual", required=True, type=Path)
    parser.add_argument("--columns", required=True, nargs="+")
    parser.add_argument("--key", default="sample_id")
    parser.add_argument("--abs-tolerance", default="0")
    args = parser.parse_args(argv)
    try:
        tolerance = decimal_value(args.abs_tolerance)
        if tolerance < 0:
            raise ValueError("Tolerance must be nonnegative")
        with args.expected.open(encoding="utf-8-sig", newline="") as stream:
            expected = read_vectors(stream, args.key, args.columns)
        with args.actual.open(encoding="utf-8-sig", newline="") as stream:
            actual = read_vectors(stream, args.key, args.columns)
        result = compare_vectors(expected, actual, args.columns, tolerance)
    except (OSError, UnicodeError, ValueError, csv.Error) as error:
        print(json.dumps({"status": "ERROR", "reason": str(error)}, ensure_ascii=False))
        return 2
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
