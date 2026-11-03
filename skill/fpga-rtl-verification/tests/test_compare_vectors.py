"""Synthetic helper tests only; these do not run an RTL DUT or an AI model."""
import contextlib
import io
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from compare_vectors import compare_vectors, decimal_value, main, read_vectors


def vectors(text, columns=None):
    return read_vectors(io.StringIO(text), "sample_id", columns or ["y"])


class ComparisonTests(unittest.TestCase):
    def test_equal_signed_values(self):
        rows = vectors("sample_id,y\n0,-32768\n1,32767\n")
        self.assertEqual(compare_vectors(rows, rows, ["y"])["status"], "PASS")

    def test_one_unit_error_is_not_rounded_away(self):
        left = vectors("sample_id,y\n0,10000000000000000000000000000000000000000\n")
        right = vectors("sample_id,y\n0,10000000000000000000000000000000000000001\n")
        report = compare_vectors(left, right, ["y"])
        self.assertEqual(report["status"], "FAIL")
        self.assertEqual(report["first_differences"][0]["abs_error_exact"], "1")

    def test_missing_and_extra_transactions(self):
        report = compare_vectors(vectors("sample_id,y\na,1\nb,2\n"),
                                 vectors("sample_id,y\na,1\nc,2\n"), ["y"])
        self.assertEqual(report["missing_ids"], ["b"])
        self.assertEqual(report["unexpected_ids"], ["c"])
        self.assertEqual(report["status"], "FAIL")

    def test_reordering_fails_even_if_values_match(self):
        report = compare_vectors(vectors("sample_id,y\na,1\nb,2\n"),
                                 vectors("sample_id,y\nb,2\na,1\n"), ["y"])
        self.assertEqual(report["value_mismatches"], 0)
        self.assertFalse(report["order_matches"])
        self.assertEqual(report["status"], "FAIL")

    def test_tolerance_inclusive_and_beyond(self):
        rows = vectors("sample_id,y\na,1.0\n")
        self.assertEqual(compare_vectors(rows, vectors("sample_id,y\na,1.1\n"),
                                         ["y"], decimal_value("0.1"))["status"], "PASS")
        self.assertEqual(compare_vectors(rows, vectors("sample_id,y\na,1.100001\n"),
                                         ["y"], decimal_value("0.1"))["status"], "FAIL")

    def test_multiple_columns(self):
        a = vectors("sample_id,y,z\na,1,-2\n", ["y", "z"])
        b = vectors("sample_id,y,z\na,1,-3\n", ["y", "z"])
        self.assertEqual(compare_vectors(a, b, ["y", "z"])["value_mismatches"], 1)

    def test_equivalent_decimal_representations(self):
        report = compare_vectors(vectors("sample_id,y\na,1e-1\n"),
                                 vectors("sample_id,y\na,0.1000\n"), ["y"])
        self.assertEqual(report["status"], "PASS")

    def test_reject_bad_headers_and_rows(self):
        for text in ["sample_id,y,y\na,1,1\n", "sample_id,z\na,1\n",
                     "sample_id,y\na\n", "sample_id,y\na,1,2\n"]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                vectors(text)

    def test_reject_empty_and_duplicate_ids(self):
        for text in ["sample_id,y\n,1\n", "sample_id,y\na,1\na,1\n"]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                vectors(text)

    def test_reject_empty_runs(self):
        for text in ["", "sample_id,y\n"]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                vectors(text)

    def test_reject_nonfinite_and_other_bases(self):
        for value in ["NaN", "Infinity", "-Infinity", "0xff", "", "word"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                vectors(f"sample_id,y\na,{value}\n")

    def test_reject_negative_tolerance(self):
        rows = vectors("sample_id,y\na,1\n")
        with self.assertRaises(ValueError):
            compare_vectors(rows, rows, ["y"], decimal_value("-0.1"))

    def test_reject_duplicate_selected_columns(self):
        with self.assertRaises(ValueError):
            vectors("sample_id,y\na,1\n", ["y", "y"])

    def test_cli_fixtures_and_error_code(self):
        examples = Path(__file__).resolve().parents[1] / "examples"
        common = ["--expected", str(examples / "reference.csv"), "--columns", "y"]
        for name, expected_code, expected_status in [
                ("observed_pass.csv", 0, "PASS"),
                ("observed_fail.csv", 1, "FAIL"),
                ("nonexistent_input.csv", 2, "ERROR")]:
            with self.subTest(name=name), contextlib.redirect_stdout(io.StringIO()) as output:
                code = main([*common, "--actual", str(examples / name)])
                self.assertEqual(code, expected_code)
                self.assertEqual(json.loads(output.getvalue())["status"], expected_status)


if __name__ == "__main__":
    unittest.main()
