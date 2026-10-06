import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { StyleSheet, Text } from 'react-native';

import { Card, ErrorText, Loading, Muted, Screen, Title } from '@/components/ui';
import { colors } from '@/constants/theme';
import { useAuth } from '@/lib/auth';
import { formatHours, formatLongDate, todayInWarsaw } from '@/lib/format';
import { supabase } from '@/lib/supabase';

type MyShift = {
  id: string;
  date: string;
  start_time: string;
  end_time: string;
  schedules: { name: string } | null;
};

/**
 * "Moje zmiany" – wszystkie nadchodzące zmiany pracownika ze wszystkich grafików
 * w jednym miejscu. RLS pokazuje tylko opublikowane miesiące.
 */
export default function MyShiftsScreen() {
  const { employee } = useAuth();
  const [shifts, setShifts] = useState<MyShift[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!employee) return;
    const { data, error: queryError } = await supabase
      .from('shifts')
      .select('id, date, start_time, end_time, schedules(name)')
      .eq('employee_id', employee.id)
      .gte('date', todayInWarsaw())
      .order('date')
      .order('start_time');

    if (queryError) {
      setError(`Nie udało się pobrać grafiku: ${queryError.message}`);
      return;
    }
    setError(null);
    setShifts(data ?? []);
  }, [employee]);

  useFocusEffect(
    useCallback(() => {
      void load();
    }, [load]),
  );

  if (error) {
    return (
      <Screen>
        <ErrorText>{error}</ErrorText>
      </Screen>
    );
  }
  if (!shifts) {
    return <Loading />;
  }

  return (
    <Screen>
      <Title>Cześć, {employee?.full_name}!</Title>

      {shifts.length === 0 ? (
        <Muted>
          Nie masz zaplanowanych zmian w opublikowanym grafiku. Gdy Halina opublikuje grafik,
          zobaczysz je tutaj.
        </Muted>
      ) : (
        shifts.map((shift, index) => (
          <Card key={shift.id} highlighted={index === 0}>
            {index === 0 ? <Text style={styles.badge}>Najbliższa zmiana</Text> : null}
            <Text style={styles.date}>{formatLongDate(shift.date)}</Text>
            <Text style={styles.details}>
              {shift.schedules?.name ?? 'Grafik'} · {formatHours(shift.start_time, shift.end_time)}
            </Text>
          </Card>
        ))
      )}
    </Screen>
  );
}

const styles = StyleSheet.create({
  badge: { fontSize: 13, fontWeight: '700', color: colors.primary, textTransform: 'uppercase' },
  date: { fontSize: 17, fontWeight: '600', color: colors.text },
  details: { fontSize: 15, color: colors.textMuted },
});
