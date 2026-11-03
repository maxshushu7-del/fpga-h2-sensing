"""Independent exact-rational FIR reference and deterministic cycle schedules."""
from fractions import Fraction

COEFFICIENTS = (Fraction(3, 8), Fraction(-2, 8), Fraction(5, 8), Fraction(-1, 8))


def quantize(value: Fraction) -> int:
    magnitude = abs(value)
    whole, remainder = divmod(magnitude.numerator, magnitude.denominator)
    rounded = whole + (2 * remainder >= magnitude.denominator)
    signed = -rounded if value < 0 else rounded
    return max(-2048, min(2047, signed))


def evaluate(samples: list[int]) -> tuple[Fraction, int]:
    exact = sum((coefficient * sample for coefficient, sample in zip(COEFFICIENTS, samples)), Fraction())
    accumulator = sum(coefficient * sample for coefficient, sample in zip((3, -2, 5, -1), samples))
    integer_rounded = (abs(accumulator) + 4) // 8
    if accumulator < 0:
        integer_rounded = -integer_rounded
    integer_result = max(-2048, min(2047, integer_rounded))
    result = quantize(exact)
    if result != integer_result:
        raise AssertionError("Rational and integer references disagree")
    return exact, result


def schedule(inputs: list[dict]) -> tuple[list[dict], dict]:
    history = [0, 0, 0]
    pending = {}
    coverage = dict(accepted=0, published=0, reset_cycles=0, disabled_cycles=0,
                    ignored_reset_valid=0, ignored_disabled_valid=0, bubbles=0,
                    cancelled_reset=0, cancelled_disabled=0, positive_saturation=0,
                    negative_saturation=0, positive_half_tie=0, negative_half_tie=0)
    trace = []
    for cycle, stimulus in enumerate(inputs):
        row = dict(cycle=cycle, **stimulus, expected_valid=0, expected_y=0, sample_id=-1)
        if stimulus["rst"] or not stimulus["enable"]:
            cause = "reset" if stimulus["rst"] else "disabled"
            coverage[f"{cause}_cycles"] += 1
            coverage[f"cancelled_{cause}"] += len(pending)
            if stimulus["in_valid"]:
                coverage[f"ignored_{cause}_valid"] += 1
            pending.clear()
            history = [0, 0, 0]
        else:
            due = pending.pop(cycle, None)
            if due is not None:
                row.update(expected_valid=1, expected_y=due[1], sample_id=due[0])
                coverage["published"] += 1
            if stimulus["in_valid"]:
                sample = stimulus["x"]
                exact, result = evaluate([sample, *history])
                pending[cycle + 2] = (cycle, result)
                history = [sample, *history[:2]]
                coverage["accepted"] += 1
                if exact >= Fraction(4095, 2):
                    coverage["positive_saturation"] += 1
                if exact <= Fraction(-4097, 2):
                    coverage["negative_saturation"] += 1
                if abs(exact).denominator == 2:
                    coverage["positive_half_tie" if exact > 0 else "negative_half_tie"] += 1
            else:
                coverage["bubbles"] += 1
        trace.append(row)
    if pending:
        raise ValueError("Scenario must end with enough enabled bubbles to drain the pipeline")
    return trace, coverage
