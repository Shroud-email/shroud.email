import { router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { Modal, Platform, Switch, View } from 'react-native';
import {
  Button,
  CopyButton,
  Field,
  Header,
  Screen,
  Section,
  row,
} from '@/components/ui';
import { ThemedText } from '@/components/themed-text';
import { useTheme } from '@/hooks/use-theme';
import { useApp } from '@/providers/app-provider';
import { useAuth } from '@/providers/auth-stub';

export default function DetailsScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { aliases, updateAlias, toggleAlias, deleteAlias } = useApp();
  const { session } = useAuth();
  const c = useTheme();
  const alias = aliases.find((item) => item.id === id);
  const [deleting, setDeleting] = useState(false);
  if (!alias)
    return (
      <Screen>
        <Header title="Alias details" back />
        <ThemedText>This alias no longer exists.</ThemedText>
        <Button label="Back to aliases" onPress={() => router.replace('/')} />
      </Screen>
    );
  return (
    <Screen>
      <Header title="Alias details" back />
      <View style={{ gap: 12, paddingTop: 12, paddingBottom: 20 }}>
        <ThemedText type="subtitle" selectable>
          {alias.address}
        </ThemedText>
        <CopyButton address={alias.address} />
      </View>
      <Section>
        <View style={[row, { gap: 16 }]}>
          <View style={{ flex: 1, gap: 6 }}>
            <ThemedText type="subtitle">
              Forwarding {alias.enabled ? 'enabled' : 'disabled'}
            </ThemedText>
            <ThemedText type="small" themeColor="textSecondary">
              {alias.enabled
                ? 'Turn off to stop receiving email.\nYou can re-enable it any time.'
                : 'Turn on to receive email again.'}
            </ThemedText>
          </View>
          <Switch
            accessibilityLabel="Enable email forwarding"
            value={alias.enabled}
            onValueChange={() => toggleAlias(id)}
            trackColor={{ false: c.backgroundSelected, true: c.primary }}
            thumbColor="#FFFFFF"
            {...(Platform.OS === 'web' ? { activeThumbColor: '#FFFFFF' } : {})}
          />
        </View>
      </Section>
      <Editable
        label="Title"
        value={alias.title}
        onSave={(title) => updateAlias(id, { title })}
      />
      <Editable
        label="Notes"
        value={alias.notes}
        multiline
        onSave={(notes) => updateAlias(id, { notes })}
      />
      <Section>
        <ThemedText type="small" themeColor="textSecondary">
          Forwards to
        </ThemedText>
        <ThemedText>{session?.email}</ThemedText>
      </Section>
      <Section>
        <View style={[row, { gap: 24 }]}>
          <View style={{ flex: 1, gap: 6 }}>
            <ThemedText type="small" themeColor="textSecondary">
              Emails forwarded
            </ThemedText>
            <ThemedText type="subtitle">{alias.forwarded}</ThemedText>
          </View>
          <View style={{ flex: 1, gap: 6 }}>
            <ThemedText type="small" themeColor="textSecondary">
              This month
            </ThemedText>
            <ThemedText type="subtitle">{alias.forwardedThisMonth}</ThemedText>
          </View>
        </View>
      </Section>
      <View style={{ marginTop: 24 }}>
        <Button
          label="Delete alias"
          kind="danger"
          onPress={() => setDeleting(true)}
        />
      </View>
      <Modal
        visible={deleting}
        transparent
        animationType="fade"
        onRequestClose={() => setDeleting(false)}
      >
        <View
          style={{
            flex: 1,
            backgroundColor: '#00000088',
            justifyContent: 'center',
            padding: 24,
          }}
        >
          <View
            accessibilityViewIsModal
            style={{
              backgroundColor: c.background,
              borderRadius: 16,
              padding: 24,
              gap: 16,
              maxWidth: 450,
              width: '100%',
              alignSelf: 'center',
            }}
          >
            <ThemedText type="subtitle">Delete this alias?</ThemedText>
            <ThemedText>
              {alias.address} will stop receiving email. This cannot be undone.
            </ThemedText>
            <Button
              label="Cancel"
              kind="outline"
              onPress={() => setDeleting(false)}
            />
            <Button
              label="Delete permanently"
              kind="danger"
              onPress={() => {
                setDeleting(false);
                deleteAlias(id);
                router.replace('/');
              }}
            />
          </View>
        </View>
      </Modal>
    </Screen>
  );
}

function Editable({
  label,
  value,
  multiline = false,
  onSave,
}: {
  label: string;
  value: string | null;
  multiline?: boolean;
  onSave: (value: string) => void;
}) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState('');
  return (
    <Section>
      <View style={[row, { justifyContent: 'space-between' }]}>
        <View style={{ flex: 1, gap: 8 }}>
          <ThemedText type="small" themeColor="textSecondary">
            {label}
          </ThemedText>
          {!editing && value ? <ThemedText>{value}</ThemedText> : null}
        </View>
        {!editing && (
          <Button
            label="Edit"
            accessibilityLabel={`Edit ${label.toLowerCase()}`}
            kind="text"
            onPress={() => {
              setDraft(value ?? '');
              setEditing(true);
            }}
          />
        )}
      </View>
      {editing ? (
        <>
          <Field
            accessibilityLabel={`Edit ${label.toLowerCase()}`}
            autoFocus
            multiline={multiline}
            value={draft}
            onChangeText={setDraft}
            style={
              multiline
                ? { minHeight: 120, textAlignVertical: 'top' }
                : undefined
            }
          />
          <View style={[row, { gap: 8 }]}>
            <Button
              label="Save"
              onPress={() => {
                onSave(draft);
                setEditing(false);
              }}
            />
            <Button
              label="Cancel"
              kind="text"
              onPress={() => setEditing(false)}
            />
          </View>
        </>
      ) : null}
    </Section>
  );
}
