import type { Session } from '@supabase/supabase-js';
import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react';

import { supabase } from '@/lib/supabase';
import type { Tables } from '@/lib/types/database';

export type Employee = Tables<'employees'>;

type AuthState = {
  /** true, dopóki nie wiemy, czy ktoś jest zalogowany */
  loading: boolean;
  session: Session | null;
  /** Rekord pracownika; null = konto bez przypisanego pracownika albo nieaktywne */
  employee: Employee | null;
  isManager: boolean;
  isOwner: boolean;
  signOut: () => Promise<void>;
  reloadEmployee: () => Promise<void>;
};

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [sessionLoading, setSessionLoading] = useState(true);
  const [employee, setEmployee] = useState<Employee | null>(null);
  const [employeeLoading, setEmployeeLoading] = useState(false);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setSessionLoading(false);
    });

    // W tym callbacku tylko ustawiamy stan – wywołania supabase w środku mogą się zablokować.
    const { data } = supabase.auth.onAuthStateChange((_event, newSession) => {
      setSession(newSession);
    });
    return () => data.subscription.unsubscribe();
  }, []);

  const userId = session?.user.id ?? null;

  const reloadEmployee = useCallback(async () => {
    if (!userId) {
      setEmployee(null);
      return;
    }
    setEmployeeLoading(true);
    const { data, error } = await supabase
      .from('employees')
      .select('*')
      .eq('id', userId)
      .eq('active', true)
      .maybeSingle();
    if (error) {
      console.warn('Nie udało się pobrać profilu pracownika', error.message);
    }
    setEmployee(data ?? null);
    setEmployeeLoading(false);
  }, [userId]);

  useEffect(() => {
    void reloadEmployee();
  }, [reloadEmployee]);

  const signOut = useCallback(async () => {
    await supabase.auth.signOut();
    setEmployee(null);
  }, []);

  const value: AuthState = {
    loading: sessionLoading || employeeLoading,
    session,
    employee,
    isManager: employee?.role === 'owner' || employee?.role === 'scheduler',
    isOwner: employee?.role === 'owner',
    signOut,
    reloadEmployee,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthState {
  const ctx = useContext(AuthContext);
  if (!ctx) {
    throw new Error('useAuth() musi być użyte wewnątrz <AuthProvider>');
  }
  return ctx;
}
