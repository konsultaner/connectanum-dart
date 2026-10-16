"""Independent validation of stock-SDK heap/GC allocation-volume observations."""

METHOD = "dart_heap_gc_volume_v1"
SCOPE = "dart_managed_heap_allocation_pressure"
LIMIT = 9007199254740991


def _integer(value, label, *, signed=False):
    if type(value) is not int or abs(value) > LIMIT or (not signed and value < 0):
        raise ValueError(f"{label} is not a bounded integer")
    return value


def _map(value, label):
    if not isinstance(value, dict) or any(not isinstance(key, str) for key in value):
        raise ValueError(f"{label} is not an object with string keys")
    return value


def allocation_evidence(process, *, observed_pids, label):
    """Return (bytes, absolute rounding bound, findings); never infer missing zeroes."""
    try:
        process = _map(process, "process metrics")
        meta = _map(process.get("allocation_measurement"), "allocation measurement")
        if (meta.get("status") != "measured" or meta.get("method") != METHOD
                or meta.get("scope") != SCOPE):
            raise ValueError("requires measured heap/GC volume; legacy live-heap census is unsupported")
        target = _integer(process.get("pid"), "process PID")
        observer = _integer(meta.get("observer_pid"), "observer PID")
        if (target <= 0 or observer <= 0 or observer in observed_pids
                or _integer(meta.get("observed_pid"), "observed PID") != target
                or meta.get("capture_strategy") != "external_process"):
            raise ValueError("observer must run outside both measured processes with matching PID attribution")
        if not isinstance(meta.get("sdk_version"), str) or not meta["sdk_version"].strip():
            raise ValueError("observed SDK version is missing")
        times = [_integer(meta.get(key), key) for key in (
            "start_snapshot_before_us", "start_snapshot_after_us",
            "end_snapshot_before_us", "end_snapshot_after_us",
        )]
        if not times[0] <= times[1] < times[2] <= times[3]:
            raise ValueError("snapshot time brackets are invalid")
        groups = meta.get("heap_group_ids")
        heaps = _map(meta.get("heap_observations"), "heap observations")
        if (not isinstance(groups, list) or not groups
                or any(not isinstance(group, str) or not group for group in groups)
                or len(set(groups)) != len(groups) or set(groups) != set(heaps)):
            raise ValueError("application heap group identities are incomplete")
        expected = {}
        heap_before = heap_after = 0
        for group, raw in heaps.items():
            raw = _map(raw, "heap group")
            heap_before += _integer(raw.get("before_used_bytes"), "initial heap")
            heap_after += _integer(raw.get("after_used_bytes"), "final heap")
            deltas = []
            for generation in ("young", "old"):
                delta = _integer(raw.get(f"after_{generation}_collections"), "final collection count") - _integer(raw.get(f"before_{generation}_collections"), "initial collection count")
                if delta < 0:
                    raise ValueError("native collection counter rewound")
                deltas.append(delta)
            expected[group] = tuple(deltas)
        events = meta.get("gc_observations")
        if not isinstance(events, list):
            raise ValueError("raw GC observations are missing")
        observed = {group: [0, 0] for group in groups}
        reclaimed = 0
        unique = set()
        for raw in events:
            raw = _map(raw, "GC observation")
            group = raw.get("isolate_group_id")
            if not isinstance(group, str) or group not in heaps:
                raise ValueError("GC observation has an unknown heap identity")
            kind = raw.get("kind")
            if kind not in ("CollectNewGeneration", "CollectOldGeneration", "StartConcurrentMarking"):
                raise ValueError("GC observation has an unsupported collection kind")
            timestamp = _integer(raw.get("timestamp_us"), "GC timestamp")
            if not times[1] < timestamp < times[2]:
                raise ValueError("GC observation overlaps/outside the snapshot brackets")
            thread = _integer(raw.get("thread_id"), "GC thread")
            identity = (group, thread, timestamp, kind)
            if identity in unique:
                raise ValueError("published GC observations must be unique")
            unique.add(identity)
            fields = [_integer(raw.get(key), key) for key in (
                "before_new_bytes", "after_new_bytes", "before_old_bytes", "after_old_bytes",
            )]
            if any(value % 1024 for value in fields):
                raise ValueError("GC observations do not retain their KB granularity")
            reclaimed += fields[0] - fields[1] + fields[2] - fields[3]
            _integer(reclaimed, "reclaimed-byte sum", signed=True)
            observed[group][0 if kind == "CollectNewGeneration" else 1] += 1
        if any(tuple(observed[group]) != expected[group] for group in groups):
            raise ValueError("GC observations disagree with native collection counters")
        young = sum(counts[0] for counts in observed.values())
        old = sum(counts[1] for counts in observed.values())
        if (_integer(meta.get("young_gc_events"), "young GC total") != young
                or _integer(meta.get("old_gc_events"), "old GC total") != old
                or _integer(process.get("gc_count_delta"), "process GC total") != young + old):
            raise ValueError("process and allocation collection totals disagree")
        for key, actual in (("heap_before_bytes", heap_before), ("heap_after_bytes", heap_after),
                            ("reclaimed_bytes", reclaimed)):
            if _integer(meta.get(key), key, signed=key == "reclaimed_bytes") != actual:
                raise ValueError(f"{key} disagrees with raw observations")
        estimate = _integer(heap_after - heap_before + reclaimed, "allocation estimate")
        bound = len(events) * 2048
        if (_integer(meta.get("estimated_bytes"), "reported estimate") != estimate
                or _integer(process.get("allocated_bytes_delta"), "process allocations") != estimate
                or _integer(meta.get("rounding_error_bound_bytes"), "rounding bound") != bound):
            raise ValueError("allocation estimate or error bound disagrees with raw observations")
        if bound * 100 > estimate:
            raise ValueError("allocation uncertainty exceeds one percent")
        return estimate, bound, []
    except ValueError as error:
        return None, None, [f"{label}: allocation measurement {error}"]
