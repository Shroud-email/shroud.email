import { Redirect } from "expo-router";

// The provider consumes the original Linking URL, not router-normalized parameters.
export default function OAuthCallback() {
  return <Redirect href="/" />;
}
