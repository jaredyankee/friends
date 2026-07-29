import { Tabs } from 'expo-router';

/**
 * The four modes. Exactly four — see CLAUDE.md. Resist adding a fifth.
 *
 * No icons yet: @expo/vector-icons conflicts with the pinned React version in
 * this SDK, and tab iconography is a T7 concern. Titles carry navigation for now.
 */
export default function TabsLayout() {
  return (
    <Tabs screenOptions={{ headerShown: true }}>
      <Tabs.Screen name="calendar/index" options={{ title: 'Calendar' }} />
      <Tabs.Screen name="form/index" options={{ title: 'Form' }} />
      <Tabs.Screen name="chat/index" options={{ title: 'Chat' }} />
      <Tabs.Screen name="account/index" options={{ title: 'Account' }} />
    </Tabs>
  );
}
