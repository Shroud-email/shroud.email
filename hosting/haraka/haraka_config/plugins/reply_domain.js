"use strict";

// The service-owned reply namespace does not grant SMTP relay privileges.
module.exports = function replyDomain(domain) {
  const emailDomain = process.env.EMAIL_DOMAIN?.toLowerCase();
  if (!emailDomain) return false;
  const root = `reply.${emailDomain}`;
  const host = domain.toLowerCase();
  return host === root || host.endsWith(`.${root}`);
};
