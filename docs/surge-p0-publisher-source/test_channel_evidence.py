import unittest
from channel_evidence import evaluate

SHA = 'a' * 64
FP1, FP2 = '1' * 32, '2' * 32
NOW = 200000

def r(fp, net, ts, ok, ms, sha=SHA):
    return {'fingerprint': fp, 'network_type': net, 'ts': ts,
            'success': ok, 'second_ms': ms, 'source_version_sha': sha}

class TestChannelEvidence(unittest.TestCase):
    def test_cross_bearer_slow_does_not_void_wifi(self):
        out = evaluate([r(FP1, 'wifi', NOW-15, True, 254),
                        r(FP1, 'cellular', NOW-10, True, 2189)], [FP1], SHA, NOW)
        self.assertEqual(out['by_network']['wifi']['qualified_diagnostic'], 1)
        self.assertEqual(out['by_network']['cellular']['failed_diagnostic'], 1)

    def test_same_bearer_newer_failure(self):
        out = evaluate([r(FP1,'wifi', NOW-20, True, 100),
                        r(FP1,'wifi', NOW-10, False, None)], [FP1], SHA, NOW)
        self.assertEqual(out['by_network']['wifi']['failed_diagnostic'], 1)

    def test_tie_failure_dominates_even_when_before_pass(self):
        out = evaluate([r(FP1,'wifi', NOW-10, False, None),
                        r(FP1,'wifi', NOW-10, True, 100)], [FP1], SHA, NOW)
        self.assertEqual(out['by_network']['wifi']['failed_diagnostic'], 1)

    def test_old_sha_cannot_admit(self):
        out = evaluate([r(FP1,'wifi', NOW-10, True, 100, 'b'*64)], [FP1], SHA, NOW)
        self.assertEqual(out['by_network']['wifi']['no_evidence'], 1)

    def test_stale_and_unobserved(self):
        out = evaluate([r(FP1,'wifi', NOW-86401, True, 50)], [FP1, FP2], SHA, NOW)
        self.assertEqual(out['by_network']['wifi'], {'no_evidence':1,'stale':1})

    def test_future_or_malformed_not_valid(self):
        out = evaluate([r(FP1,'wifi', NOW+1, True, 10),
                        r(FP1,'wifi', NOW-10, True, float('nan'))], [FP1], SHA, NOW)
        self.assertEqual(out['by_network']['wifi']['no_evidence'], 1)

    def test_exact_threshold_is_failure(self):
        out = evaluate([r(FP1,'wifi', NOW-10, True, 300)], [FP1], SHA, NOW)
        self.assertEqual(out['by_network']['wifi']['failed_diagnostic'], 1)

    def test_does_not_claim_native(self):
        out = evaluate([], [FP1], SHA, NOW)
        self.assertEqual(out['kind'], 'client_declared_diagnostic_only')

if __name__ == '__main__':
    unittest.main()
