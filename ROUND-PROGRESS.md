# Round progress

- Branch: `codex/round31-validation`. Only passing work may move to `experiment/route-motion`; nothing promoted yet. Baseline app `fd7d417`, 3.0.0 build 54; README `d7f68df`; audit `e477baa`.
- Committed/pushed: F9 `5113b09` (separate injection/timezone commit, phone test required), F7 `73bbb18`, F8 `b6e3d8f`, F10 `bf31681`, F11 candidate `acee882`, mode foundation `04c9776`.
- CI: `d04cb0d` passes seven jobs, including dark Activity (one case recovered on bounded retry). Light hit 50-minute job timeout with no usable retained log; isolated rerun active. iOS 15 launch `37213194146` passed. No full green/repeatability or promotion.
- Plane/History: implemented and engine/model/UI checks passed; all four Plane captures obtained. History layouts approved; exact WGS-84 replay fix `14e41f9` passed. Injection/flight/replay phone tests pending.
- Settings: refined seven-group layout and unchanged-default guard passed in `37152992093`; owner approved all Settings captures. Both layout checkpoints complete.
- Train: cancelled completely by owner after refusal/offline audit. Scaffolding/audit workflow/tools removed in `71c1b0a`; all Train acceptance withdrawn. Build 56 full validation `37227273239` active. Measurements retained as historical evidence; no rail work pending.
- Next: `315f598` preserves all 5 Activity scenarios/assertions, allows measured 35-second system dispatch with 45-second outcome waits and reserves timeout diagnostics. Full build 56 run `37227547248` passes models/History/defaults/retry guard; other jobs active. Superseded `37227273239` deliberately cancelled; old light diagnostic rerun remains active. Obtain full green, then several unchanged-code full runs. Details: `ROUND-AUDIT.md`.
- Awaiting: final CI/repeatability and phone tests. Candidate 3.1.0 build 56; no release or README/docs/readme edits. Delete ROUND files only in final delivery commit.
