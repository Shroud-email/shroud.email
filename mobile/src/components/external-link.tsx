import { Href, Link } from "expo-router";
import {
  openBrowserAsync,
  WebBrowserPresentationStyle,
} from "expo-web-browser";
import { type ComponentProps } from "react";

type Props = Omit<ComponentProps<typeof Link>, "href"> & {
  href: Href & string;
};

export function ExternalLink({ href, ...rest }: Props) {
  return (
    <Link
      {...rest}
      href={href}
      onPress={async (event) => {
        event.preventDefault();
        await openBrowserAsync(href, {
          presentationStyle: WebBrowserPresentationStyle.AUTOMATIC,
        });
      }}
    />
  );
}
