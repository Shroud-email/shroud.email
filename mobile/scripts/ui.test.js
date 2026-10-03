const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');
const React = require('react');
const { act, create } = require('react-test-renderer');

global.IS_REACT_ACT_ENVIRONMENT = true;

// Render our real components; replace only native/platform boundaries for Node.
function load(source, mocks, cache = {}) {
  const filename = path.resolve(__dirname, '../src', source);
  if (cache[filename]) return cache[filename].exports;
  const module = { exports: {} };
  cache[filename] = module;
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      jsx: ts.JsxEmit.ReactJSX,
    },
  }).outputText;
  new Function('require', 'module', 'exports', code)(
    (name) => {
      if (name in mocks) return mocks[name];
      if (name.startsWith('@/')) {
        const relative = name.slice(2);
        const extension = fs.existsSync(
          path.resolve(__dirname, '../src', `${relative}.tsx`),
        )
          ? '.tsx'
          : '.ts';
        return load(relative + extension, mocks, cache);
      }
      return require(name);
    },
    module,
    module.exports,
  );
  return module.exports;
}

const native = Object.fromEntries(
  [
    'View',
    'Text',
    'Pressable',
    'TextInput',
    'ScrollView',
    'KeyboardAvoidingView',
  ].map((name) => [name, name]),
);
native.Platform = { OS: 'ios' };
const platformMocks = {
  'react-native': native,
  'react-native-safe-area-context': { SafeAreaView: 'SafeAreaView' },
  'expo-router': { router: {} },
  'phosphor-react-native': {
    CopyIcon: 'CopyIcon',
    CheckIcon: 'CheckIcon',
    CaretDownIcon: 'CaretDownIcon',
  },
  '@/hooks/use-theme': { useTheme: () => ({}) },
};

test('a late appearance restore cannot overwrite a newer user selection', async () => {
  let restore;
  const stored = new Promise((resolve) => {
    restore = resolve;
  });
  const { AppProvider, useApp } = load('providers/app-provider.tsx', {
    '@react-native-async-storage/async-storage': {
      getItem: () => stored,
      setItem: async () => {},
    },
    'expo-crypto': {},
    '@/hooks/use-color-scheme': { useColorScheme: () => 'light' },
  });
  let app;
  function Probe() {
    app = useApp();
    return null;
  }
  let tree;
  await act(() => {
    tree = create(
      React.createElement(AppProvider, null, React.createElement(Probe)),
    );
  });
  await act(() => app.setAppearance('dark'));
  await act(() => restore('light'));
  assert.equal(app.appearance, 'dark');
  await act(() => tree.unmount());
});

test('copy feedback expires and compact feedback stays in layout flow', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const { CopyButton } = load('components/ui.tsx', {
    ...platformMocks,
    'expo-clipboard': { setStringAsync: async () => true },
  });
  let tree;
  await act(() => {
    tree = create(
      React.createElement(CopyButton, {
        address: 'abc@example.com',
        compact: true,
      }),
    );
  });
  await act(() => tree.root.findByType('Pressable').props.onPress());
  const feedback = tree.root.findByType('Text');
  const styles = feedback.props.style.flat();
  assert.ok(!styles.some((style) => style?.position === 'absolute'));
  await act(() => t.mock.timers.tick(2100));
  assert.equal(tree.root.findAllByType('CheckIcon').length, 0);
  assert.equal(tree.root.findAllByType('Text').length, 0);
  await act(() => tree.unmount());
});

test('custom address preview is hidden for invalid names but normalizes valid names', async () => {
  const { default: CreateScreen } = load('app/create.tsx', {
    ...platformMocks,
    'expo-clipboard': {},
    '@/providers/app-provider': {
      useApp: () => ({
        domains: [{ name: 'mail.example.com', verified: true }],
        addAlias: () => {},
      }),
    },
    '@/providers/auth-stub': {
      useAuth: () => ({ session: { email: 'alex@example.com' } }),
    },
  });
  let tree;
  await act(() => {
    tree = create(React.createElement(CreateScreen));
  });
  await act(() => tree.root.findAllByType('Pressable')[2].props.onPress());
  const field = tree.root.findByType('TextInput');
  await act(() => field.props.onChangeText('bad name'));
  assert.ok(!JSON.stringify(tree.toJSON()).includes('Your new alias'));
  await act(() => field.props.onChangeText(' Receipts '));
  const preview = tree.root
    .findAllByType('Text')
    .find((node) => node.props.children?.[1] === '@');
  assert.deepEqual(preview.props.children, [
    'receipts',
    '@',
    'mail.example.com',
  ]);
  await act(() => tree.unmount());
});
