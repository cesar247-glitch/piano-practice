// Re-export the core so `@testable import PianoPractice` also exposes PianoCore types to the
// app's unit tests without linking the package into the test bundle a second time.
@_exported import PianoCore
