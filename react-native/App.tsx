import React, { useEffect, useState } from "react";
import { SafeAreaView, Text } from "react-native";
import { createClient } from "@ranamaps/maps-react-native";
import MapsApp from "./src/MapsApp";

export default function App() {
  if (process.env.EXPO_PUBLIC_RANA_SMOKE === "1") return <NativeBridgeCheck />;
  return <MapsApp />;
}

function NativeBridgeCheck() {
  const [status, setStatus] = useState("Checking native bridge");
  useEffect(() => {
    let active = true;
    const run = async () => {
      const client = await createClient(
        "pk_live_fixture",
        async (request, signal) => {
          if (request.headers["X-Rana-Key"] !== "pk_live_fixture")
            throw Error("Missing native key header");
          if (
            !request.headers["X-Rana-Ios-Bundle"] &&
            !request.headers["X-Rana-Android-Package"]
          )
            throw Error("Missing native identity");
          return {
            status: 200,
            headers: { "rana-request-id": "fixture" },
            body: '{"results":[{"label":"Lagos","point":{"lat":6.5,"lng":3.4},"kind":"city","place_id":"fixture"}]}',
          };
        },
      );
      try {
        const results = await client.geocode({ query: "Lagos" });
        if (
          results[0].point.latitude !== 6.5 ||
          results[0].point.longitude !== 3.4
        )
          throw Error("Coordinate conversion failed");
        await client.dispose();
        let refused = false;
        try {
          await client.geocode({ query: "Lagos" });
        } catch (error) {
          refused = (error as { code?: string }).code === "stale_handle";
        }
        if (!refused) throw Error("Disposed handle accepted");
        if (active) setStatus("Native bridge passed");
        console.log("RANA_NATIVE_SMOKE_PASS");
      } finally {
        await client.dispose();
      }
    };
    void run().catch((error) => {
      if (active) setStatus(String(error));
      console.error("RANA_NATIVE_SMOKE_FAIL", error);
    });
    return () => {
      active = false;
    };
  }, []);
  return (
    <SafeAreaView>
      <Text testID="native-smoke-result">{status}</Text>
    </SafeAreaView>
  );
}
