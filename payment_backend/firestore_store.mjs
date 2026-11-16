import { HttpError } from './payment_service.mjs';
import { finalFittingRequired } from './final_fitting.mjs';
import { activeEmployee, canViewAllAppointments } from './appointment_access.mjs';

export class FirestoreStore {
  constructor(database) { this.db = database; }
  async get(path) { return (await this.db.doc(path).get()).data(); }
  async pendingNotificationSources(uid) {
    const staff=(await this.db.doc(`staff/${uid}`).get()).data();
    const selectionQuery=this.db.collection('packageSelections').where(staff?'fittingQuote.by':'uid','==',uid).limit(501);
    const selections=await selectionQuery.get();
    if(selections.size>500)throw new HttpError(409,'NOTIFICATION_SOURCE_LIMIT');
    const paths=selections.docs.filter(d=>{
      const s=d.data();
      return !s.rentalId&&!s.invoiceId&&(staff
        ? ['Accepted','ChangesRequested','Considering','Declined'].includes(s.fittingQuote?.state)
        : s.fittingQuote?.state==='AwaitingCustomer');
    }).map(d=>`packageSelections/${d.id}`);
    if(!staff){
      const invoices=await this.db.collection('sandboxInvoices').where('uid','==',uid).limit(501).get();
      if(invoices.size>500)throw new HttpError(409,'NOTIFICATION_SOURCE_LIMIT');
      paths.push(...invoices.docs.filter(d=>{const r=d.data();return ['Quoted','AwaitingPayment'].includes(r.state)&&
        !r.paymentBlocked&&(!r.holdExpiresAt||r.holdExpiresAt>Date.now());}).map(d=>`sandboxInvoices/${d.id}`));
    }
    return paths;
  }
  async inboxPage(uid,cursor) {
    const collection=this.db.collection(`inboxes/${uid}/items`);
    let query=collection.orderBy('createdAt','desc');
    if(cursor){const doc=await collection.doc(cursor).get();if(!doc.exists)throw new HttpError(400,'INVALID_NOTIFICATION');query=query.startAfter(doc);}
    const [page,count]=await Promise.all([query.limit(51).get(),collection.where('readAt','==',null).count().get()]);
    const records=page.docs.slice(0,50).map(d=>({...d.data(),id:d.id}));
    return {records,unread:count.data().count,nextCursor:page.size>50?records.at(-1).id:null};
  }
  watchAnalytics(collection,changed,failed) {
    const allowed=['appointments','rentals','supportTickets','sandboxInvoices','packageSelections','brides','bodyTypeSummaries'];
    if(!allowed.includes(collection))throw new HttpError(400,'INVALID_REPORT_SOURCE');
    return this.db.collection(collection).limit(5001).onSnapshot(changed,failed);
  }
  async activeStaffIds() {
    return (await this.db.collection('staff').where('active','==',true).get()).docs
      .filter(d=>['staff','manager'].includes(d.data().role)).map(d=>d.id).sort();
  }
  async completedDressTrials(uid) {
    const snapshot=await this.db.collection('appointments').where('uid','==',uid)
      .select('uid','type','status','actualAttendedAt','fittingInvoiceId','refundReviewRequired','feeIncluded').limit(1001).get();
    if(snapshot.size>1000)throw new HttpError(409,'LIST_LIMIT');
    return snapshot.docs.map(doc=>({...doc.data(),id:doc.id}))
      .filter(visit=>visit.type==='Dress Trial'&&visit.status==='Completed');
  }
  async pendingBookingIds() {
    return (await this.db.collection('appointments').where('status','==','Requested').limit(100).get()).docs.map(d=>d.id);
  }
  async pendingFittingIds() {
    return (await this.db.collection('appointments').where('status','==','AwaitingPayment').get()).docs.map(d=>d.id);
  }
  async expiredRentalIds(now) {
    const snapshot = await this.db.collection('rentals').where('state', '==', 'Held').get();
    return snapshot.docs.filter(doc => doc.data().expiresAt <= now).map(doc => doc.id);
  }
  async expiredExtensionIds(now){
    const snapshot=await this.db.collection('rentalExtensions').where('state','==','AwaitingPayment').get();
    return snapshot.docs.filter(doc=>doc.data().expiresAt<=now).map(doc=>doc.id);
  }
  async activeRentalIds() {
    const snapshot=await this.db.collection('rentals').where('state','in',['Held','Locked']).get();
    return snapshot.docs.map(doc=>doc.id);
  }
  async listDresses() {
    const snapshot=await this.db.collection('dresses').where('published', '==', true).limit(1001).get();
    if(snapshot.docs.length>1000)throw new HttpError(409,'LIST_LIMIT');
    return snapshot.docs.map(doc => ({ ...doc.data(), id: doc.id }));
  }
  async list(collection, uid) {
    let query = this.db.collection(collection);
    if (uid !== undefined) query = query.where('uid', '==', uid);
    const snapshot=await query.limit(1001).get();
    if(snapshot.docs.length>1000)throw new HttpError(409,'LIST_LIMIT');
    return snapshot.docs.map(doc => doc.data());
  }
  async reviewUploadRows(reviewId) {
    let query=this.db.collection('customerReviewUploads').where('status','in',['Ready','Reserved','Failed','Deleting']);
    if(reviewId!==undefined)query=query.where('reviewId','==',reviewId);
    const snapshot=await query.limit(1001).get();
    if(snapshot.size>1000)throw new HttpError(409,'LIST_LIMIT');
    return snapshot.docs.map(d=>d.data());
  }
  async reviewsForDress(dressId) {
    const snapshot=await this.db.collection('customerReviews').where('gownIds','array-contains',dressId).limit(1001).get();
    if(snapshot.size>1000)throw new HttpError(409,'LIST_LIMIT');
    return snapshot.docs.map(d=>d.data());
  }
  async paymentInvoiceSnapshot(uid) {
    let query=this.db.collection('sandboxInvoices');
    if(uid!==undefined)query=query.where('uid','==',uid);
    const snapshot=await query.limit(1001).get();
    return {rows:snapshot.docs.map(doc=>({...doc.data(),id:doc.id})),limited:snapshot.size>1000};
  }
  async directorySnapshot(uid,kind) {
    return this.db.runTransaction(async tx=>{
      const actor=(await tx.get(this.db.doc(`staff/${uid}`))).data();
      if(actor?.active!==true || !['staff','manager'].includes(actor.role) || kind==='staff' && actor.role!=='manager')return {actor,profiles:[],appointments:[],plans:[],limited:false};
      const manager=actor.role==='manager';
      const rows=async query=>(await tx.get(query)).docs.map(doc=>({...doc.data(),id:doc.id}));
      if(kind==='staff') {
        const profiles=await rows(this.db.collection('staff').select('name','email','phone','role','active').limit(501));
        return {actor,profiles,appointments:[],plans:[],limited:profiles.length>500};
      }
      const profile=manager?null:(await tx.get(this.db.doc(`staffScheduling/${uid}`))).data();
      const frontDesk=actor.role==='staff' && canViewAllAppointments(actor,profile);
      const allVisits=this.db.collection('appointments');
      const appointments=manager?[]:await rows((frontDesk?allVisits:allVisits.where('assignedStaffId','==',uid)).select('uid','assignedStaffId').limit(2001));
      const ids=[...new Set(appointments.map(a=>a.uid).filter(id=>typeof id==='string' && /^[A-Za-z0-9_-]{1,150}$/.test(id)))];
      if(appointments.length>2000 || ids.length>500)return {actor,profiles:[],appointments:[],plans:[],limited:true};
      const profiles=manager
        ? await rows(this.db.collection('brides').select('name','email','phone').limit(501))
        : (await Promise.all(ids.map(id=>tx.get(this.db.doc(`brides/${id}`))))).filter(doc=>doc.exists).map(doc=>({...doc.data(),id:doc.id}));
      const plans=[];
      if(manager)plans.push(...await rows(this.db.collection('packageSelections').select('uid','rentalPlan').limit(2001)));
      else for(let i=0;i<ids.length;i+=30)plans.push(...await rows(this.db.collection('packageSelections').where('uid','in',ids.slice(i,i+30)).select('uid','rentalPlan').limit(2001)));
      return {actor,frontDesk,profiles,appointments,plans,limited:profiles.length>500 || plans.length>2000};
    },{readOnly:true});
  }
  async scheduleSnapshot(uid,days,scope='default') {
    return this.db.runTransaction(async tx=>{
      const actor=(await tx.get(this.db.doc(`staff/${uid}`))).data();
      if(!activeEmployee(actor))return {actor,days:[],appointments:[],limited:false};
      const profile=(await tx.get(this.db.doc(`staffScheduling/${uid}`))).data();
      const canViewAll=canViewAllAppointments(actor,profile);
      if(scope==='all'&&!canViewAll)throw new HttpError(403,'SCHEDULE_ACCESS_DENIED');
      const all=canViewAll&&scope!=='own';
      const records=await Promise.all(days.map(day=>tx.get(this.db.doc(`appointmentAvailability/${day}`))));
      // One equality query requires no new composite index. Never return another
      // employee's appointments or silently omit history beyond the safety cap.
      let query=this.db.collection('appointments');
      if(!all)query=query.where('assignedStaffId','==',uid);
      const visits=await tx.get(query
        .select('assignedStaffId','name','type','startAt','status','paymentExpiresAt','revision').limit(2001));
      const staffNames=new Map();
      if(all){const ids=[...new Set(visits.docs.map(d=>d.data().assignedStaffId).filter(id=>typeof id==='string'&&/^[A-Za-z0-9_-]{1,150}$/.test(id)))];
        if(ids.length>100)throw new HttpError(409,'SCHEDULE_LIMIT');
        for(const id of ids)staffNames.set(id,(await tx.get(this.db.doc(`staff/${id}`))).data()?.name??'');}
      return {actor,canViewAll,all,days:records.map((d,i)=>({day:days[i],own:d.data()?.entries?.[uid] ?? null})),
        appointments:visits.docs.map(d=>({...d.data(),id:d.id,...(all?{assignedStaffName:staffNames.get(d.data().assignedStaffId)??''}:{})})),limited:visits.docs.length>2000};
    },{readOnly:true});
  }
  // A consistent read-only snapshot, not the business list()'s first 100 rows.
  async customerPlanningSnapshot(uid) {
    const collections=['appointments','packageSelections','sandboxInvoices','rentals'];
    return this.db.runTransaction(async tx=>{
      const snapshots=await Promise.all(collections.map(c=>tx.get(this.db.collection(c).where('uid','==',uid).limit(501))));
      if (snapshots.some(s=>s.size>500)) return {limited:true};
      const data=Object.fromEntries(collections.map((c,i)=>
        [c,snapshots[i].docs.map(d=>({...d.data(),id:d.id}))]));
      const selections=new Map(data.packageSelections.map(s=>[s.id,s]));
      const progressRefs=data.rentals.filter(r=>r.state==='Locked'&&!r.collectedAt&&
        (r.fittingAdjustmentsRequired||finalFittingRequired(r))&&
        selections.get(r.packageSelectionId)?.rentalId===r.id)
        .map(r=>this.db.doc(`rentalServiceProgress/${r.packageSelectionId}`));
      const progress=progressRefs.length ? await tx.getAll(...progressRefs) : [];
      return {...data,limited:false,rentalServiceProgress:progress.filter(d=>d.exists)
        .map(d=>({...d.data(),selectionId:d.id}))};
    },{readOnly:true});
  }
  // Refuse oversized reports rather than quietly presenting partial totals.
  async analyticsSnapshot(manager) {
    const collections=manager
      ? ['appointments','rentals','supportTickets','sandboxInvoices','packageSelections','brides','bodyTypeSummaries']
      : ['appointments','rentals','supportTickets'];
    return this.db.runTransaction(async tx=>{
      const snapshots=await Promise.all(collections.map(c=>tx.get(this.db.collection(c).limit(5001))));
      return {limited:snapshots.some(s=>s.size>5000),...Object.fromEntries(collections.map((c,i)=>
        [c,snapshots[i].docs.map(d=>({...d.data(),id:d.id}))]))};
    },{readOnly:true});
  }
  atomic(update) {
    return this.db.runTransaction(tx => {
      const rows=async query=>{const s=await tx.get(query.limit(501));if(s.size>500)throw new HttpError(409,'SCHEDULE_LIMIT');return s.docs.map(d=>({...d.data(),id:d.id}));};
      return update({
      get: async path => (await tx.get(this.db.doc(path))).data(),
      listDresses: async () => {
        const snapshot = await tx.get(this.db.collection('dresses').where('published', '==', true)
          .select('name', 'category', 'colour', 'sizes', 'availability', 'published', 'revision', 'imageUrl', 'photoRevision').limit(1001));
        if (snapshot.size > 1000) throw new HttpError(409, 'LIST_LIMIT');
        return snapshot.docs.map(doc => ({ ...doc.data(), id: doc.id }));
      },
      reviewUploads:reviewId=>rows(this.db.collection('customerReviewUploads').where('reviewId','==',reviewId).where('status','in',['Ready','Reserved'])),
      workspaceTasks:uid=>rows(uid===undefined?this.db.collection('tasks'):this.db.collection('tasks').where('assignedStaffId','==',uid)),
      staffRoster:()=>rows(this.db.collection('staff').select('name','role','active')),
      staffAccountRows:()=>rows(this.db.collection('staff').select('name','email','phone','role','active','accountRevision','pendingActivation','invitationState','accountPending','sessionReviewRequired')),
      staffCommitments:async uid=>{
        const assigned=async collection=>{
          const result=new Map();
          for(const field of ['assignedStaffId','staffId'])for(const r of await rows(this.db.collection(collection).where(field,'==',uid).select('status')))result.set(r.id,r);
          return [...result.values()];
        };
        return {appointments:await rows(this.db.collection('appointments').where('assignedStaffId','==',uid).select('status','paymentExpiresAt')),
          tasks:await assigned('tasks'),tickets:await assigned('supportTickets')};
      },
      timeOffRequests:uid=>rows(uid===undefined?this.db.collection('staffTimeOff'):this.db.collection('staffTimeOff').where('uid','==',uid)),
      staffAppointments:uid=>rows(this.db.collection('appointments').where('assignedStaffId','==',uid).select('assignedStaffId','startAt','type','status','paymentExpiresAt')),
      schedulingDays:async()=>(await rows(this.db.collection('appointmentAvailability'))).map(d=>({...d,day:d.day??d.id})),
      hasPackageSelections: async id => !(await tx.get(this.db.collection('packageSelections').where('packageId', '==', id).limit(1))).empty,
      set: (path, data) => tx.set(this.db.doc(path), data),
      delete: path => tx.delete(this.db.doc(path)),
    });});
  }
}
