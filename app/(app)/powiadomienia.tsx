import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, StyleSheet, Text } from 'react-native';

import { Card, ErrorText, Loading, Muted, Screen, Title } from '@/components/ui';
import { colors } from '@/constants/theme';
import { formatTimestamp } from '@/lib/format';
import { supabase } from '@/lib/supabase';

type Notification = {
  id: string;
  message: string;
  created_at: string;
  read_at: string | null;
};

export default function NotificationsScreen() {
  const [items, setItems] = useState<Notification[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const { data, error: queryError } = await supabase
      .from('notifications')
      .select('id, message, created_at, read_at')
      .order('created_at', { ascending: false })
      .limit(50);

    if (queryError) {
      setError(`Nie udało się pobrać powiadomień: ${queryError.message}`);
      return;
    }
    setError(null);
    setItems(data ?? []);
  }, []);

  useFocusEffect(
    useCallback(() => {
      void load();
    }, [load]),
  );

  async function markRead(id: string) {
    const { error: updateError } = await supabase
      .from('notifications')
      .update({ read_at: new Date().toISOString() })
      .eq('id', id);
    if (updateError) {
      setError(`Nie udało się oznaczyć jako przeczytane: ${updateError.message}`);
      return;
    }
    await load();
  }

  if (!items) {
    return error ? (
      <Screen>
        <ErrorText>{error}</ErrorText>
      </Screen>
    ) : (
      <Loading />
    );
  }

  return (
    <Screen>
      <Title>Powiadomienia</Title>
      {error ? <ErrorText>{error}</ErrorText> : null}
      {items.length === 0 ? <Muted>Nie masz jeszcze żadnych powiadomień.</Muted> : null}
      {items.map((item) => {
        const unread = item.read_at === null;
        return (
          <Pressable
            key={item.id}
            accessibilityRole="button"
            accessibilityHint={unread ? 'Oznacza jako przeczytane' : undefined}
            onPress={unread ? () => void markRead(item.id) : undefined}
          >
            <Card highlighted={unread}>
              <Text style={[styles.message, unread && styles.unread]}>{item.message}</Text>
              <Text style={styles.time}>{formatTimestamp(item.created_at)}</Text>
            </Card>
          </Pressable>
        );
      })}
    </Screen>
  );
}

const styles = StyleSheet.create({
  message: { fontSize: 15, color: colors.text, lineHeight: 21 },
  unread: { fontWeight: '600' },
  time: { fontSize: 13, color: colors.textMuted },
});
