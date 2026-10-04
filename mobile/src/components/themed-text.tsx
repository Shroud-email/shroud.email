import { Text, type TextProps } from 'react-native';
import type { ThemeColor } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';

export type ThemedTextProps = TextProps & {
  type?: 'default' | 'title' | 'small' | 'smallBold' | 'subtitle';
  themeColor?: ThemeColor;
};

export function ThemedText({
  type = 'default',
  themeColor = 'text',
  style,
  ...props
}: ThemedTextProps) {
  const theme = useTheme();
  const bold = ['title', 'subtitle', 'smallBold'].includes(type);
  return (
    <Text
      {...props}
      style={[
        {
          color: theme[themeColor],
          fontFamily: bold ? 'Manrope_700Bold' : 'Manrope_400Regular',
          fontSize:
            type === 'title'
              ? 26
              : type === 'subtitle'
                ? 16
                : type.startsWith('small')
                  ? 13
                  : 14,
          lineHeight: type === 'title' ? 32 : 21,
          ...(type === 'title' && { letterSpacing: -0.8 }),
        },
        style,
      ]}
    />
  );
}
