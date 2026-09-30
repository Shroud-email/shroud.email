exports.hook_bounce = function (next, _hmail, error) {
  this.logwarn(`Bounced message: ${error}`);
  return next()
}
