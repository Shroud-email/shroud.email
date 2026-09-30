---
title: Moving to our own mailserver
description: Fewer third parties = greater privacy
date: 2022-07-13
image: ../../assets/blog/man-postbox.jpg
imageAlt: a man delivering letters
---

When we started working on Shroud.email, we wanted to get up and running quickly with a great UX. I had heard of the challenges of self-hosting your own mailserver and the amount of work needed to keep your emails out of the spam folder. In order to allow us to focus on building the core product, we decided to use [MailPace](https://mailpace.com/) to deliver our emails.

This worked great. Our emails were always delivered safely, and MailPace has a lot in common with Shroud.email: we're both focused on privacy, hosted in the EU on renewable energy, and are small, independent businesses. However, as much as we're fans of theirs, our goal was always to run our own mailserver. Today, we've removed MailPace from our product and from our [privacy notice](/privacy/).

For a privacy-focused product like ours, we want to minimize the number of third parties we use. For such a core part of our infrastructure -- the mailserver that actually forwards your emails -- this is especially important. For the last few days, all emails forwarded by Shroud.email have been delivered directly by ourselves with no middle-men.

## Spam prevention

Getting to this point required quite a bit of work. Apart from setting up and securing the mailserver (and making it easily [self-hostable](/docs/deployment/self-host/)), we had to consider the risk that someone would start using our service to send spam emails. This would harm our IP's reputation as an email sender, negatively affecting all our users.

To avoid this, we added a new feature to Shroud.email -- spam detection. We now block any spam emails that are sent to or from an email alias. If a spammer sends spam to one of your email aliases, we won't forward it to your mailbox. Instead, you'll be able to view the blocked email in our web app for 7 days before it's deleted permanently. There, you can take quick actions such as blocking the sender, disabling the alias, or just deleting the email. Read more about how we handle spam [here](/docs/product/spam/).

Though we no longer use MailPace, we highly recommend them. We're excited about this step for Shroud.email -- please reach out if you have any issues with email deliverability.
