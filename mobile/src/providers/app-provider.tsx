import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Crypto from 'expo-crypto';
import {
  createContext,
  useContext,
  useEffect,
  useReducer,
  useState,
  type PropsWithChildren,
} from 'react';

import {
  aliasesReducer,
  createAlias,
  demoAliases,
  demoDomains,
  type CreateAliasInput,
  type EmailAlias,
} from '@/data/aliases';
import { useColorScheme } from '@/hooks/use-color-scheme';

export type Appearance = 'system' | 'light' | 'dark';
type AppState = {
  aliases: EmailAlias[];
  domains: typeof demoDomains;
  appearance: Appearance;
  scheme: 'light' | 'dark';
  setAppearance: (value: Appearance) => void;
  addAlias: (input: CreateAliasInput) => EmailAlias;
  updateAlias: (
    id: string,
    changes: Partial<Pick<EmailAlias, 'title' | 'notes'>>,
  ) => void;
  toggleAlias: (id: string) => void;
  deleteAlias: (id: string) => void;
  preferenceError: string | null;
};
const AppContext = createContext<AppState | null>(null);
const themeKey = 'shroud.appearance';

export function AppProvider({ children }: PropsWithChildren) {
  const [aliases, dispatch] = useReducer(aliasesReducer, demoAliases);
  const [appearance, setPreference] = useState<Appearance>('system');
  const [preferenceError, setPreferenceError] = useState<string | null>(null);
  const systemScheme = useColorScheme();

  useEffect(() => {
    let mounted = true;
    AsyncStorage.getItem(themeKey)
      .then((value) => {
        if (
          mounted &&
          (value === 'system' || value === 'light' || value === 'dark')
        )
          setPreference(value);
      })
      .catch(() => {
        if (mounted)
          setPreferenceError(
            'Appearance could not be restored on this device.',
          );
      });
    return () => {
      mounted = false;
    };
  }, []);

  function setAppearance(value: Appearance) {
    setPreference(value);
    setPreferenceError(null);
    AsyncStorage.setItem(themeKey, value).catch(() =>
      setPreferenceError(
        'Appearance changed, but could not be saved on this device.',
      ),
    );
  }

  function addAlias(input: CreateAliasInput) {
    const alias = createAlias(aliases, demoDomains, input, Crypto.randomUUID());
    dispatch({ type: 'create', alias });
    return alias;
  }

  return (
    <AppContext.Provider
      value={{
        aliases,
        domains: demoDomains,
        appearance,
        scheme:
          appearance === 'system'
            ? systemScheme === 'dark'
              ? 'dark'
              : 'light'
            : appearance,
        setAppearance,
        addAlias,
        preferenceError,
        updateAlias: (id, changes) => dispatch({ type: 'update', id, changes }),
        toggleAlias: (id) => dispatch({ type: 'toggle', id }),
        deleteAlias: (id) => dispatch({ type: 'delete', id }),
      }}
    >
      {children}
    </AppContext.Provider>
  );
}

export function useApp() {
  const app = useContext(AppContext);
  if (!app) throw new Error('useApp must be used inside AppProvider');
  return app;
}
