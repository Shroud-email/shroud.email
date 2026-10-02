import { router } from 'expo-router';
import { MagnifyingGlassIcon } from 'phosphor-react-native';
import { useState } from 'react';
import { FlatList, Pressable, View } from 'react-native';
import {
  Button,
  CopyButton,
  Field,
  Header,
  Screen,
  row,
} from '@/components/ui';
import { ThemedText } from '@/components/themed-text';
import { filterAliases, type AliasFilter } from '@/data/aliases';
import { useTheme } from '@/hooks/use-theme';
import { useApp } from '@/providers/app-provider';

export default function AliasesScreen() {
  const { aliases } = useApp();
  const c = useTheme();
  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState<AliasFilter>('all');
  const visible = filterAliases(aliases, query, filter);
  return (
    <Screen scroll={false}>
      <Header
        title="Aliases"
        action={
          <Button label="+ New alias" onPress={() => router.push('/create')} />
        }
      />
      <View
        style={[
          row,
          {
            backgroundColor: c.backgroundElement,
            borderRadius: 10,
            paddingLeft: 14,
            marginBottom: 12,
          },
        ]}
      >
        <MagnifyingGlassIcon size={18} color={c.textSecondary} />
        <Field
          accessibilityLabel="Search aliases"
          placeholder="Search address or description"
          value={query}
          onChangeText={setQuery}
          autoCapitalize="none"
          style={{ flex: 1, borderWidth: 0, fontSize: 14 }}
        />
      </View>
      <View style={[row, { gap: 6, marginBottom: 12 }]}>
        {(['all', 'enabled', 'disabled'] as const).map((value) => (
          <Pressable
            key={value}
            accessibilityRole="button"
            accessibilityState={{ selected: filter === value }}
            onPress={() => setFilter(value)}
            style={{
              minHeight: 44,
              paddingHorizontal: 14,
              borderRadius: 8,
              justifyContent: 'center',
              backgroundColor:
                filter === value ? c.filterBackground : 'transparent',
            }}
          >
            <ThemedText
              type="smallBold"
              style={{
                color: filter === value ? c.filterText : c.textSecondary,
              }}
            >
              {value === 'all'
                ? `All ${aliases.length}`
                : value === 'enabled'
                  ? 'Enabled'
                  : 'Disabled'}
            </ThemedText>
          </Pressable>
        ))}
      </View>
      <FlatList
        data={visible}
        keyExtractor={(alias) => alias.id}
        keyboardShouldPersistTaps="handled"
        contentContainerStyle={{ paddingBottom: 20 }}
        ListEmptyComponent={
          <View style={{ paddingVertical: 40, gap: 8 }}>
            <ThemedText type="subtitle">
              {aliases.length ? 'No matching aliases' : 'No aliases yet'}
            </ThemedText>
            <ThemedText themeColor="textSecondary">
              {aliases.length
                ? 'Try another search or status filter.'
                : 'Create your first alias to get started.'}
            </ThemedText>
          </View>
        }
        renderItem={({ item: alias }) => (
          <View
            style={[
              row,
              {
                borderBottomWidth: 1,
                borderColor: c.border,
                paddingVertical: 12,
                gap: 4,
              },
            ]}
          >
            <Pressable
              accessibilityRole="button"
              accessibilityLabel={`Open ${alias.address}, ${alias.enabled ? 'enabled' : 'disabled'}`}
              onPress={() =>
                router.push({
                  pathname: '/aliases/[id]',
                  params: { id: alias.id },
                })
              }
              style={{
                flex: 1,
                minHeight: 44,
                justifyContent: 'center',
                gap: 7,
              }}
            >
              <View style={alias.title ? undefined : [row, { gap: 4 }]}>
                <ThemedText
                  style={{
                    fontFamily: 'Manrope_500Medium',
                    fontSize: 13,
                    lineHeight: 19,
                    flexShrink: 1,
                    ...(alias.title ? {} : { flexGrow: 1, flexBasis: 0 }),
                  }}
                >
                  {alias.address}
                </ThemedText>
                {!alias.title && (
                  <ThemedText
                    style={{
                      fontSize: 12,
                      color: alias.enabled ? c.success : c.danger,
                    }}
                  >
                    {alias.enabled ? 'Enabled' : 'Disabled'}
                  </ThemedText>
                )}
              </View>
              {alias.title && (
                <View
                  style={[
                    row,
                    {
                      justifyContent: 'space-between',
                      gap: 8,
                      paddingRight: 8,
                    },
                  ]}
                >
                  <ThemedText
                    themeColor="textSecondary"
                    style={{ fontSize: 12, flex: 1 }}
                  >
                    {alias.title}
                  </ThemedText>
                  <ThemedText
                    style={{
                      fontSize: 12,
                      color: alias.enabled ? c.success : c.danger,
                    }}
                  >
                    {alias.enabled ? 'Enabled' : 'Disabled'}
                  </ThemedText>
                </View>
              )}
            </Pressable>
            <CopyButton address={alias.address} compact />
          </View>
        )}
      />
    </Screen>
  );
}
