# Piano Practice (provisional name)

A native SwiftUI iPhone app that listens to an acoustic piano through the iPhone microphone. It shows the next key, waits for a fresh strike of the correct note (octave included), shows a hold cue for the note's length, and works through the melody. You don't need a cable, pedal, network or account.

**Day 1 scope:** Mic Check, single-note wait practice, two lessons (Key Check and Ode to Joy), the hold cue, a Touch Demo, and noise and tuning calibration. The app makes no sound while listening, and nothing is recorded or sent anywhere.

---

## Repository layout

```
project.yml                 XcodeGen spec (source of truth; .xcodeproj is generated, not committed)
PianoCore/                  Swift package: all logic that doesn't need UIKit/AVFoundation
  Sources/PianoCore/
    YINPitchEstimator.swift   YIN: difference fn → CMND → first credible min → parabolic interp
    OnsetDetector.swift       energy envelope, adaptive floor, hysteresis/rearm, unique onset IDs
    NoteEventTracker.swift    pairs each onset with a pitch that stabilizes in a bounded window
    AnalysisPipeline.swift    mono samples → 2048-sample windows / 512-sample hops → frames
    LessonEngine.swift        wait-mode state machine (injectable time)
    KeyboardGeometry.swift    one geometry model for keys and falling bars
    Calibration.swift         quiet-room noise floor + explicit play-A4 tuning
    Lesson.swift, Resources/lessons.json
  Tests/PianoCoreTests/       synthetic-signal and state tests (44.1 kHz and 48 kHz)
PianoPractice/              iOS app
  Audio/AudioInputController.swift   AVAudioSession/.measurement, engine, tap, bounded queue
  Audio/ListeningSession.swift       main-actor view model over the microphone
  Practice/                          practice screen, falling bars, keyboard, hold cue
  Views/                             Mic Check, Calibration, lesson list
PianoPracticeTests/         app tests (Touch Demo drives the real lesson logic)
.github/workflows/ios-ci.yml  macOS CI: unsigned simulator build + all tests
codemagic.yaml              ios-tests (unsigned) and ios-testflight (signed → TestFlight)
scripts/                    pinned tooling (tooling.env), CI script, bundle-ID check
```

**Bundle ID:** `com.cesarperez.pianopractice` (registered). **App Store Connect app:** "Piano Practice: Mic Trainer", Apple ID `6833136786` (the plain name was taken; the home-screen name is still *Piano Practice*). **TestFlight:** internal group "Day 1" with automatic distribution, tester Cesar Perez. It appears in `project.yml` and twice in `codemagic.yaml`. If you change it, change all three places; `scripts/check-bundle-id.sh` fails CI if they ever differ.

**Pinned tooling:** XcodeGen 2.45.4 and Xcode 26.5, both set in `scripts/tooling.env`. Apple requires Xcode 26 or later for App Store Connect uploads.

---

## Working from Windows

You don't need a Mac. Push to GitHub, and the **iOS CI** workflow (on a `macos-26` runner) does the following:

1. runs `swift test` on PianoCore (pitch, onset, pipeline, lesson engine, geometry, calibration)
2. generates the Xcode project with the pinned XcodeGen
3. builds the app for an iPhone simulator, without signing
4. runs the app tests (Touch Demo wiring)

If a run fails, the logs and the `.xcresult` are attached as the `ios-ci-results` artifact. A simulator pass only shows that the wiring and game flow work. It does not show that the microphone works.

On a Mac: `brew install xcodegen && xcodegen generate && open PianoPractice.xcodeproj`.

---

## Ship to your iPhone 14 (internal TestFlight)

You do this once. Nothing is submitted to the public App Store.

