# Round progress

- Branch: `codex/round31-validation`. Only passing work may move to `experiment/route-motion`; nothing promoted yet. Baseline app `fd7d417`, 3.0.0 build 54; README `d7f68df`; audit `e477baa`.
- Committed/pushed: F9 `5113b09` (separate injection/timezone commit, phone test required), F7 `73bbb18`, F8 `b6e3d8f`, F10 `bf31681`, F11 candidate `acee882`, mode foundation `04c9776`.
- CI: all three build-55 package/model/Settings jobs passed. First run dark Activity passed 5/5. Other Activity jobs hit a Bash 3.2 empty-array retry bug; fix and real-selector tests prepared. Repeat 2 also exposed share background-state and Navigation launch failures. No full green or promotion.
- Plane/History: implemented and engine/model/UI checks passed; all four Plane captures obtained. History layouts approved; exact WGS-84 replay fix `14e41f9` passed. Injection/flight/replay phone tests pending.
- Settings: refined seven-group layout and unchanged-default guard passed in `37152992093`; owner approved all Settings captures. Both layout checkpoints complete.
- Train: owner reports BRouter operator refused permission. Endpoint remains disconnected; reminder deleted. Measuring metropolitan France offline rail data/storage/work, then ask owner before any substitute. No limited relations.
- Next: `848fd30` retry guard passes on macOS in `37211359365`; full run pending. `d04cb0d` pushed simulator fixes (native background wait, Navigation cleanup, stable Home and button-bound taps); full run `37211910709` active. Wait for results before further repeats/promotion. Details: `ROUND-AUDIT.md`.
- Awaiting: offline Train scope decision after measurements, all phone tests. Candidate 3.1.0 build 55; no release or README/docs/readme edits. Delete ROUND files only in final delivery commit.
