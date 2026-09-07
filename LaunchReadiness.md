# Nine 1.0 Pre-iOS Launch Readiness

This checklist covers the work that can be done before the next iOS compatibility pass.

## Payment Model

- Nine 1.0 has no StoreKit flow.
- Nine 1.0 has no free-roll gate.
- Nine 1.0 has no purchase prompt, Restore Purchase, subscription, account, ads, or backend.
- Starting a new roll should depend on roll state, not entitlement state.

## Persistence And Storage

- Private roll data lives in `Library/Application Support/Nine/Rolls`.
- Legacy beta data from `Documents/Rolls` migrates into Application Support.
- In-progress rolls persist first-pass and second-pass source frames.
- Completed rolls persist only developed frames, contact sheet, and manifest metadata.
- Completed roll display, share, export, and restore should work without raw first/second-pass source frames.
- Device/iCloud backup should include Application Support roll data.

Measure real roll storage with:

```sh
tools/measure-roll-storage.sh /path/to/Rolls
```

Use the app container's `Library/Application Support/Nine/Rolls` directory for current builds. Measure roughly ten representative rolls, then record the real average and 10/50/100/500-roll projections in the KB.

## Automated Checks

Run the app build and test target before every TestFlight candidate.

The first test target covers:

- roll phase progression
- invalid capture by phase
- saved-roll resume separation
- historical mode decode compatibility
- save/restore for partial first pass
- save/restore for awaiting second pass
- save/restore for partial second-pass Saved Rolls
- completed-roll restore without source frames
- missing contact-sheet repair
- contact-sheet and square-image invariants
- nine-output blend invariant

## Manual Device Torture Tests

Run these on a real iPhone before the new-iOS pass:

- rear to rear roll
- front to front roll
- rear to front mixed roll
- front to rear mixed roll
- rapid camera switching
- focus, focus lock, exposure drag, and pinch zoom
- background during first pass
- force-quit after capture
- save first pass, quit, relaunch, resume
- partial second-pass Saved Roll, quit, relaunch, resume
- fill all three Saved Roll slots
- delete Saved Roll
- rename completed roll
- delete completed roll
- denied Camera permission
- denied Photos permission
- limited Photos access
- automatic Photos export after development
- contact-sheet share/export
- individual-frame share/export

## Accessibility Pass

- VoiceOver labels for icon-only controls.
- VoiceOver labels for shutter, roll modes, Saved Rolls, Reveal, and export.
- Larger text sizes do not clip important state.
- Reduce Motion does not make routing or reveal confusing.
- Tap targets remain comfortable.
- State does not rely on color alone.

## Before New iOS Ships

Stop at this line:

- automated tests exist and pass locally
- real-device camera matrix has been run on the current iOS
- storage has been measured from real rolls
- persistence torture tests have not lost work
- accessibility pass has no launch-blocking issues

When the new iOS release or RC is available, rerun the complete camera, persistence, Photos, layout, and export matrix there.
