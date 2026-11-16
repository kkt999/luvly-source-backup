import { HttpError } from './payment_service.mjs';
const active = actor => actor?.active === true && ['staff','manager'].includes(actor.role);
const safeText = (value, max = 150) => typeof value === 'string' ? value.slice(0,max) : '';
const day = value => typeof value === 'string' && /^\d{4}-\d\d-\d\d$/.test(value);

export class DirectoryService {
  constructor({store,access}) {Object.assign(this,{store,access});}
  async list(uid,kind) {
    if(!['customers','staff'].includes(kind))throw new HttpError(400,'INVALID_DIRECTORY_QUERY');
    const access=await this.access(uid);
    if(!['staff','manager'].includes(access.role) || kind==='staff' && access.role!=='manager')throw new HttpError(403,'DIRECTORY_ACCESS_REQUIRED');
    const snapshot=await this.store.directorySnapshot(uid,kind);
    if(!active(snapshot.actor) || kind==='staff' && snapshot.actor.role!=='manager')throw new HttpError(403,'DIRECTORY_ACCESS_REQUIRED');
    if(snapshot.limited)throw new HttpError(409,'DIRECTORY_LIMIT');
    const manager=snapshot.actor.role==='manager';
    if(kind==='staff')return {records:snapshot.profiles.map(p=>({
      id:p.id,name:safeText(p.name,100),email:safeText(p.email,254),phone:safeText(p.phone,25),
      role:['staff','manager'].includes(p.role)?p.role:'unassigned',active:p.active===true,
    })).sort((a,b)=>a.name.localeCompare(b.name)),limited:false};
    const assigned=new Set(snapshot.appointments.filter(a=>snapshot.frontDesk===true||a.assignedStaffId===uid).map(a=>a.uid));
    const profiles=snapshot.profiles.filter(p=>manager || assigned.has(p.id));
    return {records:profiles.map(p=>({id:p.id,name:safeText(p.name,100),email:safeText(p.email,254),phone:safeText(p.phone,25),
      eventDates:[...new Set(snapshot.plans.filter(s=>s.uid===p.id && day(s.rentalPlan?.eventDate)).map(s=>s.rentalPlan.eventDate))].sort(),
    })).sort((a,b)=>a.name.localeCompare(b.name)),limited:false};
  }
}
