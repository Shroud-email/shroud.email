import { router } from 'expo-router';
import { CaretDownIcon, CheckIcon } from 'phosphor-react-native';
import { useState } from 'react';
import { Pressable, View } from 'react-native';
import { Button, Field, Header, Screen, Section, row } from '@/components/ui';
import { ThemedText } from '@/components/themed-text';
import { useTheme } from '@/hooks/use-theme';
import { useApp } from '@/providers/app-provider';
import { useAuth } from '@/providers/auth-stub';
import { isValidAliasName } from '@/data/aliases';

export default function CreateScreen() {
  const { domains, addAlias } = useApp();
  const { session } = useAuth();
  const c = useTheme();
  const [type, setType] = useState<'random' | 'custom'>('random');
  const [name, setName] = useState('');
  const [domain, setDomain] = useState(
    domains.find((d) => d.verified)?.name ?? '',
  );
  const [open, setOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);
  function submit() {
    try {
      const alias = addAlias({ type, name, domain });
      router.replace({ pathname: '/aliases/[id]', params: { id: alias.id } });
    } catch (error) {
      setError(
        error instanceof Error ? error.message : 'Could not create this alias.',
      );
    }
  }
  return (
    <Screen>
      <Header
        title="Create alias"
        action={
          <Button
            label="Cancel"
            kind="text"
            onPress={() =>
              router.canGoBack() ? router.back() : router.replace('/')
            }
          />
        }
      />
      <View style={{ gap: 8, paddingTop: 12, marginBottom: 20 }}>
        <ThemedText themeColor="textSecondary">Address type</ThemedText>
        <View
          accessibilityRole="radiogroup"
          accessibilityLabel="Address type"
          style={[
            row,
            {
              backgroundColor: c.backgroundElement,
              borderRadius: 10,
              padding: 4,
              gap: 4,
            },
          ]}
        >
          {(['random', 'custom'] as const).map((value) => (
            <Pressable
              key={value}
              accessibilityRole="radio"
              aria-checked={type === value}
              onPress={() => {
                setType(value);
                setError(null);
                setOpen(false);
              }}
              style={{
                flex: 1,
                minHeight: 44,
                alignItems: 'center',
                justifyContent: 'center',
                borderRadius: 7,
                backgroundColor:
                  type === value ? c.backgroundSelected : 'transparent',
              }}
            >
              <ThemedText
                style={{
                  fontFamily:
                    type === value
                      ? 'Manrope_600SemiBold'
                      : 'Manrope_400Regular',
                }}
              >
                {value === 'random' ? 'Random address' : 'Custom domain'}
              </ThemedText>
            </Pressable>
          ))}
        </View>
      </View>
      {type === 'custom' ? (
        <>
          <View style={{ gap: 8, marginBottom: 20 }}>
            <ThemedText>Alias name</ThemedText>
            <Field
              accessibilityLabel="Alias name"
              value={name}
              onChangeText={(value) => {
                setName(value);
                setError(null);
              }}
              autoCapitalize="none"
              autoCorrect={false}
              placeholder="shopping"
              maxLength={64}
            />
            <ThemedText type="small" themeColor="textSecondary">
              Choose the part before the @.
            </ThemedText>
          </View>
          <View style={{ gap: 8, marginBottom: 20 }}>
            <ThemedText>Domain</ThemedText>
            <Pressable
              accessibilityRole="button"
              accessibilityLabel="Choose domain"
              accessibilityState={{ expanded: open }}
              onPress={() => setOpen(!open)}
              style={[
                row,
                {
                  minHeight: 52,
                  paddingHorizontal: 14,
                  borderRadius: 10,
                  borderWidth: 1,
                  borderColor: c.inputBorder,
                  backgroundColor: c.backgroundElement,
                  justifyContent: 'space-between',
                },
              ]}
            >
              <ThemedText style={{ fontSize: 16 }}>
                {domain || 'Choose a domain'}
              </ThemedText>
              <CaretDownIcon size={18} color={c.textSecondary} />
            </Pressable>
            {open && (
              <View
                style={{
                  borderWidth: 1,
                  borderColor: c.inputBorder,
                  borderRadius: 10,
                  backgroundColor: c.backgroundElement,
                }}
              >
                {domains.map((option) => (
                  <Pressable
                    key={option.name}
                    accessibilityRole="button"
                    accessibilityLabel={
                      option.verified
                        ? option.name
                        : `${option.name}, Unverified`
                    }
                    accessibilityState={{
                      disabled: !option.verified,
                      selected: domain === option.name,
                    }}
                    disabled={!option.verified}
                    onPress={() => {
                      setDomain(option.name);
                      setOpen(false);
                      setError(null);
                    }}
                    style={[
                      row,
                      {
                        minHeight: 52,
                        paddingHorizontal: 14,
                        gap: 8,
                        opacity: option.verified ? 1 : 0.45,
                      },
                    ]}
                  >
                    <ThemedText style={{ flex: 1 }}>{option.name}</ThemedText>
                    {!option.verified ? (
                      <ThemedText type="small" themeColor="textMuted">
                        Unverified
                      </ThemedText>
                    ) : (
                      domain === option.name && (
                        <CheckIcon color={c.accent} size={18} />
                      )
                    )}
                  </Pressable>
                ))}
              </View>
            )}
          </View>
        </>
      ) : (
        <View style={{ gap: 8, marginBottom: 20 }}>
          <ThemedText type="subtitle">
            We’ll generate an address for you
          </ThemedText>
          <ThemedText themeColor="textSecondary">
            A unique, random address on fog.shroud.email will be created when
            you tap Create alias.
          </ThemedText>
        </View>
      )}
      <Section>
        {type === 'custom' && isValidAliasName(name) && domain.length > 0 && (
          <>
            <ThemedText type="small" themeColor="textMuted">
              Your new alias
            </ThemedText>
            <ThemedText type="subtitle">
              {name.trim().toLowerCase()}@{domain}
            </ThemedText>
          </>
        )}
        <ThemedText type="small" themeColor="textSecondary">
          Forwards to {session?.email}
        </ThemedText>
      </Section>
      {error && (
        <ThemedText
          accessibilityRole="alert"
          themeColor="danger"
          style={{ marginTop: 16 }}
        >
          {error}
        </ThemedText>
      )}
      <View style={{ marginTop: 24 }}>
        <Button
          label="Create alias"
          onPress={submit}
          disabled={type === 'custom' && (!name.trim() || !domain)}
        />
      </View>
      <ThemedText type="small" themeColor="textMuted" style={{ marginTop: 16 }}>
        Your alias is enabled immediately. Add a title or notes on the next
        screen.
      </ThemedText>
    </Screen>
  );
}
