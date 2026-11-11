"""G14 aggregate preregistered gate. Does not access cases or answer keys."""
from dataclasses import dataclass

@dataclass(frozen=True)
class Score:
    treatment: float
    control: float
    total: int
    exact: int
    eligible: int
    negative_false_positives: int
    negative_total: int
    conflicts: int

def verdict(s: Score) -> dict[str, bool]:
    if s.total <= 0 or s.eligible <= 0 or s.negative_total <= 0:
        raise ValueError("denominators must be positive")
    if not (0 <= s.treatment <= s.total and 0 <= s.control <= s.total):
        raise ValueError("scores outside denominator")
    if not (0 <= s.exact <= s.eligible and 0 <= s.negative_false_positives <= s.negative_total):
        raise ValueError("counts outside denominator")
    if s.conflicts < 0:
        raise ValueError("conflicts cannot be negative")
    return {
        "a_advantage": s.treatment / s.total > s.control / s.total,
        "b_specificity": s.exact / s.eligible >= 0.5,
        "c_negative_false_positives": s.negative_false_positives / s.negative_total <= 1 / 3,
        "d_conflict": s.conflicts >= 1,
    }

def overall(s: Score) -> bool:
    return all(verdict(s).values())

if __name__ == "__main__":
    frozen = Score(5.0, 4.5, 36, 1, 19, 5, 9, 2)
    print(verdict(frozen), "PASS" if overall(frozen) else "FAIL")
