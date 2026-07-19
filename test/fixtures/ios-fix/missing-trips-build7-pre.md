# Missing trips build 7 pre-fix snapshot

The bug is a background lifecycle and persistence failure, not a visual layout
failure. This fixture therefore comes from a fresh read-only extraction of the
physical iPhone's Core Data store and `ViimDiagnostics.log`; the project has no
DebugBridge/StateServer endpoint capable of producing `GET /state/snapshot` or a
restorable UI screenshot.

Observed failure: precise 9-10 second driving bursts covering 91-133 metres were
journaled, then rejected as `armingTimeout` at the next approximately five-minute
location wake. Only one trip appeared for the day.

Expected behavior: suspension must never erase a candidate, reliable short bursts
must establish movement, invalid speed accuracy must not start a trip, and sparse
routes must not be classified as 100% reliable.
