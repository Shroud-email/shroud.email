import * as Clipboard from 'expo-clipboard';
import { router } from 'expo-router';
import { CaretLeftIcon, CopyIcon, CheckIcon } from 'phosphor-react-native';
import { useState, type PropsWithChildren, type ReactNode } from 'react';
import {
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  TextInput,
  View,
  type TextInputProps,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { ThemedText } from '@/components/themed-text';
import { useTheme } from '@/hooks/use-theme';

export const row = { flexDirection: 'row', alignItems: 'center' } as const;

export function Screen({
  children,
  scroll = true,
}: PropsWithChildren<{ scroll?: boolean }>) {
  const c = useTheme();
  return (
    <SafeAreaView
      edges={['top', 'left', 'right']}
      style={{ flex: 1, backgroundColor: c.background }}
    >
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        style={{ flex: 1 }}
      >
        {scroll ? (
          <ScrollView
            keyboardShouldPersistTaps="handled"
            contentContainerStyle={{
              paddingHorizontal: 20,
              paddingBottom: 40,
              width: '100%',
              maxWidth: 600,
              alignSelf: 'center',
            }}
          >
            {children}
          </ScrollView>
        ) : (
          <View
            style={{
              flex: 1,
              paddingHorizontal: 20,
              width: '100%',
              maxWidth: 600,
              alignSelf: 'center',
            }}
          >
            {children}
          </View>
        )}
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

export function Header({
  title,
  back = false,
  action,
}: {
  title: string;
  back?: boolean;
  action?: ReactNode;
}) {
  const c = useTheme();
  return (
    <View
      style={[
        row,
        {
          minHeight: 64,
          gap: 8,
          justifyContent: 'space-between',
          paddingVertical: 8,
        },
      ]}
    >
      {back && (
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Back to aliases"
          onPress={() =>
            router.canGoBack() ? router.back() : router.replace('/')
          }
          style={{ width: 44, height: 44, justifyContent: 'center' }}
        >
          <CaretLeftIcon size={24} color={c.accent} />
        </Pressable>
      )}
      <ThemedText type="title" style={{ flex: 1, fontSize: back ? 24 : 26 }}>
        {title}
      </ThemedText>
      {action}
    </View>
  );
}

export function Button({
  label,
  onPress,
  kind = 'primary',
  disabled = false,
  selected,
  accessibilityLabel,
}: {
  label: string;
  onPress: () => void;
  kind?: 'primary' | 'outline' | 'text' | 'danger';
  disabled?: boolean;
  selected?: boolean;
  accessibilityLabel?: string;
}) {
  const c = useTheme();
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      accessibilityState={{ disabled, selected }}
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => ({
        minHeight: kind === 'text' ? 44 : 48,
        paddingHorizontal: 14,
        justifyContent: 'center',
        alignItems: 'center',
        borderRadius: 10,
        backgroundColor: kind === 'primary' ? c.primary : 'transparent',
        borderWidth: kind === 'outline' || kind === 'danger' ? 1 : 0,
        borderColor: kind === 'danger' ? c.dangerBorder : c.inputBorder,
        opacity: disabled ? 0.4 : pressed ? 0.65 : 1,
      })}
    >
      <ThemedText
        style={{
          fontFamily: 'Manrope_600SemiBold',
          color:
            kind === 'primary'
              ? c.onPrimary
              : kind === 'danger'
                ? c.danger
                : c.accent,
        }}
      >
        {label}
      </ThemedText>
    </Pressable>
  );
}

export function Field({ style, ...props }: TextInputProps) {
  const c = useTheme();
  const [focused, setFocused] = useState(false);
  return (
    <TextInput
      {...props}
      placeholderTextColor={c.textMuted}
      selectionColor={c.primary}
      onFocus={(event) => {
        setFocused(true);
        props.onFocus?.(event);
      }}
      onBlur={(event) => {
        setFocused(false);
        props.onBlur?.(event);
      }}
      style={[
        {
          backgroundColor: c.backgroundElement,
          borderColor: focused ? c.primary : c.inputBorder,
          borderWidth: 1,
          borderRadius: 10,
          minHeight: 52,
          paddingHorizontal: 14,
          paddingVertical: 12,
          color: c.text,
          fontFamily: 'Manrope_400Regular',
          fontSize: 16,
        },
        style,
      ]}
    />
  );
}

export function Section({ children }: PropsWithChildren) {
  const c = useTheme();
  return (
    <View
      style={{
        borderBottomWidth: 1,
        borderColor: c.border,
        paddingVertical: 18,
        gap: 10,
      }}
    >
      {children}
    </View>
  );
}

export function CopyButton({
  address,
  compact = false,
}: {
  address: string;
  compact?: boolean;
}) {
  const c = useTheme();
  const [feedback, setFeedback] = useState<'idle' | 'copied' | 'error'>('idle');
  async function copy() {
    try {
      await Clipboard.setStringAsync(address);
      setFeedback('copied');
    } catch {
      setFeedback('error');
    }
  }
  return (
    <View>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={`Copy ${address}`}
        onPress={copy}
        style={[
          row,
          {
            minHeight: 44,
            minWidth: 44,
            justifyContent: 'center',
            gap: 8,
            ...(compact
              ? {}
              : {
                  borderColor: c.inputBorder,
                  borderWidth: 1,
                  borderRadius: 9,
                }),
          },
        ]}
      >
        {feedback === 'copied' ? (
          <CheckIcon size={19} color={c.accent} />
        ) : (
          <CopyIcon size={19} color={c.accent} />
        )}
        {!compact && (
          <ThemedText themeColor="accent">
            {feedback === 'copied' ? 'Copied' : 'Copy address'}
          </ThemedText>
        )}
      </Pressable>
      {feedback !== 'idle' && (compact || feedback === 'error') && (
        <ThemedText
          accessibilityLiveRegion="polite"
          type="small"
          themeColor={feedback === 'error' ? 'danger' : 'success'}
          style={
            compact
              ? { position: 'absolute', right: 0, top: 42, fontSize: 10 }
              : { textAlign: 'center' }
          }
        >
          {feedback === 'error' ? 'Copy failed' : compact ? 'Copied' : ''}
        </ThemedText>
      )}
    </View>
  );
}
