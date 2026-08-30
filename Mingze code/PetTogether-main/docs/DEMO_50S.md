# Copaw 50-second two-device demo

Trigger phrase: `开始demo`

Before preparing the demo, export `COPAW_DEMO_INVITE_CODE`, `COPAW_DEMO_A_UID`, and `COPAW_DEMO_B_UID`. The script uses the first two booted simulators by default; set `COPAW_DEMO_DEVICE_A` and `COPAW_DEMO_DEVICE_B` to override them. Set `COPAW_DEMO_APP_PATH` when the latest build should be installed before launch.

The visible demo starts after `scripts/prepare_50s_demo.sh` has reset the demo task, kept the Tuesday/Friday 07:30 routine, and returned device B to the Join screen.

| Time | Device | Visible action | Proof point |
| --- | --- | --- | --- |
| 0–4s | A | Show Copaw 50s Demo and the configured invite code | One household can invite another caregiver |
| 4–12s | B | Join as Maya with the configured invite code | The second caregiver enters the same household |
| 12–16s | B | Show Copaw 50s Demo home | Shared household sync |
| 16–25s | A | Add `Evening walk` as a one-time Walking task | Fast task creation; the recurring routine is already prepared |
| 25–31s | A | Choose a person → Maya | Direct assignment request |
| 31–37s | B | Accept | Ownership changes to Maya |
| 37–41s | A | Show “Maya is on it” | Real-time cross-device update |
| 41–46s | B | Mark done | Completion by the assigned caregiver |
| 46–50s | A | Show “Done by Maya” | Completion sync and audit trail |

Success means both devices display the same task state at each handoff and the visible portion completes in 45–55 seconds.
