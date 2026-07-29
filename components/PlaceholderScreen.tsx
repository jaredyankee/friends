import { StyleSheet, Text, View, useColorScheme } from 'react-native';

interface PlaceholderScreenProps {
  title: string;
  description: string;
  /** Roadmap reference, so a stub says when it stops being a stub. */
  landsIn: string;
}

/**
 * Temporary scaffold screen. Deleted as each mode gets built.
 *
 * Colors are inline here deliberately — this component does not survive to v1,
 * and the theme system it would otherwise use does not exist yet (T7.3). Real
 * screens must take color from theme tokens; a literal in a shipped component
 * is a bug, because it ignores the user's palette and light/dark setting.
 */
export function PlaceholderScreen({ title, description, landsIn }: PlaceholderScreenProps) {
  const isDark = useColorScheme() === 'dark';

  return (
    <View style={[styles.container, isDark ? styles.containerDark : styles.containerLight]}>
      <Text style={[styles.title, isDark ? styles.textDark : styles.textLight]}>{title}</Text>
      <Text style={[styles.body, isDark ? styles.mutedDark : styles.mutedLight]}>
        {description}
      </Text>
      <Text style={[styles.meta, isDark ? styles.mutedDark : styles.mutedLight]}>{landsIn}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { alignItems: 'center', flex: 1, gap: 8, justifyContent: 'center', padding: 24 },
  containerDark: { backgroundColor: '#101014' },
  containerLight: { backgroundColor: '#ffffff' },
  title: { fontSize: 24, fontWeight: '600' },
  body: { fontSize: 15, lineHeight: 22, textAlign: 'center' },
  meta: { fontSize: 13, marginTop: 8 },
  textDark: { color: '#f2f2f5' },
  textLight: { color: '#16161a' },
  mutedDark: { color: '#9a9aa6' },
  mutedLight: { color: '#6b6b76' },
});
