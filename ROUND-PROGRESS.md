# Round progress

- Branch: `codex/round31-validation`. Only passing work may move to `experiment/route-motion`; nothing promoted yet. Baseline app `fd7d417`, 3.0.0 build 54; README `d7f68df`; audit `e477baa`.
- Committed/pushed: F9 `5113b09` (separate injection/timezone commit, phone test required), F7 `73bbb18`, F8 `b6e3d8f`, F10 `bf31681`, F11 candidate `acee882`, mode foundation `04c9776`.
- CI: `d04cb0d` passes seven jobs, including dark Activity (one case recovered on bounded retry). Light hit 50-minute job timeout with no usable retained log; isolated rerun active. iOS 15 launch `37213194146` passed. No full green/repeatability or promotion.
- Plane/History: implemented and engine/model/UI checks passed; all four Plane captures obtained. History layouts approved; exact WGS-84 replay fix `14e41f9` passed. Injection/flight/replay phone tests pending.
- Settings: refined seven-group layout and unchanged-default guard passed in `37152992093`; owner approved all Settings captures. Both layout checkpoints complete.
- Train: operator refused permission; endpoint disconnected, reminder deleted. France audit `5b2bf92` / `37213117463` passed: 88.6 MB compressed, 273.1 MB installed, 634.7 MB update peak. `docs/OFFLINE-RAIL-AUDIT.md` records work/limits. Asked owner to approve offline packs/France pilot or keep Train pending; answer required before implementation.
- Next: inspect light-job rerun `111508073347` in `37211910709`, fix any evidenced cause, then several unchanged-code full runs. Older `37211359365` timed out in both Activity jobs. Details: `ROUND-AUDIT.md`.
- Awaiting: offline Train scope decision after measurements, all phone tests. Candidate 3.1.0 build 55; no release or README/docs/readme edits. Delete ROUND files only in final delivery commit.
