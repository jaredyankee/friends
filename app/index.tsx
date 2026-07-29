import { Redirect } from 'expo-router';

/** Calendar is the app's home. A1.3 will send signed-out users to (auth) instead. */
export default function Index() {
  return <Redirect href="/calendar" />;
}