1. **Register the bundle ID.** In [developer.apple.com](https://developer.apple.com/account/resources/identifiers/list), go to Identifiers, click +, choose App IDs, then App. Enter `com.cesarperez.pianopractice` (explicit, not wildcard). No extra capabilities are needed.
2. **Create the app record.** In [App Store Connect](https://appstoreconnect.apple.com/apps), go to Apps, click +, then New App. Choose iOS, name it *Piano Practice* (provisional; the name must be unique, so add a suffix if it's taken), and select the bundle ID from step 1. Any SKU works, for example `piano-practice`. Then open **App Information** and copy the **Apple ID**, which is a 10-digit number.
3. **Create an API key.** In App Store Connect, go to Users and Access, then Integrations, then App Store Connect API, and generate a Team Key with **App Manager** access. Download the `.p8` (you can only download it once) and note the Issuer ID and Key ID.
4. **Connect Codemagic.** Add the repo to Codemagic. Then go to Team settings, Integrations, Developer Portal, and click Manage keys to add the key. Name it exactly **`PianoPractice ASC Key`**, or change `integrations.app_store_connect` in `codemagic.yaml` to match your name. Under Code signing identities, either let Codemagic generate an **Apple Distribution** certificate or upload your own `.p12`. The `ios_signing` block then fetches or creates the App Store profile automatically.
5. **Set the Apple ID.** In `codemagic.yaml`, replace `APP_STORE_APPLE_ID: "0000000000"` with the number from step 2, then commit.
6. **Run it.** In Codemagic, click Start new build and pick the `ios-testflight` workflow. The steps are named so you can tell what failed:
   - *Install pinned XcodeGen and generate the project*: a project or spec problem
   - *Signing 1/2* or *2/2*: a certificate, profile or API-key problem
   - *Set build number*: the API key can't read TestFlight builds
   - *Build signed IPA*: a compile or archive problem

   The first upload is build **1**. Each later run uses the latest TestFlight build + 1.
7. **Wait for processing.** It usually takes 5–30 minutes; App Store Connect emails you when it's done. The IPA is marked internal-only, so it can't be sent to external testers or the App Store.
8. **Create an internal group.** In App Store Connect, open the app, go to TestFlight, and next to Internal Testing click + to create a group (for example "Day 1"). Add yourself; you must be a user on the team. Then add the processed build to the group. You can turn on automatic distribution so future builds go to the group without this step.
9. **Install.** On the iPhone 14, install **TestFlight** from the App Store, sign in with the same Apple ID, accept the invite, and tap Install.

To run the unsigned checks on Codemagic as well, use the `ios-tests` workflow. It needs no credentials.

---

## On-device acceptance test (iPhone 14 + acoustic piano)

Set up: phone on the music stand, microphone openings clear, room quiet, sustain pedal **up**.

1. **Mic Check.** Tap Start Listening and allow the microphone. If the room is quiet, run Calibration, then *Calibrate in a quiet room*. Play C4 (the white key just left of the pair of black keys nearest the middle), then D4, E4, F4 and G4, and check that each one reads correctly.
2. **Five clean strikes per key**, mixing normal and soft playing. Note any wrong name or octave, and any key that needed several tries. The target is at least 23/25, with the strike indicator and note responding in about 250 ms. The "ms after strike" readout shows the detector's own latency.
3. **Key Check, wrong notes.** While the app waits for C4, play a neighboring key five times, then C3 and C5. The target must not move. The debug panel shows `wrong note` or `wrong octave`. Then wait five silent seconds; nothing should change.
4. **Repeated E4.** Strike once and let it ring. The second E4 must still wait (the debug panel shows `strike began before this target was armed` if a late report arrives). Strike again once the hold cue ends, and it advances once. Use the final C4 to check the 2-beat cue.
5. **Ode to Joy** twice, once softly. Stop and restart listening. If a note misses, write down the expected and heard note, level, confidence, and whether the previous note was still ringing; all of these are in the debug panel. To test permission recovery, deny the microphone in Settings, then check that the denied screen's *Open Settings* button gets you back.

**If your piano is noticeably out of tune**, use Calibration, then *Calibrate by playing A4*. It only accepts a confident A4 within 50¢ of 440 Hz, and it never changes tuning during a lesson.

---

## How a strike becomes progress

```
mic → tap (copy frameLength samples, bounded queue) → serial analysis queue
    → per 512-sample hop:  level ─▶ OnsetDetector ─▶ onset #id
                           window ─▶ YIN ─▶ raw estimate (Hz, confidence)
    → NoteEventTracker: after onset #id, skip 2 hops, need 3 consecutive confident estimates
      within 30¢ of each other, within 200 ms, and within ±40¢ of a MIDI note → NoteEvent(#id, midi)
    → main actor → LessonEngine.handle:
         onset #id already used?              → ignored
         onset began before target was armed? → ignored (decaying previous note)
         midi ≠ target (octave included)?     → "wrong note", target stays
         else                                 → hold cue for score duration, then arm next target
```

- The detector never sees the target note. Pitch is estimated independently, and the matcher compares exact MIDI numbers.
- The hold cue is a visual timer on a monotonic clock. The app does not measure or grade how long you held the key, because the mic can't tell a lifted key from a ringing string.
- Repeated notes need a new energy rise after the previous attack has peaked. There is only an 80 ms guard against double triggers, not a long debounce.
- The tap is removed and the session released when you leave a practice or Mic Check screen, when the app goes to the background, or when you switch to Touch Demo. Interruptions, route changes and media-service resets stop listening, drop any queued results from the old session, and show **Restart Listening**.

### Tuning knobs (adjust from on-device measurements)

| Where | Setting | Default |
|---|---|---|
| `YINConfiguration` | search range / threshold | 120–900 Hz / 0.15 |
| `TrackerConfiguration` | min confidence / stable frames / spread / cents tolerance / window | 0.80 / 3 / 30¢ / ±40¢ / 200 ms |
| `OnsetConfiguration` | min level / above floor / rise / rearm | −58 dBFS / 12 dB / 6 dB in 3 hops / peak −1 dB ×3 hops or −4 dB |

`tools/dsp_reference.py` is a numpy copy of the same detector, so you can try parameter changes on Windows. These defaults were checked against synthetic piano-like tones (harmonics, inharmonicity, decay, three-string beating, noise) at 44.1 and 48 kHz. Real-piano numbers come from the acceptance test above.

---

## Release notes and next steps

- This is an internal build only. Choose the final name and pricing after the microphone passes on a real piano.
- Next milestones: timed rhythm scoring, two-hand and chord recognition, sustain-pedal-aware behavior, song import.
- Content: original exercises, plus public-domain melodies entered independently. The Ode to Joy excerpt is Beethoven's melody line only. Track composition, arrangement and recording provenance before adding any commercial catalog. No third-party branding or arrangements are included.
