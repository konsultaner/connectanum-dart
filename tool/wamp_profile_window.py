"""Choose an interior CPU analysis interval after the real data window is known."""
import argparse
import json
from pathlib import Path
import time

WINDOW_US = 5_000_000
MARGIN_US = 2_000_000
MAX_CLOCK_ENVELOPE_US = 250_000


def integer(value, label):
    if type(value) is not int or value < 0:
        raise ValueError(f'{label} must be a nonnegative integer')
    return value


def monotonic_anchor():
    before = time.time_ns() // 1000
    clock = time.monotonic_ns() // 1000
    after = time.time_ns() // 1000
    return {'wall_before_us': before, 'clock_us': clock, 'wall_after_us': after,
            'implementation': time.get_clock_info('monotonic').implementation}


def clock_range(before, after, start, end, data_start, data_end):
    bounds = []
    for label, anchor in [('before', before), ('after', after)]:
        low = integer(anchor['wall_before_us'], label + ' wall before')
        high = integer(anchor['wall_after_us'], label + ' wall after')
        clock = integer(anchor['clock_us'], label + ' clock')
        if low > high or (label == 'before' and high > data_start) or (label == 'after' and low < data_end):
            raise ValueError('clock observations must enclose the data window')
        bounds.append((low - clock, high - clock))
    if after['clock_us'] <= before['clock_us']:
        raise ValueError('monotonic clock did not advance')
    lower = min(x[0] for x in bounds)
    upper = max(x[1] for x in bounds)
    if upper - lower > MAX_CLOCK_ENVELOPE_US:
        raise ValueError('clock offset envelope is too wide or changed excessively')
    # Intersect the desired interval for every offset in the observed envelope.
    first, last = start - lower, end - upper
    if first < 0 or last <= first:
        raise ValueError('clock conversion does not leave a positive interval')
    return {'origin_us': first, 'extent_us': last - first, 'end_us': last,
            'wall_minus_clock_lower_us': lower, 'wall_minus_clock_upper_us': upper,
            'clock_envelope_us': upper - lower, 'before': before, 'after': after}


def select_window(request):
    data_start = integer(request['data_started_at_us'], 'data start')
    data_end = integer(request['data_completed_at_us'], 'data end')
    capture_start = integer(request['capture_started_at_us'], 'capture start')
    capture_end = integer(request['capture_completed_at_us'], 'capture end')
    if not capture_start <= data_start < data_end <= capture_end:
        raise ValueError('capture does not enclose the actual operation window')
    if data_end - data_start < WINDOW_US + 2 * MARGIN_US:
        raise ValueError('actual operation window is too short for interior analysis')
    end = data_end - MARGIN_US
    start = end - WINDOW_US
    before, after = request['vm_before'], request['vm_after']
    if set(before) != {'router', 'client'} or set(after) != set(before):
        raise ValueError('both VM clock observations are required')
    ranges = {role: clock_range(before[role], after[role], start, end, data_start, data_end)
              for role in ('router', 'client')}
    result = {'schema_version': 2, 'selection': 'posthoc_interior_interval_never_acceptance',
              'sampling_started_at_us': start, 'sampling_completed_at_us': end,
              'data_started_at_us': data_start, 'data_completed_at_us': data_end,
              'capture_started_at_us': capture_start, 'capture_completed_at_us': capture_end,
              'sampling_inside_actual_data_window': True, 'vm_clock_ranges': ranges,
              'clock_bound_scope': 'observed endpoint offset envelope; reject excessive uncertainty/drift'}
    native_before, native_after = request.get('native_before'), request.get('native_after')
    if native_before is not None or native_after is not None:
        if (not isinstance(native_before, dict) or not isinstance(native_after, dict)
                or native_before.get('implementation') != 'clock_gettime(CLOCK_MONOTONIC)'
                or native_after.get('implementation') != 'clock_gettime(CLOCK_MONOTONIC)'):
            raise ValueError('native perf requires observed CLOCK_MONOTONIC anchors')
        native = clock_range(native_before, native_after, start, end, data_start, data_end)
        micros = lambda value: f'{value // 1_000_000}.{value % 1_000_000:06d}'
        native['perf_time_range'] = micros(native['origin_us']) + ',' + micros(native['end_us'])
        result['native_clock_range'] = native
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--clock', action='store_true')
    parser.add_argument('--input', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.clock:
        if args.input or args.output:
            parser.error('--clock cannot select a window')
        print(json.dumps(monotonic_anchor()))
    else:
        if not args.input or not args.output:
            parser.error('--input and --output are required')
        args.output.write_text(json.dumps(select_window(json.loads(args.input.read_text())), indent=2) + '\n')


if __name__ == '__main__':
    main()
