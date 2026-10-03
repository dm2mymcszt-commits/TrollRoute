# Round progress

- Branch: `codex/round31-validation`. Only passing work may move to `experiment/route-motion`; nothing promoted yet. Baseline app `fd7d417`, 3.0.0 build 54; README `d7f68df`; audit `e477baa`.
- Committed/pushed: F9 `5113b09` (separate injection/timezone commit, phone test required), F7 `73bbb18`, F8 `b6e3d8f`, F10 `bf31681`, F11 candidate `acee882`, mode foundation `04c9776`.
- CI: first candidate `37127628845` failed Live Activity tests. F11 isolation/retry run `37127966618` running; foundation run `37128519682` queued. Phase 0 green-CI and F11 repeatability acceptance remain unmet.
- Plane: model/data `99e1c15`; altitude adapter `41c2585` and engine `9f6ce24` need phone tests. Airport picker, Plane tab, live speed, flight altitude explanation and simulator UI checks prepared. Combined candidate validation next; no acceptance claimed yet.
- Train: pending BRouter operator permission. Owner sends `docs/BROUTER-PERMISSION-REQUEST.md`; no send date known. No limited relations. On refusal or seven unanswered days, measure one-country offline data/storage/work and ask again. Follow-up scheduled from 2026-10-10, 10:00 Paris.
- Next: validate Plane candidate and inspect simulator captures; implement History and Settings; regression and promotion after green CI. Details: `ROUND-AUDIT.md`.
- Awaiting: rail permission, future Settings/History screenshot approval, all phone tests. No release; no README/docs/readme edits. Delete ROUND files only in final delivery commit.
