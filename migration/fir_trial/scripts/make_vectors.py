"""Generate synthetic vectors and coverage; writes only to explicit --out."""
import argparse
import csv
import json
import random
from pathlib import Path
from reference import schedule


def make_inputs(seed):
    random_source = random.Random(seed)
    inputs = []

    def add(x=0, valid=0, enable=1, rst=0):
        inputs.append(dict(rst=rst, enable=enable, in_valid=valid, x=x))

    def flush():
        for _ in range(4):
            add()

    for _ in range(3):
        add(x=2047, valid=1, rst=1)
    for value in [8, 0, 0, 0, 0]:
        add(value, 1)
    flush()
    for value in [-1, 1, -4, 4, -2048, 2047]:
        add(rst=1)
        add(value, 1)
        for _ in range(5):
            add(0, 1)
        flush()
    for dc_value in [8, -8]:
        add(rst=1)
        for position in range(12):
            add(dc_value, 1)
            if position % 3 == 1:
                add(2047, 0)
        flush()
    for values in [[-2048, 2047, -2048, 2047], [2047, -2048, 2047, -2048]]:
        add(rst=1)
        for value in values:
            add(value, 1)
        flush()
    for cause in ["reset", "disable"]:
        add(8, 1)
        add(16, 1)
        add(2047, 1, rst=(cause == "reset"), enable=(cause != "disable"))
        add(0, 1)
        flush()
    for _ in range(1200):
        add(random_source.randint(-2048, 2047), int(random_source.random() < 0.72),
            int(random_source.random() >= 0.06), int(random_source.random() < 0.025))
    flush()
    return inputs


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--seed", type=int, default=20261018)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    rows, coverage = schedule(make_inputs(args.seed))
    for name in ["accepted", "published", "ignored_reset_valid", "ignored_disabled_valid", "bubbles",
                 "cancelled_reset", "cancelled_disabled", "positive_saturation", "negative_saturation",
                 "positive_half_tie", "negative_half_tie"]:
        if not coverage[name]:
            raise AssertionError(f"Missing reference scenario: {name}")
    with (args.out / "stimulus.txt").open("w", encoding="utf-8", newline="\n") as stream:
        for row in rows:
            stream.write(" ".join(str(int(row[name])) for name in
                         ["cycle", "rst", "enable", "in_valid", "x", "expected_valid", "expected_y", "sample_id"]) + "\n")
    with (args.out / "expected.csv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["sample_id", "y"])
        for row in rows:
            if row["expected_valid"]:
                writer.writerow([row["sample_id"], row["expected_y"]])
    result = dict(seed=args.seed, cycles=len(rows), coverage=coverage,
                  evidence="synthetic stimulus, exact reference; not DUT coverage or hardware")
    (args.out / "coverage.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
