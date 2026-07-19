# Missing trips build 8 pre-fix snapshot

This fixture is a fresh, read-only extraction of the connected physical iPhone's
Core Data store and `ViimDiagnostics.log`.

Observed failure: Core Location delivered background fixes in bursts separated by
about 290 seconds. A capture that remained open for roughly 12 minutes accumulated
2,514 metres of raw movement, but it was deleted as `tripTooShort` because the app
used the ten-second GPS timestamp span as the whole trip duration. The following
capture remained active after more than six minutes of zero-speed GPS because
noisy Core Motion movement callbacks repeatedly cancelled stationary finalization.
Rejected captures also lost their samples, preventing later repair or audit.

Expected behavior: the app must retain the background location activity required
for automatic tracking, distinguish receipt time from GPS event time, reject
physically impossible jumps, let sustained GPS stationarity win over noisy motion,
finalize recovered drafts deterministically, and retain terminal capture evidence.
