import {hasBoutiqueOperationsAccess} from './appointment_access.mjs';
import {HttpError} from './payment_service.mjs';
import {effectiveVisitTime} from './booking_dates.mjs';

const DAY=86400000, MYT=8*3600000;
const fail=(ok,code,status=400)=>{if(!ok)throw new HttpError(status,code);};
export const analyticsDay=ms=>new Date(ms+MYT).toISOString().slice(0,10);
export function analyticsMillis(value){
  const ms=value?.toMillis?.() ?? (value instanceof Date?+value:value);
  return typeof ms==='number' && Number.isFinite(ms) ? ms : null;
}
const validDay=v=>typeof v==='string'&&/^\d{4}-\d\d-\d\d$/.test(v)&&Number.isFinite(Date.parse(v+'T00:00:00Z'))&&new Date(v+'T00:00:00Z').toISOString().slice(0,10)===v;
export function analyticsRange(input,now){
  fail(input && Object.keys(input).every(k=>['from','to'].includes(k)),'INVALID_REPORT_RANGE');
  const to=input.to ?? analyticsDay(now),from=input.from ?? analyticsDay(now-29*DAY);
  fail(validDay(from)&&validDay(to)&&from>='2020-01-01'&&from<=to&&to<=analyticsDay(now),'INVALID_REPORT_RANGE');
  const start=Date.parse(from+'T00:00:00Z')-MYT,end=Date.parse(to+'T00:00:00Z')-MYT+DAY;
  fail(end-start<=366*DAY,'REPORT_RANGE_TOO_LONG');
  return {from,to,start,end,days:(end-start)/DAY};
}
const amount=v=>Number.isSafeInteger(v)&&v>0&&v<=100000000;
const servicePurposes=new Set(['FittingFee','BookingDeposit','PackageBalance','PackagePayment','DressPayment','RentalExtension']);
const names={FittingFee:'Fitting fee',BookingDeposit:'Booking deposit',PackageBalance:'Package balance',PackagePayment:'Legacy package payment',DressPayment:'Dress payment',RentalExtension:'Additional rental days',SecurityDeposit:'Refundable security',Other:'Review / unclassified'};
const verified=i=>i.environment==='sandbox'&&i.state==='SandboxPaid'&&amount(i.amountCents)&&typeof i.invoiceNo==='string'&&!!i.invoiceNo.trim()&&analyticsMillis(i.paidAt)!==null;
const category=i=>!i.reviewReason&&!i.reviewResolution && servicePurposes.has(i.purpose)?i.purpose:!i.reviewReason&&!i.reviewResolution&&i.purpose==='SecurityDeposit'?'SecurityDeposit':'Other';
const pct=(a,b)=>b?Math.round(a*1000/b)/10:0;
const report=(id,title,basis,headers,rows,summary)=>({id,title,basis,headers,rows,summary});

export function operationSummary(data,now){
  const today=analyticsDay(now),appointments=data.appointments ?? [],rentals=data.rentals ?? [];
  const confirmed=appointments.filter(a=>a.status==='Confirmed'&&analyticsMillis(a.startAt)!==null);
  return {
    today,todayConfirmed:confirmed.filter(a=>analyticsDay(analyticsMillis(a.startAt))===today).length,
    awaitingPayment:appointments.filter(a=>a.status==='AwaitingPayment'&&analyticsMillis(a.paymentExpiresAt)>now).length,
    openConversations:(data.supportTickets??[]).filter(t=>t.status!=='Closed').length,
    activeHolds:rentals.filter(r=>r.state==='Held'&&r.expiresAt>now).length,
    overdueReturns:rentals.filter(r=>r.collectedAt&&!r.returnedAt&&validDay(r.returnDate)&&r.returnDate<today).length,
    upcoming:confirmed.filter(a=>analyticsMillis(a.startAt)>=now&&analyticsMillis(a.startAt)<now+7*DAY)
      .sort((a,b)=>analyticsMillis(a.startAt)-analyticsMillis(b.startAt)).slice(0,6)
      .map(a=>({id:a.id,name:typeof a.name==='string'?a.name:'Customer',type:a.type??'Appointment',startAt:analyticsMillis(a.startAt)})),
  };
}

