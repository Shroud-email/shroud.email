exports.hook_bounce = (next, _hmail, error) => {
  this.logwarn(`Bounced message: ${error}`);
  return next()
}
