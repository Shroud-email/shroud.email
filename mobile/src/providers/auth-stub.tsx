import {
  createContext,
  useContext,
  useState,
  type PropsWithChildren,
} from 'react';

// UI preview only. Replace this provider with the OAuth session provider later.
// It never creates credentials or sends authenticated requests.
type PreviewSession = { email: string; accessToken: null };
type AuthStub = {
  session: PreviewSession | null;
  logOut: () => void;
  startPreview: () => void;
};
const previewSession: PreviewSession = {
  email: 'alex@example.com',
  accessToken: null,
};
const AuthContext = createContext<AuthStub | null>(null);

export function AuthStubProvider({ children }: PropsWithChildren) {
  const [session, setSession] = useState<PreviewSession | null>(previewSession);
  return (
    <AuthContext.Provider
      value={{
        session,
        logOut: () => setSession(null),
        startPreview: () => setSession(previewSession),
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const auth = useContext(AuthContext);
  if (!auth) throw new Error('useAuth must be used inside AuthStubProvider');
  return auth;
}
