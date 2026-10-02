import { View } from 'react-native';
import { Button, Header, Screen, Section, row } from '@/components/ui';
import { ThemedText } from '@/components/themed-text';
import { useApp, type Appearance } from '@/providers/app-provider';
import { useAuth } from '@/providers/auth-stub';

export default function SettingsScreen() {
  const { appearance, setAppearance, preferenceError } = useApp();
  const { session, logOut } = useAuth();
  return (
    <Screen>
      <Header title="Settings" />
      <Section>
        <ThemedText themeColor="textSecondary" type="small">
          Signed in as
        </ThemedText>
        <ThemedText>{session?.email}</ThemedText>
      </Section>
      <Section>
        <ThemedText type="subtitle">Appearance</ThemedText>
        <View
          accessibilityRole="radiogroup"
          accessibilityLabel="Appearance"
          style={[row, { gap: 4 }]}
        >
          {(['system', 'light', 'dark'] as Appearance[]).map((value) => (
            <View key={value} style={{ flex: 1 }}>
              <Button
                label={`${value[0].toUpperCase()}${value.slice(1)}`}
                accessibilityRole="radio"
                kind={appearance === value ? 'primary' : 'outline'}
                selected={appearance === value}
                onPress={() => setAppearance(value)}
              />
            </View>
          ))}
        </View>
        <ThemedText type="small" themeColor="textMuted">
          {appearance === 'system'
            ? 'Matches your device’s appearance.'
            : `Always use ${appearance} mode.`}
        </ThemedText>
        {preferenceError && (
          <ThemedText accessibilityRole="alert" themeColor="danger">
            {preferenceError}
          </ThemedText>
        )}
      </Section>
      <View style={{ marginTop: 24 }}>
        <Button label="Log out" kind="danger" onPress={logOut} />
      </View>
    </Screen>
  );
}
