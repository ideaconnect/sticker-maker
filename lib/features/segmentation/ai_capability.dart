import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/platform_services.dart';

/// Whether this device may run the heavy AI tiers, plus a short
/// human-readable reason when it may not (diagnostics / debug UI).
typedef AiCapability = ({bool samAllowed, String? reason});

/// The SAM encoder's transient working set (session + arena + a full-res
/// decode of the source photo) is what pushes 2 GB-class devices into a
/// low-memory kill, so the tier needs real headroom: not an
/// `isLowRamDevice`, and at least this much total RAM.
const int samMinTotalMemBytes = 3 * 1024 * 1024 * 1024; // 3 GiB

/// Device capability for the MobileSAM object-removal tier, probed ONCE per
/// app run (review 2026-07-19: every engine's isAvailable() is an asset
/// check, so nothing stopped the encoder from being offered to devices it
/// would kill).
///
/// Deny only on a *positive* signal that the device is too small
/// (`isLowRamDevice`, or total RAM under [samMinTotalMemBytes]). When the
/// platform can't answer at all — an APK predating `getMemoryInfo`, tests,
/// a non-Android host — default to ALLOWED so no device that works today
/// regresses.
///
/// A `FutureProvider` so the probe is memoized for the app run and trivially
/// overridable in tests (`aiCapabilityProvider.overrideWith(...)`).
final aiCapabilityProvider = FutureProvider<AiCapability>((ref) async {
  final info = await ref.watch(platformServicesProvider).memoryInfo();
  if (info == null) {
    return (samAllowed: true, reason: null);
  }
  if (info.lowRam) {
    return (samAllowed: false, reason: 'Android reports a low-RAM device');
  }
  if (info.totalMem < samMinTotalMemBytes) {
    final gib = (info.totalMem / (1024 * 1024 * 1024)).toStringAsFixed(1);
    return (samAllowed: false, reason: 'only $gib GiB RAM (needs 3 GiB)');
  }
  return (samAllowed: true, reason: null);
});
