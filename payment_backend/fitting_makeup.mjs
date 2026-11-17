import {hasBoutiqueOperationsAccess,activeEmployee} from './appointment_access.mjs';
import {malaysiaDay} from './booking_dates.mjs';
import {HttpError} from './payment_service.mjs';
import {makeupTrial,offersService} from './workforce.mjs';

const id=value=>typeof value==='string'&&/^[A-Za-z0-9_-]{1,150}$/.test(value);
const validDay=day=>typeof day==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(day)&&
  malaysiaDay(Date.parse(day+'T00:00:00+08:00'))===day;
const eventDay=selection=>selection.rentalPlan?.eventDate;
const reject=code=>{throw new HttpError(409,code);};
const timestamp=value=>value?.toMillis?.()??(value==null?NaN:+value);
const visitRevision=visit=>Number.isSafeInteger(visit.revision)?visit.revision:0;
const typeOf=service=>service.serviceType??service.id;
const names={'makeup-hair':'Wedding-day makeup & hair','makeup-trial':'Pre-wedding makeup & hair trial'};
export const makeupName=service=>names[typeOf(service)]??service.name;

async function artistName(tx,uid,staff) {
  const name=typeof staff?.name==='string'?staff.name.trim():'';
  if(!activeEmployee(staff)||!name||!offersService(await tx.get(`staffScheduling/${uid}`),makeupTrial))return null;
  return name.slice(0,100);
}

function trialSlot(visit,selection) {
  const start=timestamp(visit?.startAt), day=malaysiaDay(start);
  if(!visit||visit.uid!==selection.uid||visit.type!==makeupTrial||
      !['Confirmed','Completed'].includes(visit.status)||!id(visit.assignedStaffId)||
      !day||!validDay(eventDay(selection))||day>=eventDay(selection))return null;
  const minute=Math.floor(start/60000)+8*60;
  return {day,minuteOfDay:((minute%1440)+1440)%1440,artistId:visit.assignedStaffId};
}

export async function fittingMakeupOptions(workflow,uid,selectionId) {
  return workflow.store.atomic(async tx=>{
    const staff=await tx.get(`staff/${uid}`), selection=await tx.get(`packageSelections/${selectionId}`);
    if(!await hasBoutiqueOperationsAccess(tx,uid,staff))throw new HttpError(403,'OPERATIONS_ACCESS_REQUIRED');
    if(!selection)throw new HttpError(404,'SELECTION_ACCESS_DENIED');
    const services=(selection.services??[]).map(typeOf);
    if(!services.some(type=>type==='makeup-hair'||type==='makeup-trial'))return {artists:[],trials:[]};
    const roster=await tx.staffRoster();
    if(roster.length>100)reject('SCHEDULE_LIMIT');
    const artists=(await Promise.all(roster.map(async person=>{
      const name=await artistName(tx,person.id,person);
      return name?{id:person.id,name}:null;
    }))).filter(Boolean).sort((a,b)=>a.name.localeCompare(b.name));
    const namesById=new Map(artists.map(artist=>[artist.id,artist.name]));
    const trials=services.includes('makeup-trial') ?
      (await tx.makeupTrialAppointments(selection.uid)).flatMap(visit=>{
        const slot=trialSlot(visit,selection);
        const name=namesById.get(slot?.artistId);
        return name?[{id:visit.id,...slot,artistName:name,revision:visitRevision(visit)}]:[];
      }).sort((a,b)=>a.day.localeCompare(b.day)||a.minuteOfDay-b.minuteOfDay) : [];
    return {artists,trials};
  });
}

export function validServiceConfirmation(row) {
  if(!row||Array.isArray(row)||!id(row.serviceId))return false;
  const fields=Object.keys(row);
  if(fields.length===2 && typeof row.timing==='string')
    return row.timing.trim().length>=8&&row.timing.length<=180;
  if(fields.length===3&&id(row.appointmentId)&&Number.isSafeInteger(row.appointmentRevision)&&
      row.appointmentRevision>=0)return true;
  return [3,4].includes(fields.length)&&fields.every(key=>
    ['serviceId','artistId','minuteOfDay','day'].includes(key))&&id(row.artistId)&&
    Number.isInteger(row.minuteOfDay)&&row.minuteOfDay>=0&&row.minuteOfDay<1440&&
    (row.day===undefined||validDay(row.day));
}

export async function makeupConfirmation(tx,selection,service,row) {
  const type=typeOf(service);
  if(type!=='makeup-hair'&&type!=='makeup-trial')reject('PACKAGE_SERVICE_TIMING_REQUIRED');
  const event=eventDay(selection);
  if(!validDay(event))reject('PACKAGE_SERVICE_TIMING_REQUIRED');
  let schedule;
  if(row.appointmentId){
    if(type!=='makeup-trial')reject('PACKAGE_SERVICE_TIMING_REQUIRED');
    const visit=await tx.get(`appointments/${row.appointmentId}`);
    schedule=trialSlot(visit,selection);
    if(!schedule||visitRevision(visit)!==row.appointmentRevision)reject('PACKAGE_MAKEUP_TRIAL_CHANGED');
    schedule.appointmentId=row.appointmentId;
    schedule.appointmentRevision=row.appointmentRevision;
  }else{
    if(type==='makeup-hair'? row.day!==undefined : !validDay(row.day)||row.day>=event)
      reject('PACKAGE_SERVICE_TIMING_REQUIRED');
    schedule={day:row.day??event,minuteOfDay:row.minuteOfDay,artistId:row.artistId};
  }
  const name=await artistName(tx,schedule.artistId,await tx.get(`staff/${schedule.artistId}`));
  if(!name)reject('PACKAGE_MAKEUP_ARTIST_UNAVAILABLE');
  const clock=`${String(Math.floor(schedule.minuteOfDay/60)).padStart(2,'0')}:${String(schedule.minuteOfDay%60).padStart(2,'0')}`;
  return {serviceId:service.id,name:makeupName(service),timing:`${schedule.day} · ${clock} MYT · ${name}`,schedule};
}

export async function checkMakeupTrialReferences(tx,selection) {
  for(const {schedule} of selection.fittingQuote?.servicePlan??[]){
    if(!schedule?.appointmentId)continue;
    const actual=trialSlot(await tx.get(`appointments/${schedule.appointmentId}`),selection);
    if(!actual||actual.artistId!==schedule.artistId||actual.day!==schedule.day||
        actual.minuteOfDay!==schedule.minuteOfDay)reject('PACKAGE_MAKEUP_TRIAL_CHANGED');
  }
}
