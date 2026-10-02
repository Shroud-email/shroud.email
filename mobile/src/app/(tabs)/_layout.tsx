import { Tabs } from 'expo-router';
import { EnvelopeSimpleIcon, GearSixIcon } from 'phosphor-react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '@/hooks/use-theme';

export default function TabsLayout() {
  const c = useTheme();
  const insets = useSafeAreaInsets();
  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: c.accent,
        tabBarInactiveTintColor: c.textSecondary,
        tabBarStyle: {
          backgroundColor: c.background,
          borderTopColor: c.border,
          height: 60 + insets.bottom,
        },
        tabBarLabelPosition: 'below-icon',
        tabBarLabelStyle: {
          fontFamily: 'Manrope_600SemiBold',
          fontSize: 12,
          lineHeight: 16,
        },
        tabBarItemStyle: { paddingVertical: 4 },
        sceneStyle: { backgroundColor: c.background },
      }}
    >
      <Tabs.Screen
        name="index"
        options={{
          title: 'Aliases',
          tabBarIcon: ({ focused }) => (
            <EnvelopeSimpleIcon
              size={23}
              color={focused ? c.accent : c.textSecondary}
            />
          ),
        }}
      />
      <Tabs.Screen
        name="settings"
        options={{
          title: 'Settings',
          tabBarIcon: ({ focused }) => (
            <GearSixIcon
              size={23}
              color={focused ? c.accent : c.textSecondary}
            />
          ),
        }}
      />
    </Tabs>
  );
}
