import AsyncStorage from '@react-native-async-storage/async-storage';
import { createClient } from '@supabase/supabase-js';
import { Platform } from 'react-native';

import type { Database } from '@/lib/types/database';

const supabaseUrl = process.env.EXPO_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    'Brak konfiguracji Supabase. Skopiuj .env.example do .env i uzupełnij ' +
      'EXPO_PUBLIC_SUPABASE_URL oraz EXPO_PUBLIC_SUPABASE_ANON_KEY.',
  );
}

const isWeb = Platform.OS === 'web';

export const supabase = createClient<Database>(supabaseUrl, supabaseAnonKey, {
  auth: {
    // Na webie sesja w localStorage (domyślnie), na telefonie w AsyncStorage.
    storage: isWeb ? undefined : AsyncStorage,
    autoRefreshToken: true,
    persistSession: true,
    // Link z maila wraca na stronę z ?code=..., który supabase-js wymienia na sesję.
    detectSessionInUrl: isWeb,
    flowType: 'pkce',
  },
});