export function calculateAnalytics(data,range,now){
  const {start,end,from,to,days}=range;
  const within=v=>{const ms=analyticsMillis(v);return ms!==null&&ms>=start&&ms<end&&ms<=now;};
  const invoices=data.sandboxInvoices??[],selections=data.packageSelections??[],appointments=data.appointments??[];
  const paidAll=invoices.filter(i=>verified(i)&&analyticsMillis(i.paidAt)<=now);
  const paid=paidAll.filter(i=>within(i.paidAt));
  const totals={grossCents:0,serviceCents:0,securityCents:0,otherCents:0,paidCount:paid.length,
    reviewCount:invoices.filter(i=>i.state==='ReviewRequired'||!!i.reviewReason).length};
  const buckets=Array.from({length:Math.min(days,days<=31?days:Math.ceil(days/7))},(_,index)=>({
    from:analyticsDay(start+index*(days<=31?DAY:7*DAY)),serviceCents:0,securityCents:0,otherCents:0,
  }));
  const mix=new Map(Object.keys(names).map(k=>[k,0]));
  const receiptDetails={service:[],security:[]};
  const customerNames=new Map((data.brides??[]).map(b=>[b.id,b.name??b.displayName??'Customer']));
  const receiptRows=paid.sort((a,b)=>analyticsMillis(b.paidAt)-analyticsMillis(a.paidAt)||a.id.localeCompare(b.id)).map(i=>{
    const kind=category(i),key=kind==='SecurityDeposit'?'securityCents':kind==='Other'?'otherCents':'serviceCents';
    totals.grossCents+=i.amountCents;totals[key]+=i.amountCents;mix.set(kind,mix.get(kind)+i.amountCents);
    const index=Math.floor((analyticsMillis(i.paidAt)-start)/(days<=31?DAY:7*DAY));
    buckets[index][key]+=i.amountCents;
    if(key!=='otherCents')receiptDetails[key==='securityCents'?'security':'service'].push({
      id:i.id,receipt:i.invoiceNo,customer:i.customerName??customerNames.get(i.uid)??'Customer',
      title:i.title??names[kind],category:names[kind],paidAt:analyticsMillis(i.paidAt),amountCents:i.amountCents,
    });
    return [i.invoiceNo,analyticsDay(analyticsMillis(i.paidAt)),names[kind],(i.amountCents/100).toFixed(2)];
  });
  const selected=selections.filter(s=>within(s.createdAt));
  const selectionMap=new Map(selections.map(s=>[s.id,s]));
  const packagePayments=paidAll.filter(i=>!i.reviewReason&&!i.reviewResolution&&['BookingDeposit','PackagePayment'].includes(i.purpose)&&
    selectionMap.get(i.packageSelectionId)?.uid===i.uid);
  const purchased=new Set(packagePayments.map(i=>i.packageSelectionId));
  const packageCounts=new Map();
  for(const s of selected){
    const key=typeof s.packageId==='string'?s.packageId:'unlinked';
    const row=packageCounts.get(key)??{id:key,name:s.name??'Archived / unlinked package',selections:0,paidBookings:0};
    row.selections++;if(purchased.has(s.id))row.paidBookings++;packageCounts.set(key,row);
  }
  const packages=[...packageCounts.values()].sort((a,b)=>b.selections-a.selections||a.name.localeCompare(b.name));
  const cohort=appointments.filter(a=>a.type==='Dress Trial'&&a.status==='Completed'&&within(effectiveVisitTime(a)));
  const latestPackagePayment=new Map();
  for(const i of packagePayments){
    const key=JSON.stringify([i.appointmentId,i.uid]);
    latestPackagePayment.set(key,Math.max(latestPackagePayment.get(key)??0,analyticsMillis(i.paidAt)));
  }
  const converted=cohort.filter(a=>(latestPackagePayment.get(JSON.stringify([a.id,a.uid]))??0)>=analyticsMillis(effectiveVisitTime(a)));
  const convertedIds=new Set(converted.map(a=>a.id));
  const statusOrder=['AwaitingPayment','Confirmed','Completed','Cancelled','Expired','Declined','Requested'];
  const periodAppointments=appointments.filter(a=>{const ms=analyticsMillis(effectiveVisitTime(a));return ms!==null&&ms>=start&&ms<end;});
  const statuses=statusOrder.map(status=>({label:status,count:periodAppointments.filter(a=>a.status===status).length}));
  const shapes=['Hourglass','Pear','Rectangle','Inverted Triangle','Oval'];
  const profiles=data.brides??[],customerIds=new Set(profiles.map(p=>p.id));
  const classified=[...new Map((data.bodyTypeSummaries??[])
    .filter(p=>customerIds.has(p.id)&&shapes.includes(p.bodyType)&&p.algorithmVersion==='style-rules-v1')
    .map(p=>[p.id,p])).values()];
  const bodyTypes=shapes.map(label=>({label,count:classified.filter(p=>p.bodyType===label).length}));
  const quality={paidMissingMetadata:invoices.filter(i=>i.state==='SandboxPaid'&&!verified(i)).length,
    selectionsMissingDate:selections.filter(s=>analyticsMillis(s.createdAt)===null).length,
    appointmentsMissingDate:appointments.filter(a=>analyticsMillis(a.startAt)===null).length,
    unclassifiedProfiles:profiles.length-classified.length};
  return {
    environment:'sandbox',timezone:'Asia/Kuala_Lumpur',generatedAt:now,range:{from,to},
    totals:{...totals,packageSelections:selected.length,paidPackageBookings:selected.filter(s=>purchased.has(s.id)).length,
      completedFittings:cohort.length,convertedFittings:converted.length,conversionPercent:pct(converted.length,cohort.length),
      appointments:periodAppointments.length,customers:profiles.length,classifiedProfiles:classified.length},
    operations:operationSummary(data,now),quality,trend:buckets,packages,statuses,bodyTypes,
    details:{
      service:{totalCents:totals.serviceCents,receipts:receiptDetails.service},
      security:{totalCents:totals.securityCents,receipts:receiptDetails.security},
      selections:selected.map(s=>({id:s.id,name:s.name??'Archived / unlinked package',customer:customerNames.get(s.uid)??'Customer',
        createdAt:analyticsMillis(s.createdAt),paidBooking:purchased.has(s.id)})),
      conversion:cohort.map(a=>({id:a.id,customer:a.name??customerNames.get(a.uid)??'Customer',
        attendedAt:analyticsMillis(effectiveVisitTime(a)),converted:convertedIds.has(a.id)})),
    },
    collectionMix:[...mix].filter(([,value])=>value>0).map(([id,cents])=>({label:names[id],cents})),
    reports:[
      report('packages','Package Popularity Report','Selections created in the selected MYT period. Paid bookings are distinct selections with a verified package deposit/payment as of generation; these are not stock reservations.',
        ['Package','Selections','Paid bookings','Share of selections'],packages.map(p=>[p.name,String(p.selections),String(p.paidBookings),pct(p.selections,selected.length)+'%']),
        `${selected.length} selections · ${selected.filter(s=>purchased.has(s.id)).length} paid bookings`),
      report('conversion','Appointment Conversion Report','Cohort: completed Dress Trial visits in the selected period, using actual attendance when recorded (otherwise the scheduled visit date). Converted means a verified linked package deposit/payment after the fitting, as of generation. No-fitting approvals are not completed visits.',
        ['Appointment ID','Fitting date (MYT)','Outcome'],cohort.map(a=>[a.id,analyticsDay(analyticsMillis(effectiveVisitTime(a))),convertedIds.has(a.id)?'Converted':'Not yet converted']),
        `${converted.length} / ${cohort.length} completed fittings converted · ${pct(converted.length,cohort.length)}%`),
      report('collections','Revenue Summary Report','Verified test payments by payment date (MYT), not accounting profit or recognised revenue. Pending/failed payments are excluded. Refundable security and review/unclassified receipts are separate from service collections. Fitting credit is not added again. Refund records are manual reconciliation notes, not verified gateway outflows, so no net-income claim is made.',
        ['Receipt','Paid date (MYT)','Collection category','Amount (RM)'],receiptRows,
        `Service collections RM${(totals.serviceCents/100).toFixed(2)} · Refundable security RM${(totals.securityCents/100).toFixed(2)} · Review / unclassified RM${(totals.otherCents/100).toFixed(2)}`),
      report('body-types','Body Type Distribution Report','Current snapshot, not date-filtered. Counts use only customers who opted to share their optional recommendation proportion guide. Categories follow style-rules-v1, not a body scan or verified fit assessment. Raw measurements and customer identities are not included. Private, withdrawn and legacy profiles are excluded from percentages.',
        ['Proportion guide','Participating profiles','Share of participating profiles'],bodyTypes.map(b=>[b.label,String(b.count),pct(b.count,classified.length)+'%']),
        `${classified.length} classified profiles · ${quality.unclassifiedProfiles} not classified`),
    ],
  };
}

