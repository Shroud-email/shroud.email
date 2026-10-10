# Changelog

## [1.4.0](https://github.com/Shroud-email/shroud.email/compare/v1.3.0...v1.4.0) (2026-10-10)


### Features

* add admin mailserver health diagnostics ([#181](https://github.com/Shroud-email/shroud.email/issues/181)) ([ae42dfd](https://github.com/Shroud-email/shroud.email/commit/ae42dfd88d0f6e49832b6f9883b9ba9512a122cf))
* add alias API search, lookup, and updates ([#191](https://github.com/Shroud-email/shroud.email/issues/191)) ([495f619](https://github.com/Shroud-email/shroud.email/commit/495f619e4232042ec11b878a85c9ac5dd280af0a))
* add alias status filtering ([e0f2eef](https://github.com/Shroud-email/shroud.email/commit/e0f2eefd603c4e7f664252da33ebab7bb85007f0))
* add alias status filtering ([bac3cd5](https://github.com/Shroud-email/shroud.email/commit/bac3cd51802571cd2fc03c57b7c09fca393247e0))
* add cookieless analytics and paid signup tracking ([#232](https://github.com/Shroud-email/shroud.email/issues/232)) ([9188565](https://github.com/Shroud-email/shroud.email/commit/91885655c3fbba8226ced482afcccab38e2ab526))
* add copy buttons to alias list ([#177](https://github.com/Shroud-email/shroud.email/issues/177)) ([4adebbd](https://github.com/Shroud-email/shroud.email/commit/4adebbd46d3e33c602393c856fd7f8ef8f58e0e7))
* add hosted MCP tools with Boruta account connection ([#212](https://github.com/Shroud-email/shroud.email/issues/212)) ([0067c0e](https://github.com/Shroud-email/shroud.email/commit/0067c0e3a679dc7bd5ce5ee8627be77bf051d871))
* add passkey authentication ([#182](https://github.com/Shroud-email/shroud.email/issues/182)) ([21cf08b](https://github.com/Shroud-email/shroud.email/commit/21cf08be0a0b90f57c885617bf42ace1f6161b9f))
* add source-generated Starlight docs and Bunny deployment ([#201](https://github.com/Shroud-email/shroud.email/issues/201)) ([a95a3e3](https://github.com/Shroud-email/shroud.email/commit/a95a3e3bfcd0339ac169490e63fb74a1d0202f0d))
* alert on bounce reports ([52f9a91](https://github.com/Shroud-email/shroud.email/commit/52f9a910a7b98854999b815e202e76374067fc56))
* align app colour scheme and consolidate button styles ([#239](https://github.com/Shroud-email/shroud.email/issues/239)) ([f50d475](https://github.com/Shroud-email/shroud.email/commit/f50d4752b31a8b40c93a9c69b9383e61d6c12dbf))
* allow users to disable email branding ([#221](https://github.com/Shroud-email/shroud.email/issues/221)) ([7d95dc4](https://github.com/Shroud-email/shroud.email/commit/7d95dc4d6dfa56cec6c89167fb5f5c114b20b236))
* attribute signups to campaigns ([459cca3](https://github.com/Shroud-email/shroud.email/commit/459cca329598cf0c76c0342f843140a9d74f4986))
* attribute signups to campaigns in OpenPanel ([ac23a94](https://github.com/Shroud-email/shroud.email/commit/ac23a94688e5b2cd07a334b7bb65732599a5e412))
* email users when Paddle subscriptions become free ([c66e55d](https://github.com/Shroud-email/shroud.email/commit/c66e55d10d5dafb24d9ab0c4fb90c25a5ee953c3))
* email users when Paddle subscriptions become free ([1b13fb7](https://github.com/Shroud-email/shroud.email/commit/1b13fb77636640191529b316a019dab88ea9f07d))
* **email:** automatically visit remote images ([64c8ad6](https://github.com/Shroud-email/shroud.email/commit/64c8ad6bb7098bd2c0baf6b2c96c22584ff619ab))
* **email:** automatically visit remote images ([6bdb5d6](https://github.com/Shroud-email/shroud.email/commit/6bdb5d68151b46a4cad505b7b6d35929745b1362)), closes [#252](https://github.com/Shroud-email/shroud.email/issues/252)
* **email:** forward service postmaster mail to admin inbox ([#242](https://github.com/Shroud-email/shroud.email/issues/242)) ([1dc41e4](https://github.com/Shroud-email/shroud.email/commit/1dc41e4d7e8bca0716329fb9a39c7853c28ae9c9))
* enforce app-wide Hammer atomic rate limiting ([#208](https://github.com/Shroud-email/shroud.email/issues/208)) ([c9368b4](https://github.com/Shroud-email/shroud.email/commit/c9368b4d8213ad01c6504a500c9a389c7190ec0b))
* extend email image privacy to CSS and alternative sources ([cad0296](https://github.com/Shroud-email/shroud.email/commit/cad02965f0e95b0885ba5fd431d5dd55b450db44))
* extend email image privacy to CSS and alternative sources ([fe7950c](https://github.com/Shroud-email/shroud.email/commit/fe7950cd14dc4c8e18a5a2fbc1aeae65bcf199da))
* generate random usernames for custom-domain aliases ([#220](https://github.com/Shroud-email/shroud.email/issues/220)) ([2f5ee8d](https://github.com/Shroud-email/shroud.email/commit/2f5ee8d70ee097ec0019899d62df54c6895fffd6))
* make Sentry environment configurable ([#195](https://github.com/Shroud-email/shroud.email/issues/195)) ([4d5506e](https://github.com/Shroud-email/shroud.email/commit/4d5506e2624208ca471a585315c247c69ae25c42))
* **mcp:** improve alias pagination, creation and errors ([#237](https://github.com/Shroud-email/shroud.email/issues/237)) ([1f3654c](https://github.com/Shroud-email/shroud.email/commit/1f3654cb90790875133b04718cf2da0bd432a798))
* **mcp:** support client-neutral OAuth registration ([#235](https://github.com/Shroud-email/shroud.email/issues/235)) ([efe7d33](https://github.com/Shroud-email/shroud.email/commit/efe7d3353618eb40927cd7f79f34632b25d88741))
* migrate billing from Stripe to Paddle ([#163](https://github.com/Shroud-email/shroud.email/issues/163)) ([4adebbd](https://github.com/Shroud-email/shroud.email/commit/4adebbd46d3e33c602393c856fd7f8ef8f58e0e7))
* migrate settings pages to LiveView ([#193](https://github.com/Shroud-email/shroud.email/issues/193)) ([b0cc497](https://github.com/Shroud-email/shroud.email/commit/b0cc497a2e68449812907fe8d0cb933b0182b056))
* notify users of outgoing bounces ([34fa1df](https://github.com/Shroud-email/shroud.email/commit/34fa1df1eeb5429a0ed5f533e48339d9581b632b))
* notify users of outgoing bounces without delivery-history records ([40fc9fe](https://github.com/Shroud-email/shroud.email/commit/40fc9fe4b579b7487d7d38da260937e1ef83798b))
* notify users when a catch-all address fails validation ([#132](https://github.com/Shroud-email/shroud.email/issues/132)) ([356ae80](https://github.com/Shroud-email/shroud.email/commit/356ae80123cde134cff32710c0c316c822522123))
* **oauth:** support native and extension public clients ([#238](https://github.com/Shroud-email/shroud.email/issues/238)) ([a8891cb](https://github.com/Shroud-email/shroud.email/commit/a8891cb9ca7473eee6796be4af5efb10248ba691))
* paginate the aliases list with LiveView ([#216](https://github.com/Shroud-email/shroud.email/issues/216)) ([c24b54f](https://github.com/Shroud-email/shroud.email/commit/c24b54f8c4b30c962275ded409cdd6835e1e0206))
* polish copy, button, menu, and alias editor feedback ([b8f2f9b](https://github.com/Shroud-email/shroud.email/commit/b8f2f9b69424cacda43004d1b5bdcf1840da9749))
* polish interaction feedback across the app and website ([4289d5c](https://github.com/Shroud-email/shroud.email/commit/4289d5c856336aed853fe972307972834d763597))
* preserve campaign attribution and limit linked email analytics ([f4d2af4](https://github.com/Shroud-email/shroud.email/commit/f4d2af44562a764538f1f21dd83ed29ad2d8797a))
* remove integration and email branding feature flags ([8030bd0](https://github.com/Shroud-email/shroud.email/commit/8030bd02671a0cdd2eea380304dc64587c2ff36b))
* render bounce notifications with the standard HTML email layout ([7812450](https://github.com/Shroud-email/shroud.email/commit/7812450ea3d4e4a7f22c09f69cd624fe0747436d))
* replace PostHog with OpenPanel analytics ([5173fb8](https://github.com/Shroud-email/shroud.email/commit/5173fb82150cc6ae65e2be7b0d23785cd56ecf63))
* replace PostHog with OpenPanel analytics ([16c1944](https://github.com/Shroud-email/shroud.email/commit/16c19441db659b3f8df0f72832aa59bb7fb60523))
* report unclassified bounces to Sentry without email data ([c593d4d](https://github.com/Shroud-email/shroud.email/commit/c593d4dece4f018107d8dcb90b1cb4ef710a5f87))
* serve OpenAI domain verification challenge ([4bb5f9a](https://github.com/Shroud-email/shroud.email/commit/4bb5f9ad6441881bc594e96314afefb4819f623a))
* serve OpenAI domain verification challenge ([aaafba8](https://github.com/Shroud-email/shroud.email/commit/aaafba88d6c91eccd42de19a71e25a5100bf6240))
* **settings:** streamline connected apps and settings cards ([a6fe2a2](https://github.com/Shroud-email/shroud.email/commit/a6fe2a2b4656ad2089dac27b7f36cde36f36ac90))
* sync user status to Loops ([#174](https://github.com/Shroud-email/shroud.email/issues/174)) ([4adebbd](https://github.com/Shroud-email/shroud.email/commit/4adebbd46d3e33c602393c856fd7f8ef8f58e0e7))
* track Paddle revenue in OpenPanel ([cad5bfd](https://github.com/Shroud-email/shroud.email/commit/cad5bfd619dcc0a3b46f25db86931c1b67d490bc))
* track Paddle revenue in OpenPanel ([0e335bf](https://github.com/Shroud-email/shroud.email/commit/0e335bfd1ef3a7ba0022350e55958091b9c29a68))
* unify app notifications with persistent stacked toasts ([#224](https://github.com/Shroud-email/shroud.email/issues/224)) ([26ecd71](https://github.com/Shroud-email/shroud.email/commit/26ecd7145c23733f9b84102af00fe85ffbb6efba))
* use Plausible for website and app analytics ([#226](https://github.com/Shroud-email/shroud.email/issues/226)) ([8df752f](https://github.com/Shroud-email/shroud.email/commit/8df752f62d6c324450dfd0e91d62236617618df7))


### Bug Fixes

* accept case-insensitive delivery status actions ([af35599](https://github.com/Shroud-email/shroud.email/commit/af35599a25e9f7df3caab29becece4c97b08e63b))
* address alias filter review findings ([6755db4](https://github.com/Shroud-email/shroud.email/commit/6755db4806e3354b6a7a920db41ddd7b468b84a8))
* address OpenPanel review findings ([d7582c7](https://github.com/Shroud-email/shroud.email/commit/d7582c7db005f43cf6fcff904965ac8f149c31a3))
* avoid duplicate CSRF protection for FunWithFlags UI ([61b5656](https://github.com/Shroud-email/shroud.email/commit/61b5656f8f69a976eca8819e298d42d47a77096d))
* bound session return URLs to prevent cookie overflow ([f03ec93](https://github.com/Shroud-email/shroud.email/commit/f03ec938c708a12fb8f1e6aeb73aa1527f4b1f6b))
* compare Paddle event timestamps chronologically ([#197](https://github.com/Shroud-email/shroud.email/issues/197)) ([0c4e6d9](https://github.com/Shroud-email/shroud.email/commit/0c4e6d9b4a612600d2ebc2f9b26a136495525140))
* complete Elixir Sentry error reporting setup ([5ec0303](https://github.com/Shroud-email/shroud.email/commit/5ec030339a9b4a5b349031fef959f80ef91dae40))
* complete Elixir Sentry error reporting setup ([a04c274](https://github.com/Shroud-email/shroud.email/commit/a04c2742563854e2932341d5c49d34bdcc4c3720))
* cover video posters and mask-border images ([9abb342](https://github.com/Shroud-email/shroud.email/commit/9abb3429bd8626176fa95d312e077976dcf773f2))
* document email analytics privacy and synchronize absence assertion ([96d38a0](https://github.com/Shroud-email/shroud.email/commit/96d38a05c3fb39ac84b4707f1fae23c4a12219ca))
* **email:** cap image visits at 500 per message ([1c3de38](https://github.com/Shroud-email/shroud.email/commit/1c3de3842cb77b110106f0ea21a4b0b82e45336d))
* exclude rejected CSRF requests from Sentry ([#183](https://github.com/Shroud-email/shroud.email/issues/183)) ([4adebbd](https://github.com/Shroud-email/shroud.email/commit/4adebbd46d3e33c602393c856fd7f8ef8f58e0e7))
* handle case-insensitive image proxy headers ([#228](https://github.com/Shroud-email/shroud.email/issues/228)) ([546bf1a](https://github.com/Shroud-email/shroud.email/commit/546bf1a2e6dc3b818aa02f8d33aacc9209a9e69f)), closes [#44](https://github.com/Shroud-email/shroud.email/issues/44)
* handle empty optional notification configuration ([cac62cd](https://github.com/Shroud-email/shroud.email/commit/cac62cd0fcfd700897a6a1192ba20210e32e12e4))
* handle incomplete and malformed bounce reports ([e6906eb](https://github.com/Shroud-email/shroud.email/commit/e6906eb798c760f7a8b209a5e681d0cc91476768))
* hide unsupported passkey controls ([e321445](https://github.com/Shroud-email/shroud.email/commit/e321445ff789a336965d4a8ca883e97c1f27a6d6))
* **hosting:** make Cap, Sentry and Paddle optional ([#196](https://github.com/Shroud-email/shroud.email/issues/196)) ([c3a159e](https://github.com/Shroud-email/shroud.email/commit/c3a159e96e5b70619b6e99a6faa9ee1b71692b20))
* initialize clipboard buttons through LiveView hooks ([#202](https://github.com/Shroud-email/shroud.email/issues/202)) ([48d1362](https://github.com/Shroud-email/shroud.email/commit/48d13627ceb4d051d51c9da9385a16ec3b48f3ed))
* isolate email CSS parsing and fail open on processing errors ([ce56434](https://github.com/Shroud-email/shroud.email/commit/ce5643416392b58423b2d932d51e665f548fd9c8))
* isolate incoming email retries per recipient ([#223](https://github.com/Shroud-email/shroud.email/issues/223)) ([7b8d25c](https://github.com/Shroud-email/shroud.email/commit/7b8d25c5eb6a2ffc55152174267262d3047ba4b6))
* limit email privacy processing to two seconds ([6d87984](https://github.com/Shroud-email/shroud.email/commit/6d879844d02f9577737934d006b2bd1e40eaa1a8))
* load the HTML layout for error pages ([c4391e5](https://github.com/Shroud-email/shroud.email/commit/c4391e55a360ed68961407cd8d7e4e0c7fd43a6f))
* load the HTML layout for error pages ([2e653d3](https://github.com/Shroud-email/shroud.email/commit/2e653d3bc43faf63bb013ace83ab2dbbce4df3c6))
* log less data in analytics ([80141ee](https://github.com/Shroud-email/shroud.email/commit/80141eee8902ff0bc367b1bdd974a247c7ad38c3))
* make alias search literal and require every term ([#214](https://github.com/Shroud-email/shroud.email/issues/214)) ([0c284f8](https://github.com/Shroud-email/shroud.email/commit/0c284f8df04a9608ea273bf2d379f0858c704a5b))
* make orb setup complete reliably and reduce redundant work ([1018885](https://github.com/Shroud-email/shroud.email/commit/10188856ded1f14ec339ce30ca1a0d8a3d0a27fc))
* **mcp:** simplify app identity warning ([#236](https://github.com/Shroud-email/shroud.email/issues/236)) ([507d452](https://github.com/Shroud-email/shroud.email/commit/507d45241893c5965f726ee5399ffeb45d831172))
* prefill Paddle checkout customer email ([#210](https://github.com/Shroud-email/shroud.email/issues/210)) ([97b3efb](https://github.com/Shroud-email/shroud.email/commit/97b3efbf4c79f41b654e29ac4684a242c2deab45))
* preserve alias editor drafts during refresh ([2149860](https://github.com/Shroud-email/shroud.email/commit/2149860c38262cda57a0eea8c2ce3eac614d0f29))
* preserve OAuth MCP and passkey parameter redaction ([c900f4b](https://github.com/Shroud-email/shroud.email/commit/c900f4bf960e320613bb1a1e44e552393d8bb691))
* preserve pending TOTP settings across menu navigation ([4856e8d](https://github.com/Shroud-email/shroud.email/commit/4856e8dc693184337f827146c956976f182ccea5))
* prevent alias detail form recovery crashes ([a313f39](https://github.com/Shroud-email/shroud.email/commit/a313f39893afa46842f7b522c780d6cedb99d54f))
* prevent alias detail form recovery crashes ([e0bf316](https://github.com/Shroud-email/shroud.email/commit/e0bf3164f2df7222b9e5f69448f59d66f954ddcb))
* prevent trailing equals signs in forwarded emails ([622f1ab](https://github.com/Shroud-email/shroud.email/commit/622f1ab56e2bfa7b1f23dd374f14d394ba03f193))
* prevent unstyled page flashes in Firefox ([#218](https://github.com/Shroud-email/shroud.email/issues/218)) ([04dd7da](https://github.com/Shroud-email/shroud.email/commit/04dd7da691ec33a1a5ee66e3d16094aa47974fcf))
* properly handle OAuth MCP and passkey parameter redaction ([7a476d1](https://github.com/Shroud-email/shroud.email/commit/7a476d160b094734affc4822363e92448463124d))
* queue bounce notifications through the standard notifier ([9653ba1](https://github.com/Shroud-email/shroud.email/commit/9653ba1e917cd74207ab33352c7e6feead1b4d5c))
* reject Shroud-hosted account email addresses ([806f6eb](https://github.com/Shroud-email/shroud.email/commit/806f6eb9a0f9658dfe4df9971356c7f2e5f3d111))
* remove cross-site attribution ([73e3e02](https://github.com/Shroud-email/shroud.email/commit/73e3e02787f81825bedb951155909fffcfc818be))
* remove cross-site campaign attribution ([50dd996](https://github.com/Shroud-email/shroud.email/commit/50dd9967ecad56f68132d910e3899917ab892067))
* remove redundant signup success alert ([09c8f97](https://github.com/Shroud-email/shroud.email/commit/09c8f977e892e855564266fb1cc4e8156068d13f))
* report error logs to Sentry with email job IDs ([a6145d3](https://github.com/Shroud-email/shroud.email/commit/a6145d38f6df7fe57202a7685f9eb8b361cbacc4))
* report error logs to Sentry with email job IDs ([9836561](https://github.com/Shroud-email/shroud.email/commit/9836561562dee4efccdd614094b7ef4042eb9306))
* retain bounce archives and include their paths in Sentry ([ceda48a](https://github.com/Shroud-email/shroud.email/commit/ceda48aac7b0c8d58d5603fac0db3b9d18a9587f))
* safely log structured email delivery errors ([542dbeb](https://github.com/Shroud-email/shroud.email/commit/542dbeb738582c9b5b9b8f0ebea2eb21e8794ba3))
* show password reset feedback on authentication forms ([#199](https://github.com/Shroud-email/shroud.email/issues/199)) ([53fa580](https://github.com/Shroud-email/shroud.email/commit/53fa58097e0daeb72da605d154dbc79524c44321))
* show unverified domains in alias dropdown ([#227](https://github.com/Shroud-email/shroud.email/issues/227)) ([9db7b52](https://github.com/Shroud-email/shroud.email/commit/9db7b52ab9778b506244a256d8f49c0d78c03308))
* speed up orb Erlang setup ([#180](https://github.com/Shroud-email/shroud.email/issues/180)) ([4adebbd](https://github.com/Shroud-email/shroud.email/commit/4adebbd46d3e33c602393c856fd7f8ef8f58e0e7))
* stack alias controls on narrow screens ([473c5f8](https://github.com/Shroud-email/shroud.email/commit/473c5f8789a10251d1c06d741dd010e748b5777b))
* support long OAuth state values ([dbf71f2](https://github.com/Shroud-email/shroud.email/commit/dbf71f29aa9d7867da02f64fa50ba2c12959c416))
* support long OAuth state values ([afa3bcc](https://github.com/Shroud-email/shroud.email/commit/afa3bcca9d088d5206c893bd87e9d02b739ea1d7))
* suppress login error for root visits ([c15dbc2](https://github.com/Shroud-email/shroud.email/commit/c15dbc20eb3892df990a3407ef19edba52e5dbd3))
* upgrade mailex to prevent trailing equals signs in forwarded emails ([e9a6c0e](https://github.com/Shroud-email/shroud.email/commit/e9a6c0e0746d3a6c931aaf97afb38a0d5198d771))
* use alias as forwarding envelope sender ([14b494f](https://github.com/Shroud-email/shroud.email/commit/14b494f4ca32c8da88a6cd1d1582f97efd4e01b9))
* use alias as forwarding envelope sender ([6004899](https://github.com/Shroud-email/shroud.email/commit/60048996984affbe9c0698944a83eda7c64bbc15))
* use custom dialogs for all app alerts ([#230](https://github.com/Shroud-email/shroud.email/issues/230)) ([e695516](https://github.com/Shroud-email/shroud.email/commit/e6955160a7c396f89895c28f33fc691d24032e81))
* use LiveView navigation in navbar ([#179](https://github.com/Shroud-email/shroud.email/issues/179)) ([4adebbd](https://github.com/Shroud-email/shroud.email/commit/4adebbd46d3e33c602393c856fd7f8ef8f58e0e7))
* use pause-aware subscription downgrade emails ([04e47a0](https://github.com/Shroud-email/shroud.email/commit/04e47a0c92f99b2b30226ef8625147e038a4ad3d))
* use vgpu fog on error pages ([19360e3](https://github.com/Shroud-email/shroud.email/commit/19360e3a512257273b728af654c205c6bb0f5a98))
* validate custom-domain DMARC policies semantically ([3a24b36](https://github.com/Shroud-email/shroud.email/commit/3a24b369efd769ff9260f1b887946f9a9aba6da3))
* validate custom-domain DMARC policies semantically ([2022538](https://github.com/Shroud-email/shroud.email/commit/2022538a1a85281524c8adaaf98f3149b820ddf5))


### Reverts

* undo plausible ([#229](https://github.com/Shroud-email/shroud.email/issues/229)) ([5c8a36a](https://github.com/Shroud-email/shroud.email/commit/5c8a36a614b8a8dc3ff69a3da3beca1060da777d))

## [1.3.0](https://github.com/Shroud-email/shroud.email/compare/v1.2.0...v1.3.0) (2026-07-25)


### Features

* add Cap for bot prevention ([#167](https://github.com/Shroud-email/shroud.email/issues/167)) ([33d22d3](https://github.com/Shroud-email/shroud.email/commit/33d22d3c4f578eb24e78b3b4a4a3339bd42b2b7d))
* add dark mode support with system preference detection ([#111](https://github.com/Shroud-email/shroud.email/issues/111)) ([cc10ef5](https://github.com/Shroud-email/shroud.email/commit/cc10ef5abc5d5b6d57a4500c04c85df0530b4273))
* add live chat support widget ([#162](https://github.com/Shroud-email/shroud.email/issues/162)) ([6b9f76f](https://github.com/Shroud-email/shroud.email/commit/6b9f76fe8773b29ed28f8da871d86f393cc69ab4))
* add task to export failed emails for debugging ([#106](https://github.com/Shroud-email/shroud.email/issues/106)) ([b86bdd7](https://github.com/Shroud-email/shroud.email/commit/b86bdd75224c42105616b5ba36291eccc490e49b))
* replace 30-day trial with permanent free tier ([#112](https://github.com/Shroud-email/shroud.email/issues/112)) ([314318b](https://github.com/Shroud-email/shroud.email/commit/314318b6902bb3cf69ea0cfa38b77ede4881f6da))
* set up Sentry releases ([#143](https://github.com/Shroud-email/shroud.email/issues/143)) ([70265b2](https://github.com/Shroud-email/shroud.email/commit/70265b2e96d012e18ec8140b45c9fb6966afc7d3))
* track per-day counts of blocked tracking domains ([#140](https://github.com/Shroud-email/shroud.email/issues/140)) ([183d00c](https://github.com/Shroud-email/shroud.email/commit/183d00ca0cb72589078e3c9c1047e5a8877f349a))
* use mailex (experimental) ([#105](https://github.com/Shroud-email/shroud.email/issues/105)) ([6053f09](https://github.com/Shroud-email/shroud.email/commit/6053f09747bb6ee6208c4a9bb63ef04d1ee91c05))


### Bug Fixes

* add dark mode support to email report page ([#113](https://github.com/Shroud-email/shroud.email/issues/113)) ([2fa4654](https://github.com/Shroud-email/shroud.email/commit/2fa465419e07c394f1374d3507734ad42694bb27))
* add Oban v14 migration for missing 'suspended' enum value ([#142](https://github.com/Shroud-email/shroud.email/issues/142)) ([1fdd010](https://github.com/Shroud-email/shroud.email/commit/1fdd010c57df750de2b5e461433238b8d9592a46))
* align templates with AGENTS.md guidelines ([#147](https://github.com/Shroud-email/shroud.email/issues/147)) ([3025b8a](https://github.com/Shroud-email/shroud.email/commit/3025b8a211e93830a312de055ec2243bc8c67026))
* always return noreply from delete/block_sender handle_event ([#150](https://github.com/Shroud-email/shroud.email/issues/150)) ([f13f6c0](https://github.com/Shroud-email/shroud.email/commit/f13f6c010747e2a00de9ae3dbd19ff5c2098f20d))
* decode legacy-charset email headers to prevent SMTP encode crash ([#141](https://github.com/Shroud-email/shroud.email/issues/141)) ([247efe3](https://github.com/Shroud-email/shroud.email/commit/247efe36f3568f31c451f3594bdb5689208db915))
* deduplicate trackers in email reports ([#131](https://github.com/Shroud-email/shroud.email/issues/131)) ([b9b1f80](https://github.com/Shroud-email/shroud.email/commit/b9b1f80de883b1aced1e9526d254780f9c66e466)), closes [#20](https://github.com/Shroud-email/shroud.email/issues/20)
* fix KeyError when checking for admin ([#96](https://github.com/Shroud-email/shroud.email/issues/96)) ([08797de](https://github.com/Shroud-email/shroud.email/commit/08797de6b1add0fdafa4fcaed74be5f021a430b4))
* handle empty reply-to headers ([#107](https://github.com/Shroud-email/shroud.email/issues/107)) ([10fd0ec](https://github.com/Shroud-email/shroud.email/commit/10fd0eca7076553c668a4b47ade92bc4e0ac9010))
* handle invalid bracket domains in email addresses ([#109](https://github.com/Shroud-email/shroud.email/issues/109)) ([75ea13b](https://github.com/Shroud-email/shroud.email/commit/75ea13b75705a400e760e17a4b0f4a7618e211aa))
* handle invalid emails with spaces in local part ([#104](https://github.com/Shroud-email/shroud.email/issues/104)) ([36df157](https://github.com/Shroud-email/shroud.email/commit/36df157b3db950c4deda5768ce9abe34484b531f))
* handle non-UTF8 bytes in incoming emails ([17bbdf8](https://github.com/Shroud-email/shroud.email/commit/17bbdf8f04c353843fd153b90b6c1c2f07691474))
* handle parentheses in sender name ([0189458](https://github.com/Shroud-email/shroud.email/commit/0189458632bef916816b398c88a0dbad49213df6))
* handle proxy network errors ([#165](https://github.com/Shroud-email/shroud.email/issues/165)) ([d58817f](https://github.com/Shroud-email/shroud.email/commit/d58817f8ec83ebb8decd700153bc04326e1f77c5))
* handle quotes in email addresses ([ed04f41](https://github.com/Shroud-email/shroud.email/commit/ed04f4141359f20ab78ce42b392a7f8e74a3ea8e))
* ignore TLS when relaying to haraka ([#100](https://github.com/Shroud-email/shroud.email/issues/100)) ([8187006](https://github.com/Shroud-email/shroud.email/commit/8187006d164ac356a6fd3f34058313eabcab93d9))
* interpolate token in password reset form action ([#148](https://github.com/Shroud-email/shroud.email/issues/148)) ([6e36943](https://github.com/Shroud-email/shroud.email/commit/6e369435b5094e14ca7df941f9b052a6c5bc1e34))
* make debug email page readable in dark mode ([#138](https://github.com/Shroud-email/shroud.email/issues/138)) ([669a874](https://github.com/Shroud-email/shroud.email/commit/669a874ed8992611539de2bfb3e58fcf1c2233dc))
* pass clipboard text via data attribute to prevent JS injection ([#152](https://github.com/Shroud-email/shroud.email/issues/152)) ([9bdd168](https://github.com/Shroud-email/shroud.email/commit/9bdd1689b2c92fffe589254a6675913a53a84c81))
* prevent ArgumentError when DISABLE_SIGNUPS env var is unset ([#159](https://github.com/Shroud-email/shroud.email/issues/159)) ([08ea6dc](https://github.com/Shroud-email/shroud.email/commit/08ea6dcd7c665b6284965a48523eb089ddfbbbd1))
* rebind socket so custom alias success flash is shown ([#151](https://github.com/Shroud-email/shroud.email/issues/151)) ([a78a4f3](https://github.com/Shroud-email/shroud.email/commit/a78a4f3056ecfed9be512c29b3adbfb26e083878))
* reject RFC-5322-invalid emails ([#170](https://github.com/Shroud-email/shroud.email/issues/170)) ([39df997](https://github.com/Shroud-email/shroud.email/commit/39df99759bd0fec1f67bdaaed57fb5d1a0518adc))
* render heroicon component for unverified domain indicator ([#149](https://github.com/Shroud-email/shroud.email/issues/149)) ([b32eaa5](https://github.com/Shroud-email/shroud.email/commit/b32eaa548a78202420781d00bca4b4d009791e31))
* return error when lifetime code redemption transaction fails ([#153](https://github.com/Shroud-email/shroud.email/issues/153)) ([e23a023](https://github.com/Shroud-email/shroud.email/commit/e23a0239d38254443dce8ec3aa04a1a8bf87ac89))
* revert gen_smtp update ([b84ca3d](https://github.com/Shroud-email/shroud.email/commit/b84ca3d079d4e27d59372981a462183ff56c7a81))
* serve digested favicon by allowing only_matching in Plug.Static ([#145](https://github.com/Shroud-email/shroud.email/issues/145)) ([bc055ad](https://github.com/Shroud-email/shroud.email/commit/bc055add226322cebde370c6ef2a5d1aed563854))
* stop EmailAlias.changeset from mass-assigning user_id ([#155](https://github.com/Shroud-email/shroud.email/issues/155)) ([f4b49bf](https://github.com/Shroud-email/shroud.email/commit/f4b49bf648682f541545b4dc39f65e7318317b59))
* stop enqueuing DnsChecker jobs inside a streaming transaction ([#136](https://github.com/Shroud-email/shroud.email/issues/136)) ([e4f9997](https://github.com/Shroud-email/shroud.email/commit/e4f999703dbebfee6604addb58688b25d8616d41))
* strip double quotes from parsed email addresses ([#139](https://github.com/Shroud-email/shroud.email/issues/139)) ([dc44cd4](https://github.com/Shroud-email/shroud.email/commit/dc44cd4035abb54ab8cde1b4dd53ab8ce5d20f7a))
* strip XML processing instructions in SpamEmailScrubber ([#158](https://github.com/Shroud-email/shroud.email/issues/158)) ([165d178](https://github.com/Shroud-email/shroud.email/commit/165d17852f1e75d5037e9e81ff351b074c75b6e7))
* switch from emailoctopus to loops ([#101](https://github.com/Shroud-email/shroud.email/issues/101)) ([9fb17e8](https://github.com/Shroud-email/shroud.email/commit/9fb17e84be161fd68f88bd2a01fc4b39d952929f))
* use mailex to parse emails in spam check ([#108](https://github.com/Shroud-email/shroud.email/issues/108)) ([2e294dd](https://github.com/Shroud-email/shroud.email/commit/2e294ddb9faa4fa5139e4de5ee2e503d2c1e5a09))
* use the release input for the sentry-release action ([#144](https://github.com/Shroud-email/shroud.email/issues/144)) ([8217d14](https://github.com/Shroud-email/shroud.email/commit/8217d14a80d887f657b0cb2ae363099de7ae5943))

## [1.2.0](https://github.com/Shroud-email/shroud.email/compare/v1.1.1...v1.2.0) (2025-03-23)


### Features

* add debug view for admins ([07ff176](https://github.com/Shroud-email/shroud.email/commit/07ff1761efb0c4e73e8857415e8b98c4fed924aa))
* **api:** API Endpoint to delete Alias ([#84](https://github.com/Shroud-email/shroud.email/issues/84)) ([2dc1caa](https://github.com/Shroud-email/shroud.email/commit/2dc1caa308918586a070ee050beb129ad7d66e76))
* store spamassassin headers ([#87](https://github.com/Shroud-email/shroud.email/issues/87)) ([b3364dd](https://github.com/Shroud-email/shroud.email/commit/b3364dde6950b434498a60784ea1e9395e1c9a0f))

## [1.1.1](https://github.com/Shroud-email/shroud.email/compare/v1.1.0...v1.1.1) (2023-11-07)


### Bug Fixes

* fix config error ([c46d7c8](https://github.com/Shroud-email/shroud.email/commit/c46d7c8c657b7ff79d401640a3ed0ed8be7c3fb6))

## [1.1.0](https://github.com/Shroud-email/shroud.email/compare/v1.0.3...v1.1.0) (2023-11-06)


### Features

* add ability to disable signups ([#78](https://github.com/Shroud-email/shroud.email/issues/78)) ([43d002a](https://github.com/Shroud-email/shroud.email/commit/43d002afd379f7bcdb5d32335178531d42166daa))

## [1.0.3](https://github.com/Shroud-email/shroud.email/compare/v1.0.2...v1.0.3) (2023-07-01)


### Miscellaneous Chores

* release 1.0.3 ([4b979c8](https://github.com/Shroud-email/shroud.email/commit/4b979c826ecefe205997d960cd23c01c7f817ca2))

## [1.0.2](https://github.com/Shroud-email/shroud.email/compare/v1.0.1...v1.0.2) (2023-06-29)


### Bug Fixes

* **emails:** move shroud.email notice to bottom of emails ([e575553](https://github.com/Shroud-email/shroud.email/commit/e575553d2e9d702f8c6ef76214fc72641b0899a0))

## [1.0.1](https://github.com/Shroud-email/shroud.email/compare/v1.0.0...v1.0.1) (2023-03-25)


### Bug Fixes

* **domains:** fix "add domain" button ([4ceef00](https://github.com/Shroud-email/shroud.email/commit/4ceef001daecea4afff5268d3a3916266ad9ff59))

## [1.0.0](https://github.com/Shroud-email/shroud.email/compare/v0.2.4...v1.0.0) (2023-03-11)


### ⚠ BREAKING CHANGES

* **aliases:** admins must manually run the `make_emails_case_insensitive` command before deploying this.

### Features

* **aliases:** use citext column for alias addresses ([#53](https://github.com/Shroud-email/shroud.email/issues/53)) ([8e7800a](https://github.com/Shroud-email/shroud.email/commit/8e7800a9a77827224527a6e231f0d76695697b06))

## [0.2.4](https://github.com/Shroud-email/shroud.email/compare/v0.2.2...v0.2.4) (2023-03-11)


### Miscellaneous Chores

* **main:** release 0.2.3 ([#58](https://github.com/Shroud-email/shroud.email/issues/58)) ([121ac5b](https://github.com/Shroud-email/shroud.email/commit/121ac5be666c95762a26fff4ad3fba4f019a9dbf))


### Continuous Integration

* only deploy on new tags ([10c94df](https://github.com/Shroud-email/shroud.email/commit/10c94df28bd54f88a81015bcf43c695c81abbaae))
* use different token to create releases ([c1a10df](https://github.com/Shroud-email/shroud.email/commit/c1a10df55286257a1e50c7588b0c5caef901377e))

## [0.2.3](https://github.com/Shroud-email/shroud.email/compare/v0.2.2...v0.2.3) (2023-03-11)


### Continuous Integration

* only deploy on new tags ([10c94df](https://github.com/Shroud-email/shroud.email/commit/10c94df28bd54f88a81015bcf43c695c81abbaae))

## [0.2.2](https://github.com/Shroud-email/shroud.email/compare/v0.2.1...v0.2.2) (2023-03-11)


### Continuous Integration

* fix releasing semver images ([43d0509](https://github.com/Shroud-email/shroud.email/commit/43d0509c7274a37fdebe500217a1e7182c9ab84e))

## [0.2.1](https://github.com/Shroud-email/shroud.email/compare/v0.2.0...v0.2.1) (2023-03-11)


### Continuous Integration

* deploy on new tags ([9d40c4f](https://github.com/Shroud-email/shroud.email/commit/9d40c4f8f670b57a0518782803ce9af660d8af1b))

## [0.2.1](https://github.com/Shroud-email/shroud.email/compare/v0.2.0...v0.2.1) (2023-03-11)


### Continuous Integration

* deploy on new tags ([9d40c4f](https://github.com/Shroud-email/shroud.email/commit/9d40c4f8f670b57a0518782803ce9af660d8af1b))

## [0.2.0](https://github.com/Shroud-email/shroud.email/compare/v0.1.0...v0.2.0) (2023-03-11)


### Features

* **aliases:** add command to deduplicate aliases with different cases ([b9d82a5](https://github.com/Shroud-email/shroud.email/commit/b9d82a5b2e0cf5ec28c9215f7210ca637ab188d0))


### Bug Fixes

* **aliases:** ensure we don't create more duplicate aliases ([1f319c8](https://github.com/Shroud-email/shroud.email/commit/1f319c80029ebd8be9ae0437335b23646e3c234a))

## 0.1.0 (2023-03-05)


### Build System

* set up release-please ([#50](https://github.com/Shroud-email/shroud.email/issues/50)) ([2cd7097](https://github.com/Shroud-email/shroud.email/commit/2cd7097b58389549f9bcd0a583a44e4a49a63b96))
