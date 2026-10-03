# Round progress

- Branch: `codex/round31-validation`. Only passing work may move to `experiment/route-motion`; nothing promoted yet. Baseline app `fd7d417`, 3.0.0 build 54; README `d7f68df`; audit `e477baa`.
- Committed/pushed: F9 `5113b09` (separate injection/timezone commit, phone test required), F7 `73bbb18`, F8 `b6e3d8f`, F10 `bf31681`, F11 candidate `acee882`, mode foundation `04c9776`.
- CI: F11 run `37127966618` still fails system presentation after bounded retry; package/other jobs passed. Foundation `37128519682` build passed. No full green run or repeatability yet.
- Plane: `99e1c15` model/data, `41c2585` altitude adapter, `9f6ce24` engine (phone tests), `ca4667f` UI. Run `37130603952` flight/elevation math passed; app compile failed on misplaced label helper, fixed separately in `99d7904`. Revalidation and screenshots pending.
- History: local 50-entry store, deduplication, delete/clear, successful-start recording, prepare-only replay, Navigation/Settings access and tests prepared. Screenshot approval pending. Settings reorganization next.
- Train: pending BRouter operator permission. Owner sends `docs/BROUTER-PERMISSION-REQUEST.md`; no send date known. No limited relations. On refusal or seven unanswered days, measure one-country offline data/storage/work and ask again. Follow-up scheduled from 2026-10-10, 10:00 Paris.
- Next: validate History/Plane and inspect captures; reorganize Settings; diagnose remaining F11 failures; regression and promotion after green CI. Details: `ROUND-AUDIT.md`.
- Awaiting: rail permission, future Settings/History screenshot approval, all phone tests. No release; no README/docs/readme edits. Delete ROUND files only in final delivery commit.
