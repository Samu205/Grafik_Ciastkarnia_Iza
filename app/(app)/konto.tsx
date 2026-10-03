import { StyleSheet, Text } from 'react-native';

import { Button, Card, Screen, Title } from '@/components/ui';
import { colors } from '@/constants/theme';
import { useAuth } from '@/lib/auth';
import { DEPARTMENT_LABELS, ROLE_LABELS } from '@/lib/labels';

export default function AccountScreen() {
  const { employee, session, signOut } = useAuth();

  if (!employee) {
    return null;
  }

  return (
    <Screen>
      <Title>{employee.full_name}</Title>
      <Card>
        <Text style={styles.row}>Rola: {ROLE_LABELS[employee.role]}</Text>
        <Text style={styles.row}>Dział: {DEPARTMENT_LABELS[employee.department]}</Text>
        <Text style={styles.row}>E-mail: {session?.user.email}</Text>
        {employee.swaps_require_approval ? (
          <Text style={styles.note}>Twoje zamiany zmian zatwierdza Halina.</Text>
        ) : null}
      </Card>
      <Button title="Wyloguj" variant="secondary" onPress={() => void signOut()} />
    </Screen>
  );
}

const styles = StyleSheet.create({
  row: { fontSize: 15, color: colors.text },
  note: { fontSize: 14, color: colors.warning, marginTop: 4 },
});
