/**
 * Learn more about light and dark modes:
 * https://docs.expo.dev/guides/color-schemes/
 */

import { Colors } from '@/constants/theme';
import { useApp } from '@/providers/app-provider';

export function useTheme() {
  return Colors[useApp().scheme];
}