export class AnalyticsService{
  constructor({store,access,now=Date.now}){Object.assign(this,{store,access,now});}
  async snapshot(uid,manager){
    const actor=await this.access(uid);
    fail(manager?actor.role==='manager':['staff','manager'].includes(actor.role),'MANAGER_REQUIRED',403);
    if (!manager) {
      fail(await hasBoutiqueOperationsAccess(this.store, uid, await this.store.get(`staff/${uid}`)),
        'OPERATIONS_ACCESS_REQUIRED',403);
    }
    const data=await this.store.analyticsSnapshot(manager);
    fail(!data.limited,'ANALYTICS_LIMIT_REACHED',409);
    const current=await this.access(uid);
    fail(current.role===actor.role,'ACCOUNT_ACCESS_REQUIRED',403);
    if (!manager && actor.role==='staff') {
      fail(await hasBoutiqueOperationsAccess(this.store, uid, await this.store.get(`staff/${uid}`)),
        'OPERATIONS_ACCESS_REQUIRED',403);
    }
    return data;
  }
  async report(uid,input){
    const now=this.now(),range=analyticsRange(input,now);
    return calculateAnalytics(await this.snapshot(uid,true),range,now);
  }
  async dashboard(uid){
    const now=this.now();
    return {environment:'sandbox',generatedAt:now,timezone:'Asia/Kuala_Lumpur',operations:operationSummary(await this.snapshot(uid,false),now)};
  }
}
