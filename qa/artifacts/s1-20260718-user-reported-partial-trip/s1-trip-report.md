# S1 Trip Report

- Generated at: `2026-07-19T00:01:49.491760+00:00`
- Store: `/Users/lookasbrook/Documents/Viim-ios/qa/artifacts/s1-20260718-user-reported-partial-trip/container/Library/Application Support/Viim.sqlite`
- Trip count: `15`
- Active draft count: `0`
- Active sample count: `9`
- Quality telemetry count: `36`
- Local trips today: `2`
- Latest trip age: `0.83 h`
- Diagnostics log present: `True`
- Build identity: `{'version': '0.1.0', 'build': '13', 'gitSHA': 'local', 'builtAt': 'local'}`
- Capture sessions: `28`
- Capture sessions without outcome: `0`
- Persistent terminal outcomes: `11`

## Latest Trip

- ID: `35d27dfb-e74b-4ac2-9dd7-e501fd807d0e`
- Start: `2026-07-18T23:07:03.026993+00:00`
- End: `2026-07-18T23:12:12.999083+00:00`
- Distance: `4.191 km`
- Duration: `310 s`
- Average speed: `48.67 km/h`
- Max speed: `45.55 km/h`
- Route points: `20`
- Valid segments: `19`
- Rejected segments: `0`
- GPS accuracy avg/p95: `2.21 m / 2.48 m`
- GPS gaps max/p95: `289.03 s / 289.03 s`
- GPS temporal coverage: `0.6483` across `2` bursts
- Estimated fuel: `0.284985 L` with `vehicle-fuel-catalog-v4`
- Quality: `partial` score `65` reasons `gpsCoverageIncomplete`

## Trips

| End local | Distance | Duration | Avg | Max stored | Points | Rejected | Quality |
|---|---:|---:|---:|---:|---:|---:|---|
| 2026-07-18 19:12:12 EDT | 4.191 km | 310 s | 48.67 km/h | 45.55 km/h | 20 | 0 | partial:gpsCoverageIncomplete |
| 2026-07-18 10:34:11 EDT | 11.0125 km | 1510 s | 26.25 km/h | 104.82 km/h | 44 | 0 | partial:gpsCoverageIncomplete |
| 2026-07-17 20:29:41 EDT | 1.2774 km | 300 s | 15.33 km/h | 34.49 km/h | 12 | 0 | partial:gpsCoverageIncomplete |
| 2026-07-17 18:01:12 EDT | 4.8144 km | 310 s | 55.91 km/h | 55.83 km/h | 20 | 0 | partial:gpsCoverageIncomplete |
| 2026-07-16 18:37:09 EDT | 4.382 km | 727 s | 21.7 km/h | 57.49 km/h | 21 | 0 | partial:gpsCoverageIncomplete |
| 2026-07-16 16:59:50 EDT | 5.062 km | 311 s | 58.6 km/h | 47.39 km/h | 18 | 0 | partial:gpsCoverageIncomplete |
| 2026-07-15 21:00:34 EDT | 8.2719 km | 910 s | 32.72 km/h | 59.49 km/h | 45 | 0 | partial:gpsCoverageIncomplete |
| 2026-07-14 19:38:43 EDT | 2.0368 km | 261 s | 28.09 km/h | 47.49 km/h | 158 | 0 | reliable:complete |
| 2026-07-13 00:27:27 EDT | 0.1077 km | 102 s | 3.8 km/h | 0.76 km/h | 8 | 0 | rejected:tripTooShort |
| 2026-07-08 19:11:41 EDT | 1.9916 km | 1398 s | 5.13 km/h | 49.36 km/h | 32 | 0 | partial:gpsCoverageIncomplete |
| 2026-07-07 10:30:24 EDT | 4.3298 km | 902 s | 17.28 km/h | 28.29 km/h | 15 | 0 | partial:gpsCoverageIncomplete |
| 2026-07-06 17:34:12 EDT | 3.9144 km | 1039 s | 13.56 km/h | 50.18 km/h | 1251 | 0 | reliable:complete |
| 2026-07-06 16:37:51 EDT | 13.3822 km | 2220 s | 21.7 km/h | 90.82 km/h | 2805 | 0 | reliable:complete |
| 2026-07-06 07:22:15 EDT | 13.5224 km | 2282 s | 21.33 km/h | 186.06 km/h | 2274 | 2 | partial:impossibleSpeed |
| 2026-07-05 16:01:04 EDT | 7.9195 km | 2631 s | 10.84 km/h | 55.8 km/h | 53 | 0 | partial:gpsCoverageIncomplete |

## Recent Diagnostics

