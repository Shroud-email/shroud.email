export type EmailAlias = {
  id: string;
  address: string;
  title: string | null;
  notes: string | null;
  enabled: boolean;
  forwarded: number;
  forwardedThisMonth: number;
};

export type Domain = { name: string; verified: boolean };
export type AliasFilter = 'all' | 'enabled' | 'disabled';
export type CreateAliasInput = {
  type: 'random' | 'custom';
  name: string;
  domain: string;
};
export type AliasAction =
  | { type: 'create'; alias: EmailAlias }
  | {
      type: 'update';
      id: string;
      changes: Partial<Pick<EmailAlias, 'title' | 'notes'>>;
    }
  | { type: 'toggle'; id: string }
  | { type: 'delete'; id: string };

export const demoDomains: Domain[] = [
  { name: 'mail.example.com', verified: true },
  { name: 'work.example.com', verified: true },
  { name: 'news.example.com', verified: false },
];

export const demoAliases: EmailAlias[] = [
  {
    id: 'linear',
    address: '2svf5roc5kach8@fog.shroud.email',
    title: 'Linear',
    notes: 'Work projects and notifications.',
    enabled: true,
    forwarded: 48,
    forwardedThisMonth: 11,
  },
  {
    id: 'github',
    address: 'q2dod1mt5zx12u@fog.shroud.email',
    title: 'GitHub',
    notes: null,
    enabled: true,
    forwarded: 65,
    forwardedThisMonth: 17,
  },
  {
    id: 'newsletters',
    address: 'e1eb0358ff93k1@fog.shroud.email',
    title: 'Tech newsletters',
    notes: null,
    enabled: true,
    forwarded: 26,
    forwardedThisMonth: 6,
  },
  {
    id: 'website',
    address: 'rkvy45x06ae8kbk@fog.shroud.email',
    title: 'Personal website',
    notes: null,
    enabled: true,
    forwarded: 12,
    forwardedThisMonth: 5,
  },
  {
    id: 'shopping',
    address: '1bfyegjpuzpgm3dr@fog.shroud.email',
    title: 'Online shopping',
    notes: null,
    enabled: false,
    forwarded: 19,
    forwardedThisMonth: 7,
  },
  {
    id: 'travel',
    address: '6kfb3bzxj6e8s4@fog.shroud.email',
    title: 'Travel bookings',
    notes: null,
    enabled: true,
    forwarded: 9,
    forwardedThisMonth: 4,
  },
  {
    id: 'untitled',
    address: '2nuwhww83jzs874@fog.shroud.email',
    title: null,
    notes: null,
    enabled: true,
    forwarded: 2,
    forwardedThisMonth: 2,
  },
];

export function filterAliases(
  aliases: EmailAlias[],
  query: string,
  filter: AliasFilter,
) {
  const search = query.trim().toLowerCase();
  return aliases.filter(
    (alias) =>
      (filter === 'all' || alias.enabled === (filter === 'enabled')) &&
      [alias.address, alias.title, alias.notes].some((value) =>
        value?.toLowerCase().includes(search),
      ),
  );
}

export function createAlias(
  aliases: EmailAlias[],
  domains: Domain[],
  input: CreateAliasInput,
  id: string,
): EmailAlias {
  let address: string;
  if (input.type === 'random') {
    address = `${id.replaceAll('-', '').slice(0, 14)}@fog.shroud.email`;
  } else {
    const name = input.name.trim().toLowerCase();
    if (
      !name ||
      !/^[a-z0-9.!#$%&'*+\-=^`{|}~]+$/.test(name) ||
      name.startsWith('.') ||
      name.endsWith('.') ||
      name.includes('..')
    ) {
      throw new Error(
        'Enter a valid alias name without spaces, underscores, or @.',
      );
    }
    if (
      !domains.some((domain) => domain.name === input.domain && domain.verified)
    ) {
      throw new Error('Choose a verified domain.');
    }
    address = `${name}@${input.domain}`;
  }
  if (aliases.some((alias) => alias.address.toLowerCase() === address)) {
    throw new Error('This alias already exists. Choose another name.');
  }
  return {
    id,
    address,
    title: null,
    notes: null,
    enabled: true,
    forwarded: 0,
    forwardedThisMonth: 0,
  };
}

export function aliasesReducer(
  aliases: EmailAlias[],
  action: AliasAction,
): EmailAlias[] {
  if (action.type === 'create') return [action.alias, ...aliases];
  if (action.type === 'delete')
    return aliases.filter((alias) => alias.id !== action.id);
  return aliases.map((alias) => {
    if (alias.id !== action.id) return alias;
    if (action.type === 'toggle') return { ...alias, enabled: !alias.enabled };
    return {
      ...alias,
      ...(action.changes.title !== undefined && {
        title: action.changes.title?.trim() || null,
      }),
      ...(action.changes.notes !== undefined && {
        notes: action.changes.notes?.trim() || null,
      }),
    };
  });
}
