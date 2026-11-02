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
