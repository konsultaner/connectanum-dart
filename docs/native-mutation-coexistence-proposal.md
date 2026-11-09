# Native Mutation Coexistence Proposal

Status: external-image storage approved on 2026-11-09; host-headroom policy
remains a proposal, not an active resource-policy change.
The active execution plan remains
`docs/exec-plans/2026-09-15-regression-mutation-coverage.md`. Do not launch a
campaign under this proposal before its admission rules are approved, tested,
committed, and included in a fresh fingerprint-matched preflight.

## Why Change Admission

This is a work machine, so waiting for zero unrelated activity is unlikely to
be useful. On 2026-11-09 the host reported 32 logical CPUs and 512 GiB of RAM,
while two long-lived VMs and intermittent local inference were active. Internal
free space varied from roughly 3 GiB to 20 GiB during the same day. The shared
machine lock correctly excludes local inference and other cooperating native
jobs, but does not reserve CPU, memory bandwidth, I/O, or disk against VMs and
unrelated processes. An empty lock is therefore necessary, not sufficient.

The existing preflight floor is 13 GiB, first pilot admission is 15 GiB, and
the runtime free-disk reserve is 4 GiB. The campaign uses 32 batches, four
workers and four Cargo jobs, with unchanged original tests, operators,
assertions, deadlines, evidence rules, and independent strict 95% Core and FFI
gates. This proposal does not lower any of those requirements.

## Isolation Choice

Prefer a native macOS run with an additional measured host-headroom guard and
scratch/evidence on a validated, physically separate APFS-formatted drive. A
dedicated physical runner remains the stronger choice if one is available.
The currently mounted external `Storage` drive has ample free capacity but is
ExFAT; do not move Cargo scratch or audited evidence there as-is, reformat or
repartition it, or assume its filesystem semantics satisfy the runner's
atomic-write and durability checks. A separate APFS volume on the same internal
APFS container may reserve storage capacity, but it still shares physical I/O
and currently has too little stable headroom to be an attractive solution.

A non-destructive fallback is a fixed-size (not sparse) APFS disk image stored
on the existing external ExFAT drive. This gives the campaign an APFS volume
without repartitioning the drive, but the image still inherits the external
USB device's throughput, disconnect risk, and backing ExFAT durability. It is
not equivalent to a separately formatted APFS SSD. Use a fresh Git worktree,
temporary directory and evidence directory inside that image so the unchanged
13-GiB preflight floor and 15-GiB pilot admission measure the actual campaign
filesystem. Do not reuse a mounted image or workspace owned by another task.

On 2026-11-09, a disposable 256-MiB fixed-size APFS image on that drive was
fully allocated. Within the mounted image, an executable file, symlink,
fsynced file and directory, and atomic replacement worked; the files survived
detach/reattach, and `diskutil verifyVolume` passed. This is a filesystem
semantics probe, not a throughput, sustained-I/O, disconnect-recovery or full
campaign validation. The internal APFS container had about 7.8 GB free, so a
new internal worktree cannot meet the unchanged preflight floor.

A macOS VM on this same host could cap the guest's visible CPU count and memory
and provide a private filesystem. It does **not** reserve physical cores or
protect guest I/O from the existing VMs and host jobs. A Linux VM or Docker
container would also change platform-sensitive native, Dart, browser, and FFI
verification, so it is not an equivalent shortcut. Do not create a third VM or
modify the existing VMs without a separate approval and a matching-environment
validation plan.

## Proposed Admission And Abort Contract

1. Keep the repository exclusive lease and machine-wide local-inference guard.
   Never run beside another mutation campaign, a cooperating lease holder, or
   uncoordinated tests/builds that threaten the measured budget.
2. Collect read-only host telemetry across representative working hours before
   choosing thresholds: CPU utilization and run queue, memory pressure and
   swap, disk free space and write rate on each target filesystem, I/O latency,
   and the identity/load of persistent VMs. Record the measurement window and
   source paths. Do not start synthetic load or local inference for this audit;
   observe other jobs' normal activity without interrupting them.
3. Set numeric, reviewable admission and abort thresholds from that baseline
   and the campaign's existing controls. Require a sustained admission window,
   not one favorable sample. Keep the existing disk floor, pilot budget,
   per-worker scratch cap, and runtime reserve as hard lower bounds; add a
   conservative allowance for unrelated write bursts. Recheck before every
   phase and sample during it. Fail closed on missing telemetry, contention,
   disk loss, filesystem disconnect, or policy drift. Excluded/aborted work
   earns no mutation-kill credit.
4. Prove the chosen filesystem separately before use: physical-device identity,
   free-space accounting, executable permissions, symlink behavior, atomic
   replacement and fsync, and safe recovery after interrupted writes. If using
   a fixed-size external image, verify its allocated backing-file size and
   free-space accounting before and during each phase. Do not rely on a sparse
   disk image as reserved capacity.
5. Implement the new guard with fail-first resource tests, then commit it with
   the approved policy. Its fingerprint changes the evidence environment:
   repeat canonical `bin/verify`, exact Core/FFI inventories, default/lean
   controls, and a representative timing pilot before a fresh full campaign.
   Compare pilot timing and resource samples with the controls; if workload
   interference makes original deadlines unreliable, stop and prefer a
   dedicated runner rather than weakening deadlines or counting errors as
   kills.

## Approval Boundary

The operator approved a dedicated fixed-size 64-GiB APFS image on the existing
external drive, without reformatting it. This does not authorize cleanup, VM
setup, unrelated disk alteration, new resource thresholds, or relaxation of
the active run policy. A fresh clean worktree, canonical preflight and exact
controls must establish whether the external drive can sustain the unchanged
campaign. If it cannot, stop and use a separate APFS SSD or dedicated runner;
do not weaken original deadlines or credit infrastructure failures as kills.
Prior mutation and coverage evidence remains immutable.

## Platform References

- Apple describes VM `cpuCount` as CPUs made available to the guest, not
  physical cores reserved from the host:
  <https://developer.apple.com/documentation/virtualization/vzvirtualmachineconfiguration/cpucount>.
- Docker Desktop describes its Mac CPU setting as a maximum and its memory
  setting as RAM allocated to its Linux VM:
  <https://docs.docker.com/desktop/settings-and-maintenance/settings/>.
- Apple states that APFS volumes in one container share free capacity, and
  Disk Utility's optional volume reserve protects capacity for that volume:
  <https://support.apple.com/en-gb/guide/security/seca6147599e/web>,
  <https://support.apple.com/en-ie/guide/disk-utility/dskua9e6a110/mac>.
