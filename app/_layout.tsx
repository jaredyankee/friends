import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';

/**
 * Root layout. Auth and the tab bar are siblings so that signing out can swap
 * the whole tree rather than unwinding a nested stack.
 *
 * Session gating lands in A1.3 — today both groups are reachable.
 */
export default function RootLayout() {
  return (
    <>
      <Stack screenOptions={{ headerShown: false }}>
        <Stack.Screen name="(tabs)" />
        <Stack.Screen name="(auth)" />
      </Stack>
      <StatusBar style="auto" />
    </>
  );
}
