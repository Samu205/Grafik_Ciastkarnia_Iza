import { Link } from 'expo-router';
import { StyleSheet, Text } from 'react-native';

import { Muted, Screen, Title } from '@/components/ui';
import { colors } from '@/constants/theme';

export default function NotFoundScreen() {
  return (
    <Screen>
      <Title>Nie ma takiej strony</Title>
      <Muted>Ten adres nie istnieje w aplikacji.</Muted>
      <Link href="/">
        <Text style={styles.link}>Wróć do moich zmian</Text>
      </Link>
    </Screen>
  );
}

const styles = StyleSheet.create({
  link: { color: colors.primary, fontSize: 16, fontWeight: '600' },
});
