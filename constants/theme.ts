// Kolory i odstępy aplikacji. Ciepła, "cukiernicza" paleta, wysoki kontrast tekstu.
export const colors = {
  background: '#FBF7F2',
  surface: '#FFFFFF',
  border: '#E7DDD1',
  text: '#2B211A',
  textMuted: '#6E6157',
  primary: '#8C4A2F',
  primaryText: '#FFFFFF',
  danger: '#B3261E',
  warning: '#8A5A00',
  warningBackground: '#FFF4D6',
  success: '#2E6B3A',
  unreadBackground: '#F6ECE3',
} as const;

export const spacing = {
  xs: 4,
  sm: 8,
  md: 16,
  lg: 24,
  xl: 32,
} as const;

export const radius = {
  sm: 6,
  md: 10,
} as const;
