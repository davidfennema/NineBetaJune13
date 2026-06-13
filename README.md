# Nine

Nine is a deliberately constrained square-format iOS camera: a nine-frame roll exposed twice, then developed as a set. Nothing is reviewed between exposures, and nothing is editable after development.

## Run

Open `Afterimage.xcodeproj` in Xcode, select the `Nine` scheme, and run on a physical iPhone running iOS 18 or later. A device is required for meaningful camera and Photos behavior.

## Implemented Experience

- Four understated roll modes selected before exposure: Freeform, Desaturated, Black & White, and High Contrast.
- Strict nine-frame first pass followed by a black intermission and nine-frame second pass.
- A centered 1:1 viewing frame inspired by 6 by 6 film cameras; captures, results, and exports stay square.
- A brief black physical-shutter-style closure after each exposure.
- A blurred, low-opacity, slightly displaced square ghost of the paired first exposure during pass two.
- Fast AVFoundation photo capture, tap-to-focus, hold-to-lock focus for recomposition, vertical-drag intentional defocus, pinch-to-zoom, and exposure compensation.
- A restrained Core Image blend pipeline that normalizes exposure, balances both moments, and protects highlights while keeping slight registration variation.
- A developing interstitial followed by staggered contact-sheet reveal.
- Horizontal review from the contact sheet through each individual frame, with context-aware sharing.
- Automatic Photos export of the contact sheet and all developed frames.
- Local JSON persistence of completed and in-progress roll data, including stored exposures and developed outputs.

## Structure

- `Afterimage/Camera`: AVFoundation session ownership and SwiftUI preview.
- `Afterimage/Roll`: roll state machine and app-level view model.
- `Afterimage/Processing`: blend pipeline and 3 by 3 grid renderer.
- `Afterimage/Persistence`: on-device roll archive and Photos writer.
- `Afterimage/Views`: home, camera ritual, developing state, and reveal viewer.

## Development Notes

The v1 pipeline intentionally keeps its decisions fixed: the full-sensor still is center-cropped to the visible square composition as soon as it is captured, then paired exposures are gently normalized and blended with stable, subtle imperfections. The processing pipeline also square-crops input defensively, keeping results square if older frame data is encountered. There is no adjustment UI and no importing path. Captures are persisted after every frame so the model is prepared for restoration work, though unfinished-roll resume UI is not yet surfaced.

The simulator compiles the complete app, but it cannot validate a real camera composition workflow. Validate square preview-to-output registration, overlay feel, focus-lock timing and release restoration, device zoom and intentional defocus gestures, photo-library permissions, thermal behavior, and full-resolution processing on device.

## Suggested Next Steps

1. Add recovery UI for a partially exposed stored roll after app termination.
2. Perform device tests across iPhone camera hardware and tune square crop registration, ghost displacement, and blend luminance.
3. Move development to a bounded background task and add cancellation-safe recovery for interrupted processing.
4. Add unit tests for roll transition invariants and deterministic rendering tests using fixture exposures.
5. Add final app icon, launch treatment, typography audit, and accessibility labels before distribution.
