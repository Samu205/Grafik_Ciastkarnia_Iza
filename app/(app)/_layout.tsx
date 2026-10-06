import { Redirect, Tabs } from 'expo-router';
import { Text, type ColorValue } from 'react-native';

import { Button, Loading, Muted, Screen, Title } from '@/components/ui';
import { colors } from '@/constants/theme';
import { useAuth } from '@/lib/auth';

function TabIcon({ symbol, color }: { symbol: string; color: ColorValue }) {
  return <Text style={{ color, fontSize: 18 }}>{symbol}</Text>;
}

/** Część aplikacji dostępna tylko dla zalogowanych, aktywnych pracowników. */
export default function AppLayout() {
  const { loading, session, employee, signOut } = useAuth();

  if (loading) {
    return <Loading />;
  }
  if (!session) {
    return <Redirect href="/login" />;
  }
  if (!employee) {
    return (
      <Screen>
        <Title>Konto nie jest jeszcze aktywne</Title>
        <Muted>
          Zalogowano jako {session.user.email}, ale to konto nie jest jeszcze dodane do listy
          pracowników. Poproś Izę o dodanie Cię do aplikacji.
        </Muted>
        <Button title="Wyloguj" variant="secondary" onPress={() => void signOut()} />
      </Screen>
    );
  }

  return (
    <Tabs
      screenOptions={{
        tabBarActiveTintColor: colors.primary,
        tabBarInactiveTintColor: colors.textMuted,
        headerTintColor: colors.text,
        headerStyle: { backgroundColor: colors.surface },
      }}
    >
      <Tabs.Screen
        name="index"
        options={{
          title: 'Moje zmiany',
          tabBarIcon: ({ color }) => <TabIcon symbol="🗓" color={color} />,
        }}
      />
      <Tabs.Screen
        name="powiadomienia"
        options={{
          title: 'Powiadomienia',
          tabBarIcon: ({ color }) => <TabIcon symbol="🔔" color={color} />,
        }}
      />
      <Tabs.Screen
        name="konto"
        options={{
          title: 'Konto',
          tabBarIcon: ({ color }) => <TabIcon symbol="👤" color={color} />,
        }}
      />
    </Tabs>
  );
}
