import test from 'node:test';
import assert from 'node:assert/strict';
import {fittingBeforeRental,fittingFitsRental,malaysiaDay} from './booking_dates.mjs';
test('fitting is strictly before pickup and wedding using Malaysia date boundaries',()=>{
  const plan={pickupDate:'2026-10-19',eventDate:'2026-10-20'};
  assert.equal(fittingBeforeRental(Date.parse('2026-10-18T07:00:00Z'),plan),true);
  assert.equal(fittingBeforeRental(Date.parse('2026-10-19T02:00:00Z'),plan),false);
  assert.equal(fittingBeforeRental(Date.parse('2026-10-21T02:00:00Z'),plan),false);
  assert.equal(malaysiaDay(Date.parse('2026-10-18T16:00:00Z')),'2026-10-19');
  assert.equal(fittingBeforeRental(NaN,plan),false);
});

test('same-day pickup requires real completed attendance, never a confirmed visit or future completion',()=>{
  const now=Date.parse('2026-10-17T13:00:00Z'),plan={pickupDate:'2026-10-17',eventDate:'2026-10-29'};
  const booking={status:'Completed',startAt:new Date('2026-10-21T04:00:00Z'),actualAttendedAt:new Date('2026-10-17T06:40:00Z')};
  assert.equal(fittingFitsRental(booking,plan,now),true);
  for(const patch of [{status:'Confirmed'},{status:'Requested'},{actualAttendedAt:null},{actualAttendedAt:new Date(now+1)},{actualAttendedAt:new Date('invalid')}])
    assert.equal(fittingFitsRental({...booking,...patch},plan,now),false);
  assert.equal(fittingFitsRental(booking,{...plan,eventDate:'2026-10-17'},now),false);
  assert.equal(fittingFitsRental(booking,{...plan,pickupDate:'2026-10-16'},now),false);
  assert.equal(fittingFitsRental({...booking,actualAttendedAt:{toMillis:()=>+booking.actualAttendedAt}},plan,now),true);
});