- `2026-07-18T23:27:05Z location.start active authorization=authorizedAlways`
- `2026-07-18T23:27:05Z trip.capture.start id=B9BD4E40-AE97-4305-8783-6FA642D7A888 source=location`
- `2026-07-18T23:27:05Z motion.phase movementDetected`
- `2026-07-18T23:27:13Z trip.begin samples=5 distanceMeters=72`
- `2026-07-18T23:35:45Z trip.finish.inactive distanceMeters=92 samples=6`
- `2026-07-18T23:35:45Z trip.end distanceMeters=92 samples=6`
- `2026-07-18T23:35:45Z trip.persist.skipped reason=tripTooShort`
- `2026-07-18T23:35:46Z trip.capture.outcome id=B9BD4E40-AE97-4305-8783-6FA642D7A888 status=rejected reason=tripTooShort source=live`
- `2026-07-18T23:35:46Z motion.phase waitingForMovement`
- `2026-07-18T23:35:47Z motion.phase movementDetected`
- `2026-07-18T23:35:49Z motion.phase waitingForMovement`
- `2026-07-18T23:35:51Z motion.phase movementDetected`
- `2026-07-18T23:35:51Z motion.phase waitingForMovement`
- `2026-07-18T23:35:53Z motion.phase movementDetected`
- `2026-07-18T23:35:53Z motion.phase waitingForMovement`
- `2026-07-18T23:51:52Z location.idleFailsafe.stop phase=idle`
- `2026-07-18T23:51:52Z location.stop phase=idle`
- `2026-07-18T23:51:52Z location.backgroundSession.end`
- `2026-07-18T23:51:53Z location.passiveWakeup.ignored count=1`
- `2026-07-18T23:51:53Z location.passiveWakeup.ignored count=1`
- `2026-07-18T23:51:53Z motion.phase movementDetected`
- `2026-07-18T23:51:53Z motion.triggerLocationMonitoring`
- `2026-07-18T23:51:53Z location.backgroundSession.start authorization=authorizedAlways`
- `2026-07-18T23:51:53Z location.start active authorization=authorizedAlways`
- `2026-07-18T23:51:53Z motion.phase waitingForMovement`
- `2026-07-18T23:51:54Z motion.phase movementDetected`
- `2026-07-18T23:51:55Z motion.phase waitingForMovement`
- `2026-07-18T23:51:55Z motion.phase movementDetected`
- `2026-07-18T23:51:56Z motion.phase waitingForMovement`
- `2026-07-18T23:51:57Z motion.phase movementDetected`
- `2026-07-18T23:52:03Z motion.phase waitingForMovement`
- `2026-07-18T23:52:03Z motion.phase movementDetected`
- `2026-07-18T23:52:05Z motion.phase waitingForMovement`
- `2026-07-18T23:52:06Z motion.phase movementDetected`
- `2026-07-18T23:52:06Z motion.phase waitingForMovement`
- `2026-07-18T23:52:07Z motion.phase movementDetected`
- `2026-07-18T23:52:13Z motion.phase waitingForMovement`
- `2026-07-18T23:52:15Z motion.phase movementDetected`
- `2026-07-18T23:52:17Z motion.phase waitingForMovement`
- `2026-07-18T23:52:19Z motion.phase movementDetected`
- `2026-07-18T23:52:19Z motion.phase waitingForMovement`
- `2026-07-18T23:52:21Z motion.phase movementDetected`
- `2026-07-18T23:52:22Z motion.phase waitingForMovement`
- `2026-07-18T23:52:24Z motion.phase movementDetected`
- `2026-07-18T23:52:31Z motion.phase waitingForMovement`
- `2026-07-18T23:52:35Z motion.phase stationary`
- `2026-07-18T23:52:35Z motion.stationaryStop.deferred reason=armingOrMovement`
- `2026-07-18T23:54:53Z location.idleFailsafe.stop phase=idle`
- `2026-07-18T23:54:53Z location.stop phase=idle`
- `2026-07-18T23:54:53Z location.backgroundSession.end`
- `2026-07-18T23:58:16Z motion.phase movementDetected`
- `2026-07-18T23:58:16Z motion.triggerLocationMonitoring`
- `2026-07-18T23:58:16Z location.backgroundSession.start authorization=authorizedAlways`
- `2026-07-18T23:58:16Z location.start active authorization=authorizedAlways`
- `2026-07-18T23:58:19Z motion.phase waitingForMovement`
- `2026-07-18T23:58:19Z motion.phase movementDetected`
- `2026-07-18T23:58:32Z motion.phase waitingForMovement`
- `2026-07-18T23:58:32Z motion.phase movementDetected`
- `2026-07-18T23:58:35Z motion.phase waitingForMovement`
- `2026-07-18T23:58:35Z motion.phase movementDetected`
- `2026-07-18T23:58:36Z motion.phase waitingForMovement`
- `2026-07-18T23:58:36Z motion.phase movementDetected`
- `2026-07-18T23:58:37Z motion.phase waitingForMovement`
- `2026-07-18T23:58:37Z motion.phase movementDetected`
- `2026-07-18T23:58:39Z motion.phase waitingForMovement`
- `2026-07-18T23:58:43Z motion.phase stationary`
- `2026-07-18T23:58:43Z motion.stationaryStop.deferred reason=armingOrMovement`
- `2026-07-18T23:59:11Z motion.phase movementDetected`
- `2026-07-18T23:59:11Z motion.phase waitingForMovement`
- `2026-07-18T23:59:15Z motion.phase stationary`
- `2026-07-18T23:59:15Z motion.stationaryStop.deferred reason=armingOrMovement`
- `2026-07-19T00:00:51Z motion.phase movementDetected`
- `2026-07-19T00:00:54Z motion.phase waitingForMovement`
- `2026-07-19T00:00:57Z motion.phase movementDetected`
- `2026-07-19T00:01:05Z motion.phase waitingForMovement`
- `2026-07-19T00:01:11Z motion.phase stationary`
- `2026-07-19T00:01:11Z motion.stationaryStop.deferred reason=armingOrMovement`
- `2026-07-19T00:01:17Z location.idleFailsafe.stop phase=idle`
- `2026-07-19T00:01:17Z location.stop phase=idle`
- `2026-07-19T00:01:17Z location.backgroundSession.end`

## Route Bounds

- First point: `{'timestamp': 806108823.026993, 'latitude': 46.83304469119904, 'longitude': -71.23118718620843, 'speedKmh': 44.287833891056835, 'horizontalAccuracy': 2.312123085418643, 'speedAccuracy': 0.9289891212669391}`
- Last point: `{'timestamp': 806109423.036459, 'latitude': 46.86704871598513, 'longitude': -71.21677983739838, 'speedKmh': 0.7843842619122461, 'horizontalAccuracy': 2.19051847342683, 'speedAccuracy': 0.30751569995960426}`
