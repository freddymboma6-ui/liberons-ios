# Libérons — Backup reliability hardening (non-production work plan)

Status: investigation / not deployed. Source branch: `library-protected-media`.

## Verified observations (2026-11-18 UTC)
- 21:22:47 photo 2,095,765 B: upload session completed, asset protected; verify-upload observed.
- 21:22:50 video 8,774,892 B: initiated, no verify-upload observed, session later failed after B2 HEAD reported missing.
- 21:24:14 photo 1,755,119 B: initiated, no verify-upload observed, session later failed after B2 HEAD reported missing.
- These records do **not** identify the direct-to-B2 PUT HTTP status or iOS URLSession error. An expired signed URL is a hypothesis, not an established root cause.

## Code findings
- `Liberons/SupabaseService.swift`: background URLSession uploads from file; in-memory continuation dictionary keyed by URLSession taskIdentifier.
- On process relaunch `reconnect()` enumerates tasks but does not reconstruct the association to asset/session or trigger verify-upload on completion.
- In `didCompleteWithError`, missing continuation only prints a message; it does not finalize the cloud asset.
- `Liberons/BackupEngine.swift`: temporary exported file removed with `defer`; investigate lifecycle and URLSession's staging behavior with device testing.
- `initiate-upload` creates B2 presigned PUT URLs with X-Amz-Expires=900 and can resume some existing unresolved reservations.

## Safe implementation sequence (separate reviewable changes)
1. Instrument iOS upload attempts with non-sensitive structured diagnostics: asset/session IDs, attempt ID, elapsed time, HTTP status, URLSession error domain/code, bytes sent, whether app was relaunched. Never log signed URLs, auth headers, private media or full paths.
2. Persist a mapping from background URLSession task to asset/session IDs before starting the task. Rehydrate it at launch; on callback, verify successful PUT with server, then remove mapping only after verified protected status. Handle missing continuation without declaring success. Ensure idempotent verification.
3. For HTTP 401/403/expired signature or transient network errors, verify/reconcile object existence first, then renew the same reservation and retry with bounded exponential backoff + jitter; never allocate a second pending quota reservation for the same asset.
4. Make the temp-file lifecycle explicit and safe for background URLSession; do not delete a source before URLSession has durably staged it. Confirm Apple platform semantics in a real-device test.
5. Add bounded server-side reconciliation and monitoring: upload started/completed/failed, failure reason categories, stuck sessions, retries, B2 HEAD outcome, rate limits, queue lag. Avoid per-file high-cardinality metrics.
6. Test offline during upload, airplane mode, app suspension/force-quit, relaunch, signed URL expiry, B2 4xx/5xx, concurrent retries, duplicate initiation, iCloud original not locally available, quota exhaustion and 1k+ queued assets.
7. Test progressive rollout, rollback, and load at increasing scale. A billion-user target requires measured capacity planning; do not claim tested capacity.

## Invariants
- A local original is NEVER deleted automatically or suggested for deletion unless its cloud copy is verified and the user confirms the deletion.
- Do not modify already protected assets or break shared storage, subscription quotas, FR/EN UX or existing receipt flows.
- No production deploy without device-level verification, metrics baseline, and rollback plan.
