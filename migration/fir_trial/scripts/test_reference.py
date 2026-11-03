import unittest
from fractions import Fraction
from reference import evaluate, quantize, schedule


class ReferenceTests(unittest.TestCase):
    def test_hand_rounding(self):
        for numerator, wanted in [(-3, 0), (3, 0), (-4, -1), (4, 1), (-12, -2), (12, 2)]:
            with self.subTest(numerator=numerator):
                self.assertEqual(quantize(Fraction(numerator, 8)), wanted)

    def test_hand_impulse(self):
        windows = [[8, 0, 0, 0], [0, 8, 0, 0], [0, 0, 8, 0], [0, 0, 0, 8], [0, 0, 0, 0]]
        self.assertEqual([evaluate(window)[1] for window in windows], [3, -2, 5, -1, 0])

    def test_dc_gain(self):
        self.assertEqual(evaluate([8, 8, 8, 8])[1], 5)
        self.assertEqual(evaluate([-8, -8, -8, -8])[1], -5)

    def test_saturation_extrema(self):
        self.assertEqual(evaluate([2047, -2048, 2047, -2048]), (Fraction(2815), 2047))
        self.assertEqual(evaluate([-2048, 2047, -2048, 2047]), (Fraction(-22525, 8), -2048))

    def test_bubbles_do_not_shift_history(self):
        stimuli = [dict(rst=0, enable=1, in_valid=v, x=x)
                   for v, x in [(1, 8), (0, 999), (1, 0), (0, -999), (0, 0), (0, 0)]]
        rows, _ = schedule(stimuli)
        self.assertEqual([(r["cycle"], r["sample_id"], r["expected_y"]) for r in rows if r["expected_valid"]],
                         [(2, 0, 3), (4, 2, -2)])

    def test_reset_cancels_inflight_and_clears_history(self):
        stimuli = [dict(rst=r, enable=1, in_valid=v, x=x)
                   for r, v, x in [(0, 1, 8), (1, 1, 2047), (0, 1, 0), (0, 0, 0), (0, 0, 0)]]
        rows, coverage = schedule(stimuli)
        self.assertEqual([r["expected_y"] for r in rows if r["expected_valid"]], [0])
        self.assertEqual(coverage["cancelled_reset"], 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
