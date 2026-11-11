import unittest
from g14_verdict import Score, verdict, overall

class G14VerdictTests(unittest.TestCase):
    def test_frozen_v12_new_set_fails(self):
        s = Score(5, 4.5, 36, 1, 19, 5, 9, 2)
        self.assertEqual(verdict(s), {"a_advantage": True, "b_specificity": False, "c_negative_false_positives": False, "d_conflict": True})
        self.assertFalse(overall(s))

    def test_exact_threshold(self):
        self.assertTrue(verdict(Score(6, 4, 36, 10, 20, 3, 9, 1))["b_specificity"])

    def test_reject_zero_denominator(self):
        with self.assertRaises(ValueError): verdict(Score(0, 0, 0, 0, 19, 0, 9, 1))

    def test_reject_invalid_count(self):
        with self.assertRaises(ValueError): verdict(Score(5, 4, 36, 20, 19, 0, 9, 1))

    def test_no_advantage_on_tie(self):
        self.assertFalse(verdict(Score(5, 5, 36, 10, 19, 0, 9, 1))["a_advantage"])

if __name__ == "__main__":
    unittest.main()
