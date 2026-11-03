"""Explicit fault injection, not naturally observed design failures."""
import argparse
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    source = args.source.read_text(encoding="utf-8")
    args.out.mkdir(parents=True, exist_ok=False)
    mutations = {
        "rounding": ("round_div8 = -((magnitude + 17'sd4) >>> 3);", "round_div8 = value >>> 3;"),
        "sign": ("wire signed [15:0] xw = {{4{x_in[11]}}, x_in};", "wire signed [15:0] xw = {{4{1'b0}}, x_in};"),
        "valid": ("out_valid <= s2_valid;", "out_valid <= s1_valid;"),
    }
    for name, (original, replacement) in mutations.items():
        if source.count(original) != 1:
            raise ValueError(f"Fault injection site is ambiguous: {name}")
        (args.out / f"fir4_{name}.sv").write_text(
            "// DELIBERATELY INJECTED FAULT; NOT A NATURAL BUG.\n" + source.replace(original, replacement),
            encoding="utf-8")
    print("Generated 3 explicitly labelled one-site fault variants")


if __name__ == "__main__":
    main()
