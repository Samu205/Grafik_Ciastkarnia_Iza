import type { Enums } from '@/lib/types/database';

export const ROLE_LABELS: Record<Enums<'app_role'>, string> = {
  owner: 'Właścicielka',
  scheduler: 'Układa grafik',
  employee: 'Pracownik',
};

export const DEPARTMENT_LABELS: Record<Enums<'department'>, string> = {
  sales: 'Sprzedaż',
  production: 'Produkcja',
};

export const MONTH_STATUS_LABELS: Record<Enums<'month_status'>, string> = {
  collecting: 'Zbieranie dyspozycyjności',
  drafting: 'Układanie grafiku',
  published: 'Opublikowany',
};

export const SWAP_STATUS_LABELS: Record<Enums<'swap_status'>, string> = {
  open: 'Czeka na chętnego',
  awaiting_requester: 'Czeka na Twoje potwierdzenie',
  pending_approval: 'Czeka na zatwierdzenie Haliny',
  done: 'Wykonana',
  rejected: 'Odrzucona',
  cancelled: 'Anulowana',
  expired: 'Wygasła',
};
