import {HttpError} from './payment_service.mjs';
import {analyticsDay,analyticsMillis} from './analytics.mjs';
import {fittingFitsRental,effectiveVisitTime} from './booking_dates.mjs';
import {fittingPresentation} from './fitting_proposals.mjs';
import {finalFittingComplete} from './final_fitting.mjs';
const DAY=86400000;
const day=v=>typeof v==='string'&&/^\d{4}-\d\d-\d\d$/.test(v)&&Number.isFinite(Date.parse(v+'T00:00:00Z'))&&new Date(v+'T00:00:00Z').toISOString().slice(0,10)===v;
const cents=v=>Number.isSafeInteger(v)&&v>=0&&v<=100000000;
const text=(v,fallback='')=>typeof v==='string'?v:fallback;
const step=(key,title,state,detail)=>({key,title,state,detail});
const action=(type,title,detail,targetId=null)=>({type,title,detail,targetId});
const paid=(i,now)=>i?.state==='SandboxPaid'&&i.environment==='sandbox'&&!i.reviewReason&&typeof i.invoiceNo==='string'&&!!i.invoiceNo.trim()&&analyticsMillis(i.paidAt)!==null&&analyticsMillis(i.paidAt)<=now;
function payment(i,now,{blocked=false}={}){
  if(!i)return {state:'NotIssued',amountCents:null,invoiceId:null,expiresAt:null};
  const expiresAt=analyticsMillis(i.holdExpiresAt);
  const state=i.reviewResolution?'Closed':i.environment!=='sandbox'||!cents(i.amountCents)||i.amountCents<100||i.reviewReason||i.state==='ReviewRequired'||(i.state==='SandboxPaid'&&!paid(i,now))?'NeedsReview'
    :paid(i,now)?'Paid':blocked||i.paymentBlocked||(expiresAt!==null&&expiresAt<=now)?'Expired'
    :i.state==='Pending'||i.state==='Creating'?'PendingVerification'
    :['Quoted','Unpaid'].includes(i.state)?'AwaitingPayment':'NeedsReview';
  return {state,amountCents:cents(i.amountCents)?i.amountCents:null,invoiceId:i.id,expiresAt};
}
function appointment(a,invoiceMap,now){
  const expiresAt=analyticsMillis(a.paymentExpiresAt),startAt=analyticsMillis(effectiveVisitTime(a));
  const fee=invoiceMap.get(a.fittingInvoiceId);
  const fittingPayment=payment(fee?.appointmentId===a.id&&fee.purpose==='FittingFee'?fee:null,now,
    {blocked:!['AwaitingPayment','Confirmed','Completed'].includes(a.status)});
  return {id:a.id,type:text(a.type,'Appointment'),startAt,
    status:a.status==='AwaitingPayment'&&(expiresAt===null||expiresAt<=now)?'Expired':text(a.status,'NeedsReview'),
    expiresAt,fittingPayment};
}
export function customerPlanning(data,uid,now){
  // Defence in depth: never trust a store implementation to return only this owner.
  const own=key=>(data[key]??[]).filter(row=>row.uid===uid);
  const invoices=own('sandboxInvoices'),invoiceMap=new Map(invoices.map(i=>[i.id,i]));
  const rentals=new Map(own('rentals').map(r=>[r.id,r]));
  const serviceProgress=new Map((data.rentalServiceProgress??[]).map(p=>[p.selectionId,p]));
  const appointments=own('appointments').map(a=>appointment(a,invoiceMap,now));
  const rawAppointments=new Map(own('appointments').map(a=>[a.id,a]));
  const appointmentMap=new Map(appointments.map(a=>[a.id,a]));
  const today=analyticsDay(now);
  const plans=own('packageSelections').map(s=>{
    const linked=rentals.get(s.rentalId),r=linked?.packageSelectionId===s.id?linked:null;
    const state=r?.state==='Held'&&(!Number.isFinite(r.expiresAt)||r.expiresAt<=now)?'Expired':text(r?.state,'NotReserved');
    const locked=state==='Locked',held=state==='Held';
    const collectedAt=analyticsMillis(r?.collectedAt),returnedAt=analyticsMillis(r?.returnedAt);
    const p=(r&&['Held','Locked','PaymentReview'].includes(state)?r:s.rentalPlan)??{};
    const validDates=day(p.pickupDate)&&day(p.eventDate)&&day(p.returnDate)&&p.pickupDate<=p.eventDate&&p.eventDate<=p.returnDate;
    const eventDate=validDates?p.eventDate:null,pickupDate=validDates?p.pickupDate:null,returnDate=validDates?p.returnDate:null;
    const linkedAppointments=(s.appointmentIds??[]).map(id=>appointmentMap.get(id)).filter(Boolean).sort((a,b)=>(b.startAt??0)-(a.startAt??0));
    const fittingDone=linkedAppointments.some(a=>a.type==='Dress Trial'&&a.status==='Completed'&&a.startAt!==null&&a.startAt<=now);
    const nextVisit=linkedAppointments.filter(a=>['Confirmed','AwaitingPayment'].includes(a.status)&&a.startAt>=now).sort((a,b)=>a.startAt-b.startAt)[0];
    const unsettledVisit=linkedAppointments.find(a=>a.status==='Confirmed'&&a.startAt<now);
    function invoiceFor(id,phase){
      const i=invoiceMap.get(id);
      if(!i||i.packageSelectionId!==s.id)return null;
      if(r && ['Deposit','Balance','Security'].includes(phase) && i.rentalId!==r.id)return null;
      if(phase==='Legacy'&&i.purpose!=='PackagePayment')return null;
      if(phase!=='Legacy'&&(i.paymentPhase!==phase||i.purpose!==({Deposit:'BookingDeposit',Balance:'PackageBalance',Security:'SecurityDeposit'})[phase]))return null;
      const expected=phase==='Legacy'?s.totalCents:r?.[({Deposit:'depositCents',Balance:'balanceCents',Security:'securityCents'})[phase]];
      if(!cents(expected)||expected!==i.amountCents)return null;
      return i;
    }
    const deposit=payment(invoiceFor(r?.invoiceId??s.invoiceId,r?'Deposit':'Legacy'),now,{blocked:!!r&&!held&&!locked});
    const balance=payment(invoiceFor(r?.balanceInvoiceId??s.balanceInvoiceId,'Balance'),now,{blocked:!locked||!!collectedAt});
    const security=payment(invoiceFor(r?.securityInvoiceId,'Security'),now,{blocked:!locked||!!collectedAt});
    const pendingExtension=r?.pendingExtension;
    const extensionInvoice=invoiceMap.get(pendingExtension?.invoiceId);
    const extension=payment(extensionInvoice?.purpose==='RentalExtension'&&extensionInvoice.rentalId===r?.id&&extensionInvoice.packageSelectionId===s.id&&extensionInvoice.extensionId===pendingExtension?.id&&extensionInvoice.amountCents===pendingExtension.amountCents?extensionInvoice:null,now,{blocked:!locked||!!collectedAt});
    if(r?.balanceCents===0)balance.state='NotRequired';
    if(r?.securityCents===0)security.state='NotRequired';
    const review=state==='PaymentReview'||!!r?.reviewReason||(s.rentalId&&!r)||
      (!!s.invoiceId&&!deposit.invoiceId)||(r&&(held||locked)&&!deposit.invoiceId)||
      (locked&&(deposit.state!=='Paid'||(r.balanceCents>0&&!balance.invoiceId)||(r.securityCents>0&&!security.invoiceId)))||
      (nextVisit?.status==='AwaitingPayment'&&!['AwaitingPayment','PendingVerification','Paid'].includes(nextVisit.fittingPayment.state))||
      (validDates&&linkedAppointments.some(a=>['Confirmed','Completed','AwaitingPayment','Requested'].includes(a.status)&&!fittingFitsRental(rawAppointments.get(a.id),p,now)))||
      (deposit.state==='Paid'&&!!r&&!locked)||[deposit,balance,security].some(p=>p.state==='NeedsReview')||(!!s.rentalPlan&&!validDates);
    const payable=p=>['AwaitingPayment','PendingVerification'].includes(p.state);
    const allPaid=['Paid','NotRequired'].includes(balance.state)&&['Paid','NotRequired'].includes(security.state)&&deposit.state==='Paid';
    const skip=s.fittingChoice?.mode==='SkipFitting'&&s.fittingChoice.accepted===true;
    const waiverApproved=skip&&s.fittingDecision?.mode==='Waived'&&s.fittingDecision.state==='Approved';
    const changes=s.fittingDecision?.state==='NeedsChanges';
    const fittingV2=s.fittingWorkflowVersion===2?fittingPresentation(s):null;
    const decisionState=s.fittingDecision?.state;
    const fittingState=changes?'ChangesRequired':waiverApproved?'Waived':skip?'WaiverRequested':fittingDone?'Completed':nextVisit?.type==='Bridal Consultation'?'ConsultationBooked':nextVisit?.status??(unsettledVisit?'AwaitingUpdate':'NotBooked');
    const returnState=returnedAt?'Returned':collectedAt?(returnDate&&returnDate<today?'Overdue':'AwaitingReturn'):'NotCollected';
    const progress=serviceProgress.get(s.id);
    const adjustmentsPending=locked&&r.fittingAdjustmentsRequired&&
      !(progress?.rentalId===r.id&&progress.alteration==='Completed');
    const finalFittingPending=locked&&!finalFittingComplete(r,progress);
    const pickupState=collectedAt?'Collected':locked&&allPaid&&!review&&!adjustmentsPending&&!finalFittingPending&&pickupDate===today?'ReadyForPickup':pickupDate&&pickupDate<today?'DatePassed':locked?'Scheduled':'NotReserved';
    let next;
    if(review)next=action('support','Ask our team to review this plan','Some saved rental or payment details need review. Do not make a duplicate payment.');
    else if(returnState==='Overdue')next=action('support','Arrange your overdue return',`Your return date was ${returnDate}. Please contact our team.`);
    else if(returnedAt)next=action('packages',r?.securityState==='RefundRecorded'?'Your rental is complete':'Return recorded · review your security deposit',
      r?.securityState==='RefundRecorded'?'Your refund has been recorded by our team. Contact Luvly if you need help confirming receipt.':r?.securityState==='RefundDue'?'Your return inspection is complete. The team is reviewing your security refund.':'View your return inspection and security-deposit outcome.',s.id);
    else if(collectedAt&&r.returnIssue?.state==='Open')next=action('support','Discuss your return inspection','The team recorded a return issue. Contact Luvly to agree the next steps; your return has not been marked complete.');
    else if(collectedAt)next=action('packages','Return your bridal items',returnDate?`Return by ${returnDate}. Completion appears after staff records the return.`:'Check the agreed return date with the team.',s.id);
    else if(held && payable(deposit))next=action('payments','Complete your booking deposit','Your items are temporarily held. Pay or check verification before the hold expires.',deposit.invoiceId);
    else if(state==='Expired'||state==='Cancelled')next=action('packages','Review your rental availability','The previous stock hold ended. Review dates and availability with the team before paying again.',s.id);
    else if(locked&&pendingExtension?.expiresAt>now&&payable(extension))next=action('payments','Review and pay your rental extension',`Requested pickup ${pendingExtension.pickupDate} · Return ${pendingExtension.returnDate}. Original dates remain until verified payment.`,extension.invoiceId);
    else if(locked&&payable(balance))next=action('payments','Settle your package balance','The package balance must be verified paid before pickup.',balance.invoiceId);
    else if(locked&&payable(security))next=action('payments','Pay your refundable security deposit','Security is separate from the package price and must be verified before pickup.',security.invoiceId);
    else if(locked&&!allPaid)next=action('support','Confirm your pickup payments','Some required payment details are unavailable. Contact the team instead of paying again.');
    else if(adjustmentsPending)next=action('packages','Your gown adjustments are in progress','Check your package for updates. The team needs to complete the agreed alterations before pickup.',s.id);
    else if(finalFittingPending)next=action('packages','Arrange your final fitting','The agreed alteration plan requires a final fit check before collection. Book a linked fitting with the team; it is included after reservation.',s.id);
    else if(locked)next=action(pickupState==='DatePassed'?'support':'packages',pickupState==='ReadyForPickup'?'Your pickup is scheduled for today':pickupState==='DatePassed'?'Contact us about your pickup':'Your gown is reserved',
      pickupDate?`Pickup ${pickupDate} · Return ${returnDate}. Staff records the actual handover.`:'Review your agreed collection arrangements.',s.id);
    else if(fittingV2&&decisionState==='Declined')next=action('packages','You chose not to proceed','No package deposit is issued. Your attended visit and payment history are kept.',s.id);
    else if(!validDates)next=action('packages','Set your rental dates','Add the event, pickup and return dates before booking a linked fitting.',s.id);
    else if(eventDate<today||pickupDate<today||(!skip&&!fittingDone&&pickupDate===today))next=action('support','Review your plan dates','The event or pickup date has arrived or passed. Ask the team about the next arrangement.');
    else if(fittingV2&&s.fittingDecision&&!fittingV2.fittingReady)next=action('packages',
      decisionState==='Declined'?'You chose not to proceed':decisionState==='Considering'?'Take your time to decide':decisionState==='Reselect'?'Explore another gown':fittingV2.fittingQuote?.state==='AwaitingCustomer'?'Review your fitting proposal':'Your selection needs team review',
      decisionState==='Declined'?'No package deposit is issued. Your attended visit stays in your history.':decisionState==='Considering'?'Your preferences are saved; stock is not reserved. Return to My packages when ready.':decisionState==='Reselect'?'Change your gown, size or accessories in My packages. Your attended fitting and eligible credit are kept.':fittingV2.fittingQuote?.state==='AwaitingCustomer'?'Review the selected items, adjustment details and final total before accepting.':'The team will assess your selection and any adjustments before you confirm the proposal.',s.id);
    else if(changes)next=action('packages','Review your gown selection','Staff recorded that changes are needed. Agree on the gown and size before confirming the rental.',s.id);
    else if(skip)next=action('packages',waiverApproved?'Ready for rental confirmation':'Your no-fitting request is under review',waiverApproved?'The team approved proceeding without a fitting. Stock is checked when the rental is confirmed; no items are reserved yet.':'The team will review your chosen gown, size and dates. No fitting fee is charged and inventory is not yet reserved.',s.id);
    else if(nextVisit?.status==='AwaitingPayment'&&payable(nextVisit.fittingPayment))next=action('payments','Confirm your fitting with payment','The fitting time is held until the payment deadline. A held time is not yet a confirmed visit.',nextVisit.fittingPayment.invoiceId);
    else if(nextVisit?.status==='AwaitingPayment')next=action('appointments','Your fitting confirmation is being checked','The payment record does not yet confirm the appointment. Check Bookings before making another payment.');
    else if(nextVisit)next=action('appointments',nextVisit.type==='Bridal Consultation'?'Your consultation is booked':'Your next fitting is booked','Review your appointment time and prepare for your visit.');
    else if(unsettledVisit)next=action('appointments','Your visit is awaiting an update','The appointment time has passed; completion must be recorded by staff.');
    else if(fittingDone)next=action('packages','Review the rental with our team','Your fitting is completed. Staff can confirm the selected gown, size and rental availability before issuing the booking deposit.',s.id);
    else if(deposit.state==='Paid')next=action('support','Payment recorded · rental needs confirmation','A payment record alone does not confirm that inventory is locked. Ask the team to confirm this plan.');
    else next=action('packages','Book your gown fitting','Choose a fitting before the event and pickup date.',s.id);
    return {
      id:s.id,name:text(s.name,'Bridal package'),createdAt:analyticsMillis(s.createdAt),totalCents:cents(fittingV2?.agreedTotalCents??s.totalCents)?(fittingV2?.agreedTotalCents??s.totalCents):null,
      eventDate,pickupDate,returnDate,daysToEvent:eventDate?Math.round((Date.parse(eventDate+'T00:00:00Z')-Date.parse(today+'T00:00:00Z'))/DAY):null,
      rentalState:state,needsReview:!!review,completed:!!returnedAt,deposit,balance,security,extension,additionalRentalPaidCents:cents(r?.extensionPaidCents)?r.extensionPaidCents:0,
      gowns:(s.selectedGowns??[]).map(g=>({name:text(g.name,'Selected gown'),size:text(g.size),colour:text(g.colour)})),
      accessoriesCount:Array.isArray(s.selectedAccessories)?s.selectedAccessories.length:0,
      appointmentIds:linkedAppointments.map(a=>a.id),nextVisit:nextVisit??null,
      steps:[
        step('selection','Package selection',(s.selectedGowns??[]).length?'Saved':'PackageSaved',(s.selectedGowns??[]).length?'Gown preferences saved. This is not a stock reservation.':'Package saved. Review My packages to choose your gown.'),
        step('dates','Rental dates',validDates?'Saved':'NotSet',validDates?`${pickupDate} → ${returnDate}`:'Set dates in My packages.'),
        step('fitting','Fitting arrangement',fittingState,changes?'Changes are needed before rental confirmation.':waiverApproved?'Customer chose no fitting; staff approved the request. No visit is recorded as completed.':skip?'Awaiting staff review of the customer’s no-fitting request.':fittingDone?'Staff recorded a completed Dress Trial.':nextVisit?'Open Bookings for the visit time and payment status.':'Arrange a fitting before pickup, or request to proceed without one.'),
        step('deposit','Booking deposit & reservation',review?'NeedsReview':locked?'Reserved':held?'Held':state==='Expired'?'Expired':state==='Cancelled'?'Cancelled':'NotReserved',locked?'Inventory is locked for the agreed rental period.':held?'Temporary hold only; verified deposit is required.':'Selecting a package does not reserve inventory.'),
        step('balance','Package balance',balance.state,'Balance and refundable security are separate payments.'),
        step('security','Refundable security',returnedAt?text(r?.securityState,'NeedsReview'):security.state,'Refunds follow return inspection; they are not automatic.'),
        step('pickup','Gown pickup',pickupState,collectedAt?'Staff recorded the handover.':adjustmentsPending?'Agreed alterations are still pending.':finalFittingPending?'Complete your final fitting before pickup.':pickupDate?`Agreed pickup: ${pickupDate}`:'Pickup has not been arranged.'),
        step('return','Return & inspection',returnState,returnedAt?'Staff recorded the return inspection.':returnDate?`Agreed return: ${returnDate}`:'The return date will follow your rental plan.'),
      ],nextAction:next,
    };
  }).sort((a,b)=>{
    const rank=p=>p.completed?5:p.steps.some(s=>s.state==='Overdue')?0:p.eventDate&&p.eventDate>=today?1:p.needsReview?2:!p.eventDate?3:4;
    const difference=rank(a)-rank(b);
    return difference || (rank(a)===1?a.eventDate.localeCompare(b.eventDate):(b.createdAt??0)-(a.createdAt??0)) || a.id.localeCompare(b.id);
  });
  const upcoming=appointments.filter(a=>a.startAt>=now&&['Confirmed','AwaitingPayment'].includes(a.status)).sort((a,b)=>a.startAt-b.startAt);
  const first=plans[0];
  const nextAction=first?.nextAction??(upcoming[0]?.status==='AwaitingPayment'&&['AwaitingPayment','PendingVerification'].includes(upcoming[0].fittingPayment.state)
    ?action('payments','Confirm your fitting with payment','Complete or verify the fitting fee before the hold expires.',upcoming[0].fittingPayment.invoiceId)
    :upcoming.length?action('appointments','Review your next appointment','Your next visit is shown in Bookings.')
    :action('packages','Start your bridal plan','Explore packages, choose your gown and plan your dates.'));
  return {uid,environment:'sandbox',timezone:'Asia/Kuala_Lumpur',generatedAt:now,today,
    plans,appointments:appointments.sort((a,b)=>(b.startAt??0)-(a.startAt??0)),nextAppointment:upcoming[0]??null,nextAction,
    warnings:{undatedAppointments:appointments.filter(a=>a.startAt===null).length,reviewPayments:invoices.filter(i=>payment(i,now).state==='NeedsReview').length}};
}
export class CustomerPlanningService{
  constructor({store,access,now=Date.now}){Object.assign(this,{store,access,now});}
  async get(uid){
    const actor=await this.access(uid);
    if(actor.role!=='bride')throw new HttpError(403,'BRIDE_REQUIRED');
    const data=await this.store.customerPlanningSnapshot(uid);
    if(data.limited)throw new HttpError(409,'PLANNING_LIMIT_REACHED');
    if((await this.access(uid)).role!=='bride')throw new HttpError(403,'BRIDE_REQUIRED');
    return customerPlanning(data,uid,this.now());
  }
}
