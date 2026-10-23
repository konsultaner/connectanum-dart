import copy
import unittest

import wamp_profile_window as windows


class ProfileWindowTests(unittest.TestCase):
    def request(self):
        # The observed E2EE request began long after the old fixed-delay sample.
        start, end = 1792687453665265, 1792687483669259
        def anchor(wall, offset, width=200):
            return {'wall_before_us': wall, 'wall_after_us': wall + width,
                    'clock_us': wall - offset}
        before = {role: anchor(start - 30_000_000, 1792687066000000 + i * 1000)
                  for i, role in enumerate(('router', 'client'))}
        after = {role: anchor(end + 1000, 1792687066000000 + i * 1000, 300)
                 for i, role in enumerate(('router', 'client'))}
        native_before = dict(before['router'], implementation='clock_gettime(CLOCK_MONOTONIC)')
        native_after = dict(after['router'], implementation='clock_gettime(CLOCK_MONOTONIC)')
        return {'data_started_at_us': start, 'data_completed_at_us': end,
                'capture_started_at_us': start - 30_000_000, 'capture_completed_at_us': end + 2000,
                'vm_before': before, 'vm_after': after,
                'native_before': native_before, 'native_after': native_after}

    def test_slow_setup_selects_only_a_late_real_operation_interval(self):
        request = self.request()
        result = windows.select_window(request)
        self.assertEqual(result['sampling_started_at_us'], 1792687476669259)
        self.assertEqual(result['sampling_completed_at_us'], 1792687481669259)
        self.assertTrue(result['sampling_inside_actual_data_window'])
        for item in result['vm_clock_ranges'].values():
            self.assertEqual(item['extent_us'], 4_999_700)
            self.assertGreaterEqual(item['origin_us'] + item['wall_minus_clock_lower_us'], result['sampling_started_at_us'])
            self.assertLessEqual(item['end_us'] + item['wall_minus_clock_upper_us'], result['sampling_completed_at_us'])

    def test_actual_failed_capture_cannot_be_relabelled_as_valid(self):
        request = self.request()
        request['capture_started_at_us'] = 1792687426334269
        request['capture_completed_at_us'] = 1792687441029098
        with self.assertRaisesRegex(ValueError, 'capture does not enclose'):
            windows.select_window(request)

    def test_distinct_vm_clocks_use_independent_conservative_offsets(self):
        result = windows.select_window(self.request())
        router, client = (result['vm_clock_ranges'][role] for role in ('router', 'client'))
        self.assertEqual(client['origin_us'], router['origin_us'] - 1000)
        self.assertRegex(result['native_clock_range']['perf_time_range'], r'^\d+\.\d{6},\d+\.\d{6}$')

    def test_reversed_or_short_data_and_capture_are_rejected(self):
        original = self.request()
        for key, value in [('data_completed_at_us', original['data_started_at_us']),
                           ('data_completed_at_us', original['data_started_at_us'] + 8_000_000),
                           ('capture_started_at_us', original['data_started_at_us'] + 1),
                           ('capture_completed_at_us', original['data_completed_at_us'] - 1)]:
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                windows.select_window(dict(original, **{key: value}))

    def test_invalid_scalars_are_rejected(self):
        for value in [True, -1, None, 1.5, float('nan'), float('inf'), '1000']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                windows.select_window(dict(self.request(), data_started_at_us=value))

    def test_missing_vm_clocks_are_rejected(self):
        request = self.request()
        del request['vm_after']['client']
        with self.assertRaisesRegex(ValueError, 'both VM'):
            windows.select_window(request)

    def test_clock_observations_must_bracket_actual_data(self):
        for phase, field, value in [('vm_before', 'wall_after_us', self.request()['data_started_at_us'] + 1),
                                     ('vm_after', 'wall_before_us', self.request()['data_completed_at_us'] - 1)]:
            request = self.request()
            request[phase]['router'][field] = value
            with self.subTest(phase=phase), self.assertRaises(ValueError):
                windows.select_window(request)

    def test_clock_drift_uncertainty_or_backwards_time_is_rejected(self):
        for field, delta in [('clock_us', -500_000), ('wall_after_us', 500_000), ('clock_us', -100_000_000)]:
            request = self.request()
            request['vm_after']['router'][field] += delta
            with self.subTest(field=field, delta=delta), self.assertRaises(ValueError):
                windows.select_window(request)
        request = self.request()
        request['vm_after']['router']['clock_us'] = request['vm_before']['router']['clock_us']
        with self.assertRaisesRegex(ValueError, 'did not advance'):
            windows.select_window(request)

    def test_native_clock_is_explicit_and_optional(self):
        request = self.request()
        request.pop('native_before'); request.pop('native_after')
        self.assertNotIn('native_clock_range', windows.select_window(request))
        for field in ['native_before', 'native_after']:
            request = self.request(); request[field]['implementation'] = 'unknown'
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, 'CLOCK_MONOTONIC'):
                windows.select_window(request)

    def test_request_is_not_modified(self):
        request = self.request(); before = copy.deepcopy(request)
        windows.select_window(request)
        self.assertEqual(request, before)


if __name__ == '__main__':
    unittest.main()
