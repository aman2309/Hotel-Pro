/** Add one calendar year in UTC. 29 February becomes 28 February. */
function addOneCalendarYear(date) {
  const year = date.getUTCFullYear() + 1;
  const month = date.getUTCMonth();
  let day = date.getUTCDate();
  if (month === 1 && day === 29) day = 28;
  return new Date(Date.UTC(
    year,
    month,
    day,
    date.getUTCHours(),
    date.getUTCMinutes(),
    date.getUTCSeconds(),
    date.getUTCMilliseconds(),
  ));
}

module.exports = {addOneCalendarYear};

/** Add calendar months in UTC, clamping to the target month's last day. */
function addCalendarMonths(date, months) {
  if (!Number.isInteger(months) || months < 1 || months > 1200) throw Error('INVALID_DURATION');
  const target = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + months, 1));
  const last = new Date(Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0)).getUTCDate();
  target.setUTCDate(Math.min(date.getUTCDate(), last));
  target.setUTCHours(date.getUTCHours(), date.getUTCMinutes(), date.getUTCSeconds(), date.getUTCMilliseconds());
  return target;
}
module.exports.addCalendarMonths = addCalendarMonths;
