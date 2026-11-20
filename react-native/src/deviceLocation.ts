import { PermissionsAndroid, Platform } from "react-native";
import type { LatLng } from "@ranamaps/maps-react-native";

/** Fallback point used when location permission is denied (Lagos Island). */
export const LAGOS: LatLng = { latitude: 6.5244, longitude: 3.3792 };

/**
 * Foreground location permission. Android uses the RN runtime request (manifest entries come from the app.json
 * plugin options). On iOS the SDK's native provider asks for when-in-use permission itself when it is undecided
 * (the usage string comes from the same plugin options); a refusal arrives as a `permission_denied` map error.
 */
export async function requestLocationPermission(): Promise<boolean> {
  if (Platform.OS !== "android") return true;
  const { ACCESS_FINE_LOCATION: fine, ACCESS_COARSE_LOCATION: coarse } =
    PermissionsAndroid.PERMISSIONS;
  const result = await PermissionsAndroid.requestMultiple([fine, coarse]);
  return (
    result[fine] === PermissionsAndroid.RESULTS.GRANTED ||
    result[coarse] === PermissionsAndroid.RESULTS.GRANTED
  );
}
