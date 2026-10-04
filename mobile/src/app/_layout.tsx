import '@/global.css';

import { DarkTheme, DefaultTheme, Stack, ThemeProvider } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { StatusBar } from 'expo-status-bar';
import {
  useFonts,
  Manrope_400Regular,
  Manrope_500Medium,
  Manrope_600SemiBold,
  Manrope_700Bold,
} from '@expo-google-fonts/manrope';
import { useEffect } from 'react';

import { AppProvider, useApp } from '@/providers/app-provider';
import { AuthStubProvider, useAuth } from '@/providers/auth-stub';
import { Button, Screen, Header } from '@/components/ui';
import { ThemedText } from '@/components/themed-text';
import { useTheme } from '@/hooks/use-theme';

SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  const [loaded, error] = useFonts({
    Manrope_400Regular,
    Manrope_500Medium,
    Manrope_600SemiBold,
    Manrope_700Bold,
  });
  useEffect(() => {
    if (error) console.error('Could not load Manrope fonts.', error);
    if (loaded || error) SplashScreen.hideAsync();
  }, [loaded, error]);
  if (!loaded && !error) return null;
  return (
    <AuthStubProvider>
      <AppProvider>
        <Navigation />
      </AppProvider>
    </AuthStubProvider>
  );
}

function Navigation() {
  const { scheme } = useApp();
  const { session, startPreview } = useAuth();
  const colors = useTheme();
  const base = scheme === 'dark' ? DarkTheme : DefaultTheme;
  return (
    <ThemeProvider
      value={{
        ...base,
        colors: {
          ...base.colors,
          background: colors.background,
          card: colors.background,
          text: colors.text,
          primary: colors.primary,
          border: colors.border,
        },
      }}
    >
      <StatusBar style={scheme === 'dark' ? 'light' : 'dark'} />
      {session ? (
        <Stack
          screenOptions={{
            headerShown: false,
            contentStyle: { backgroundColor: colors.background },
          }}
        >
          <Stack.Screen name="(tabs)" />
          <Stack.Screen name="create" />
          <Stack.Screen name="aliases/[id]" />
        </Stack>
      ) : (
        <Screen>
          <Header title="Authentication stub" />
          <ThemedText style={{ marginBottom: 24 }}>
            You’re signed out of the UI preview. OAuth will be connected
            separately.
          </ThemedText>
          <Button label="Restart UI preview" onPress={startPreview} />
        </Screen>
      )}
    </ThemeProvider>
  );
}
