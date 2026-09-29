# Monorepo migration

## Source provenance

All imports preserve original commits through unsquashed subtree merges. Each
import's tree was compared to its source tree before migration-specific edits.
Existing app tags retain their original objects.

| Project | Source revision |
| --- | --- |
| shroud.email | [9635750](https://github.com/Shroud-email/shroud.email/commit/9635750) |
| website | [e82132e](https://github.com/Shroud-email/website/commit/e82132ec605b9bf88578008b1facd8ebf6d8c2f6) |
| hosting | [afa908b](https://github.com/Shroud-email/hosting/commit/afa908b2498bf2ed7b181d029130d0c61cc69069) |
| email-trackers | [deeef41](https://github.com/Shroud-email/email-trackers/commit/deeef41f9c48bd8d25c0ff300e967f4ea8a292b1) |
| caddy-permissive-file-storage | [4059a60](https://github.com/Shroud-email/caddy-permissive-file-storage/commit/4059a602db55a1762de165dac7f1204c823ebbd4) |

Historical files keep their original paths in original commits. Use the source
revision above with `git log <revision> -- <original-path>` to inspect pre-import
history. Do not squash or rebase away the import merge commits when integrating
this branch. Use a history-preserving merge.

Issues, PRs, release assets, secrets, and repository settings are not imported.
Keep the old repositories available for external source/module consumers during
cutover. The Go module identity is unchanged; hosting builds use a local source
replacement rather than fetching the old repository.
