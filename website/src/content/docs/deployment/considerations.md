---
title: Considerations
description: Considerations when self-hosting Shroud.email.
---

If you'd like to self-host Shroud.email, you should keep in mind that running your own mailserver isn't always trivial.
You should ensure that the IP you host on is not on any blocklists, and that your SPF/DKIM/DMARC are configured correctly. Even then, it's not uncommon for emails from small mailservers to end up in spam.

You should also consider that when self-hosting, all your aliases will use your own domain which makes it easier to identify who you are.

All of this is to say that while it's definitely doable to self-host Shroud.email, you may or may not need to deal with email deliverability issues. If you'd like to skip this hassle, you can sign up for our hosted version of Shroud.email [here](https://app.shroud.email/users/register).
