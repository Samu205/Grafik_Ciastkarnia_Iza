import * as Linking from 'expo-linking';
import { Redirect } from 'expo-router';
import { useState } from 'react';

import { Button, ErrorText, Loading, Muted, Screen, TextField, Title } from '@/components/ui';
import { useAuth } from '@/lib/auth';
import { supabase } from '@/lib/supabase';

type Status = 'idle' | 'sending' | 'sent';

export default function LoginScreen() {
  const { loading, session } = useAuth();
  const [email, setEmail] = useState('');
  const [status, setStatus] = useState<Status>('idle');
  const [error, setError] = useState<string | null>(null);

  if (loading) {
    return <Loading />;
  }
  if (session) {
    return <Redirect href="/" />;
  }

  async function sendLink() {
    setError(null);
    const address = email.trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(address)) {
      setError('Wpisz poprawny adres e-mail.');
      return;
    }

    setStatus('sending');
    const { error: authError } = await supabase.auth.signInWithOtp({
      email: address,
      options: { emailRedirectTo: Linking.createURL('/') },
    });

    if (authError) {
      setStatus('idle');
      setError(`Nie udało się wysłać linku: ${authError.message}`);
      return;
    }
    setStatus('sent');
  }

  return (
    <Screen>
      <Title>Grafik Ciastkarnia Iza</Title>

      {status === 'sent' ? (
        <>
          <Muted>
            Wysłaliśmy link do logowania na adres {email.trim()}. Otwórz maila na tym urządzeniu i
            kliknij link.
          </Muted>
          <Button title="Wyślij ponownie" variant="secondary" onPress={() => setStatus('idle')} />
        </>
      ) : (
        <>
          <Muted>Podaj swój adres e-mail. Wyślemy Ci link do logowania – bez hasła.</Muted>
          <TextField
            label="Adres e-mail"
            value={email}
            onChangeText={setEmail}
            autoCapitalize="none"
            autoComplete="email"
            keyboardType="email-address"
            inputMode="email"
            onSubmitEditing={() => void sendLink()}
            placeholder="np. ania@example.com"
          />
          {error ? <ErrorText>{error}</ErrorText> : null}
          <Button
            title={status === 'sending' ? 'Wysyłam…' : 'Wyślij link'}
            onPress={() => void sendLink()}
            disabled={status === 'sending'}
          />
        </>
      )}
    </Screen>
  );
}
