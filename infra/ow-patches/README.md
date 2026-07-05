# Open Wearables — Whoop workout-sync fix (self-contained)

## What this is
A local, self-owned copy of the fix that makes **Whoop workouts/activities sync**
into Open Wearables (recovery + sleep always worked; *workouts* were silently
broken by a crash in OW's after-commit webhook path).

- `fix-whoop-workout-sync.patch` — the two-file diff (`database.py` +
  `event_record_service.py`).
- `apply.sh` — idempotently re-applies it to the VM, rebuilds the image, and
  restarts the sync containers.

## Why it lives here (not in Open Wearables' git)
Deliberately kept in **our** repo so there is **no dependency on OW's upstream
git** and nothing to wait on. The fix is currently applied on the VM and baked
into the running Docker image, so it survives **container restarts and VM
reboots**. It is only lost if the VM is **re-provisioned / OW rebuilt from clean
source** — in which case, run `apply.sh` to restore it.

## Current status (as of 2026-07-05)
- Fix is **live** on the VM `open-wearables` (us-central1-a).
- Workout auto-sync **works via polling**: OW's celery beat polls Whoop hourly,
  and the iOS app triggers a sync every ~15 min while open — new workouts appear
  automatically at `/api/v1/users/<uid>/events/workouts`, no manual backfill.
- No crashes in the worker logs since the fix.

## When to run apply.sh
Only if Whoop **activities stop showing up again** (a sign the VM was rebuilt from
clean source). From your Mac:

```bash
bash infra/ow-patches/apply.sh
```

## Optional: instant sync via webhook
Auto-sync currently relies on **polling** (hourly + 15-min-when-app-open), which
is fine — Whoop scores a workout minutes after you finish anyway. If you ever
want *near-instant* sync, point the Whoop developer-dashboard webhook at the VM
(`https://35-238-86-12.nip.io/...`). Not required; polling covers the normal case.
