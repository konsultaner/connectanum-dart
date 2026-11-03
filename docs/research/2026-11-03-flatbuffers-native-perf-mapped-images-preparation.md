# Mapped backing-file witness preparation (2026-11-03)

Twenty-five new cases pass for direct scoped-PID mapped backing-file observations
and a candidate join to decoded MMAP2 records. Procfs, credentials and pidhandles
are synthetic; file descriptors and backing files are owned POSIX fixtures.
No actual Linux/root/pidfd/map_files/perf/kernel/VM/native build/benchmark/capture
ran. **Both APIs always return capture_ready=false.**

The source pins exact declared executable/native artifacts, checks process
start/argv byte strings/credentials and opens every matching executable native
mapping through its exact map_files range. Identity and full SHA are checked
against the pinned backing file, including a second bounded sweep. Unknown and
anonymous maps remain. Pathnames and build IDs alone never select the artifact.
VMA page rounding can exceed file length; the source does not impose that false
bound. Sixty-four-bit addresses, inodes, offsets, start cookies and statidentity
values retain decimal strings. Original sample context and MMAP2 body PID remain
separate in the new decoder integration.

[map_files](https://man7.org/linux/man-pages/man5/proc_pid_map_files.5.html) describes
backing-file links and access restrictions involving ptrace checks and additional
capabilities in the initial user namespace. UID0 alone does not prove access.
Actual operations must succeed during future controls; no capability grant,
permissions waiver, freeze or host selection is assumed.
[maps](https://man7.org/linux/man-pages/man5/proc_pid_maps.5.html) distinguishes
addresses, permissions, offsets and device/inode from ambiguous path display.
Only LF ends records; unescaped carriage-return path bytes remain exact.
The URL/hash/size receipt is public; complete third-party pages remain local.

First17 had two fixture-expectation failures: broad close injection interrupted
before the intended identity check, and an environ substring matched the owned
fixture-directory name. Targeted new controls then demonstrated actual read-error
masking and stand-in pidfd leakage. Two candidate controls demonstrated boolean
aliasing and malformed nested records; no forged admission/GO was demonstrated.
After20 passes, new actual duplicate-VMA, carriage-return and JSON statidentity
counterexamples were fixed; partial-read and platform-preflight controls also
pass in final25. Full raw/error JSON is retained from overlap-before onward.
Earlier five phases retain source/log/regular files, but API returns were not
systematically serialized; no full in-memory transcript claim is made.

[Root-qualified assessment and all member hashes](2026-11-03-flatbuffers-native-perf-mapped-images-assessment.json),
[all nine executed source combinations and retained evidence](2026-11-03-flatbuffers-native-perf-mapped-images-evidence.tar.gz).
The test adviser incorrectly claimed fstat on an opened followed FD reports link
attributes. Own FD positives verify target-file identity without loosening checks;
this is not an actual Linux magiclink proof. The final review reached a token
limit without saving an assessment, not backend unavailability or approval.

This witnesses backing files, not private/COW executable pages, source closure,
role labels, event timestamps, global ownership or atomic identity. The candidate
join requires a separately supplied start cookie and makes no recording-clock,
role-lineage or trusted transport claim. Actual kernel compatibility, live
provenance and complete immutable admission remain pending before data.
Prior16 files are byte-identical, old suites not rerun; the existing decoder is
used in new synthetic integration. Eighteen tools uncommitted at601, production/
helper12 unchanged. No new-tool canonical/source commit/push/adoption/strict
release; last free18.98GB exceeds12GiB, no cleanup. RAM cause/repair/parity
remain unproved and both original strict campaigns failed; PR132 stays draft.
