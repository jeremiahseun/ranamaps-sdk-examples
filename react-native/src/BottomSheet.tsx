import React, {
  forwardRef,
  useEffect,
  useImperativeHandle,
  useMemo,
  useRef,
} from "react";
import {
  Animated,
  PanResponder,
  ScrollView,
  StyleSheet,
  View,
} from "react-native";

export interface BottomSheetHandle {
  snapTo(index: number): void;
}

interface Props {
  /** Visible heights in px, ascending. */
  snaps: readonly [number, number, number];
  initialIndex?: number;
  /** Called with the visible height on every change while dragging/animating. */
  onHeight: (height: number) => void;
  children: React.ReactNode;
}

export const BottomSheet = forwardRef<BottomSheetHandle, Props>(
  function BottomSheet({ snaps, initialIndex = 1, onHeight, children }, ref) {
    const height = useRef(new Animated.Value(snaps[initialIndex])).current;
    const current = useRef(snaps[initialIndex]);
    const start = useRef(current.current);
    const snapsRef = useRef(snaps);
    snapsRef.current = snaps;
    const report = useRef(onHeight);
    report.current = onHeight;

    useEffect(() => {
      const id = height.addListener(({ value }) => {
        current.current = value;
        report.current(value);
      });
      report.current(current.current);
      return () => height.removeListener(id);
    }, [height]);

    const animate = (to: number) =>
      Animated.spring(height, {
        toValue: to,
        bounciness: 0,
        speed: 14,
        useNativeDriver: false,
      }).start();

    useImperativeHandle(ref, () => ({
      snapTo: (index) => animate(snapsRef.current[index]),
    }));

    // Keep the sheet on a snap point if the window size (and so the snaps) changes.
    useEffect(() => {
      const nearest = nearestSnap(snaps, current.current);
      animate(snaps[nearest]);
      // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [snaps[0], snaps[1], snaps[2]]);

    const responder = useMemo(
      () =>
        PanResponder.create({
          onStartShouldSetPanResponder: () => true,
          onPanResponderGrant: () => {
            height.stopAnimation();
            start.current = current.current;
          },
          onPanResponderMove: (_, g) => {
            const [min, , max] = snapsRef.current;
            height.setValue(Math.min(max, Math.max(min, start.current - g.dy)));
          },
          onPanResponderRelease: (_, g) => {
            // Dragging up (negative vy) increases height; project a little ahead.
            const projected = current.current - g.vy * 180;
            const target =
              snapsRef.current[nearestSnap(snapsRef.current, projected)];
            animate(target);
          },
        }),
      // eslint-disable-next-line react-hooks/exhaustive-deps
      [height],
    );

    return (
      <Animated.View style={[styles.sheet, { height }]}>
        <View
          {...responder.panHandlers}
          style={styles.grabber}
          accessible
          accessibilityRole="adjustable"
          accessibilityLabel="Resize sheet"
        >
          <View style={styles.pill} />
        </View>
        <ScrollView
          keyboardShouldPersistTaps="handled"
          contentContainerStyle={styles.content}
        >
          {children}
        </ScrollView>
      </Animated.View>
    );
  },
);

function nearestSnap(snaps: readonly number[], value: number) {
  let best = 0;
  snaps.forEach((s, i) => {
    if (Math.abs(s - value) < Math.abs(snaps[best] - value)) best = i;
  });
  return best;
}

const styles = StyleSheet.create({
  sheet: {
    position: "absolute",
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: "#fff",
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    elevation: 12,
    shadowColor: "#000",
    shadowOpacity: 0.18,
    shadowRadius: 10,
    shadowOffset: { width: 0, height: -2 },
    overflow: "hidden",
  },
  grabber: { height: 28, alignItems: "center", justifyContent: "center" },
  pill: { width: 40, height: 5, borderRadius: 3, backgroundColor: "#c9ccd1" },
  content: { paddingHorizontal: 16, paddingBottom: 32 },
});
