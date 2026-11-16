import {createHash,randomBytes} from 'node:crypto';
import {HttpError} from './payment_service.mjs';
import {WorkforceService,offersService,staffResponsibilities} from './workforce.mjs';
import {normalizeMalaysiaPhone,staffPhoneForSave,validContactName} from './contact_validation.mjs';
import {malaysiaDay} from './booking_dates.mjs';
import {taskQualified} from './task_time.mjs';

const check=(v,c,status=409)=>{if(!v)throw new HttpError(status,c);};
const hash=v=>createHash('sha256').update(v).digest('hex');
const idOK=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,150}$/.test(v);
const keys=(v,allowed)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).every(k=>allowed.includes(k));
const text=(v,min,max)=>typeof v==='string'&&v.trim().length>=min&&v.length<=max;
const millis=v=>v?.toMillis?.()??+v;
const revision=r=>r.accountRevision??0;
const audit=(row,event)=>[...(row.accountHistory??[]),event].slice(-40);
const authFailure=e=>new HttpError(409, e?.code==='auth/email-already-exists'?'STAFF_EMAIL_IN_USE':e?.code==='auth/user-not-found'?'STAFF_AUTH_MISSING':'STAFF_AUTH_UNAVAILABLE');
export class StaffAccountsService {
  constructor({store,auth,mailer,now=Date.now}){Object.assign(this,{store,auth,mailer,now});this.workforce=new WorkforceService({store,now});this.syncs=new Map();}
  async manager(tx,uid){const a=await tx.get(`staff/${uid}`);check(a?.active===true&&a.role==='manager','MANAGER_REQUIRED',403);return a;}
  async access(uid){return this.store.atomic(tx=>this.manager(tx,uid));}
  public(row,profile){return {id:row.id,name:row.name??'',email:row.email??'',phone:row.phone??'',role:row.role??'',active:row.active===true,
    revision:revision(row),profileRevision:profile?.revision??0,jobRole:profile?.jobRole??null,jobTitle:profile?.jobTitle??null,serviceTypes:profile?.serviceTypes??[],
    invitationState:row.invitationState??'NotSent',pendingActivation:row.pendingActivation===true,
    syncRequired:!!row.accountPending,sessionReviewRequired:row.sessionReviewRequired===true,
    history:row.accountHistory??[]};}
  async list(uid){return this.store.atomic(async tx=>{await this.manager(tx,uid);const staff=await tx.staffAccountRows();
    const records=[];for(const row of staff)records.push(this.public(row,await tx.get(`staffScheduling/${row.id}`)));
    return {actorUid:uid,canSendSetupEmail:!!this.mailer,records:records.sort((a,b)=>a.name.localeCompare(b.name)),limited:false};});}
  async details(uid,id){check(idOK(id),'INVALID_STAFF_ACCOUNT',400);const result=await this.store.atomic(async tx=>{await this.manager(tx,uid);const r=await tx.get(`staff/${id}`);check(r,'STAFF_ACCOUNT_NOT_FOUND',404);
      const p=await tx.get(`staffScheduling/${id}`),work=await tx.staffCommitments(id);return {record:this.public({...r,id},p),workload:this.countWork(work)};});
    try{const account=await this.auth.getUser(id);return {...result,record:{...result.record,email:account.email??result.record.email},authAvailable:true,authDisabled:account.disabled===true};}
    catch{return {...result,authAvailable:false,authDisabled:null};}}
  countWork(work){const appointments=work.appointments.filter(b=>['Requested','Confirmed','AwaitingPayment'].includes(b.status)&&!(b.status==='AwaitingPayment'&&b.paymentExpiresAt<=this.now())).length;
    const tasks=work.tasks.filter(t=>!['Completed','Cancelled','Closed','Done'].includes(t.status)).length;
    const tickets=work.tickets.filter(t=>!['Closed','Resolved','Cancelled'].includes(t.status)).length;return {appointments,tasks,tickets};}
  async create(uid,input){
    const responsibilities = input && staffResponsibilities(input);
    const phone = normalizeMalaysiaPhone(input?.phone);
    check(keys(input,['requestId','name','email','phone','role','jobRole','jobTitle','serviceTypes'])&&idOK(input.requestId)&&validContactName(input.name)&&phone&&text(input.email,3,254)&&/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(input.email)&&['staff','manager'].includes(input.role)&&responsibilities,'INVALID_STAFF_ACCOUNT',400);
    const email=input.email.trim().toLowerCase(),initialId=`staff_${hash(`${uid}:${input.requestId}`).slice(0,32)}`,initialOpId=hash(`create:${uid}:${input.requestId}`).slice(0,32),claim=`staffAccountEmails/${hash(email)}`;
    const fingerprintFor = candidate => hash(JSON.stringify({
      name: input.name.trim(), email, phone: candidate, role: input.role,
      ...responsibilities, serviceTypes: [...responsibilities.serviceTypes].sort(),
    }));
    const fingerprint = fingerprintFor(phone);
    const national = phone.slice(3);
    // A request started by the old editor may have used a local or pasted format.
    const acceptedFingerprints = new Set([
      fingerprint, ...[input.phone.trim(), national, '0'+national].map(fingerprintFor),
    ]);
    const leaseToken = randomBytes(16).toString('hex');
    const reserve = () => this.store.atomic(async tx=>{await this.manager(tx,uid);
      check(input.role==='staff','STAFF_ROLE_PROTECTED',403);
      const taken=await tx.get(claim);
      const opId=taken?.operationId??initialOpId,path=`staffAccountOperations/${opId}`,op=await tx.get(path),id=op?.id??initialId,r=await tx.get(`staff/${id}`);
      // Self-service verified email changes also reserve an address. Such a
      // claim is not an interrupted create operation and must never be adopted.
      if(taken)check(taken.uid===id&&op?.id===id,'STAFF_EMAIL_IN_USE');
      // A manager can recover their own interrupted provisioning after a page
      // reload, using the same employee details. Never adopt a completed account
      // or an operation belonging to a different manager.
      if (taken && opId !== initialOpId && (op.by !== uid || !acceptedFingerprints.has(op.fingerprint) || op.state === 'Complete')) {
        if (!r && op.state === 'RetryRequired' && op.leaseUntil === 0) {
          return {abandoned: {id, opId, path, leaseToken: op.leaseToken}};
        }
        throw new HttpError(409, 'STAFF_EMAIL_IN_USE');
      }
      if(op){check(acceptedFingerprints.has(op.fingerprint),'REQUEST_CONFLICT');if(op.state==='Complete'){check(r?.creationOperation===opId,'STAFF_ACCOUNT_CONFLICT');return {id,opId,path,complete:true};}check(!op.leaseUntil||op.leaseUntil<=this.now(),'STAFF_ACCOUNT_BUSY');}
      check(!r||r.creationOperation===opId,'STAFF_ACCOUNT_CONFLICT');
      check(r||(await tx.staffAccountRows()).length<100,'STAFF_ACCOUNT_LIMIT');
      tx.set(path,{...op,id,by:uid,fingerprint,state:'Creating',leaseToken,leaseUntil:this.now()+60000,at:op?.at??this.now()});tx.set(claim,{uid:id,operationId:opId});return {id,opId,path,complete:false};});
    let reserved = await reserve();
    if (reserved.abandoned) {
      await this.releaseAbandonedClaim(uid, claim, reserved.abandoned);
      reserved = await reserve();
      check(!reserved.abandoned, 'STAFF_EMAIL_IN_USE');
    }
    const {id,opId,path}=reserved;
    if(reserved.complete)return {id,created:true};
    try {
      await this.access(uid);
      await this.auth.createManagedUser({uid:id,email,displayName:input.name.trim()});
      await this.store.atomic(async tx=>{await this.manager(tx,uid);const op=await tx.get(path),r=await tx.get(`staff/${id}`),bride=await tx.get(`brides/${id}`),policy=await tx.get('schedulingSettings/policy')??{revision:0,minimumOnDuty:1};
        check(op?.fingerprint===fingerprint&&op.leaseToken===leaseToken&&(!r||r.creationOperation===opId)&&!bride,'STAFF_ACCOUNT_CONFLICT');
        if(op.state==='Complete')return;
        check(r||(await tx.staffAccountRows()).length<100,'STAFF_ACCOUNT_LIMIT');
        const row={name:input.name.trim(),email,phone,role:'staff',active:false,accountRevision:1,pendingActivation:true,invitationState:'NotSent',creationOperation:opId,createdBy:uid,createdAt:this.now(),accountHistory:[{action:'Created staff account',by:uid,at:this.now()}]};
        tx.set(`staff/${id}`,row);tx.set(`staffScheduling/${id}`,{...responsibilities,revision:1,updatedBy:uid,updatedAt:this.now()});
        tx.set(path,{...op,state:'Complete',leaseUntil:0});tx.set('schedulingSettings/policy',{...policy,revision:policy.revision+1});});
      return {id,created:true};
    } catch(e) {
      await this.store.atomic(async tx => {
        const op = await tx.get(path);
        if (op?.state !== 'Creating' || op.leaseToken !== leaseToken) return;
        if (e?.code === 'auth/email-already-exists') {
          const emailClaim = await tx.get(claim);
          if (emailClaim?.operationId === opId && emailClaim.uid === id) tx.delete(claim);
          tx.delete(path);
          return;
        }
        tx.set(path, {...op, leaseUntil: 0, state: 'RetryRequired'});
      });
      if(e instanceof HttpError)throw e;throw authFailure(e);
    }
  }
  async releaseAbandonedClaim(uid, claim, abandoned) {
    const {id, opId, path, leaseToken} = abandoned;
    try {
      await this.auth.getUser(id);
      throw new HttpError(409, 'STAFF_EMAIL_IN_USE');
    } catch (error) {
      if (error instanceof HttpError) throw error;
      if (error?.code !== 'auth/user-not-found') throw authFailure(error);
    }
    await this.store.atomic(async tx => {
      await this.manager(tx, uid);
      const [reservation, operation, staff] = await Promise.all([
        tx.get(claim), tx.get(path), tx.get(`staff/${id}`),
      ]);
      check(reservation?.uid === id && reservation.operationId === opId &&
        operation?.id === id && operation.state === 'RetryRequired' &&
        operation.leaseUntil === 0 && operation.leaseToken === leaseToken && !staff, 'STAFF_EMAIL_IN_USE');
      tx.delete(path);
      tx.delete(claim);
    });
  }
  async update(uid,id,input){
    const responsibilities = input && staffResponsibilities(input);
    check(idOK(id)&&keys(input,['name','phone','role','jobRole','jobTitle','serviceTypes','revision','profileRevision'])&&validContactName(input.name)&&typeof input.phone==='string'&&['staff','manager'].includes(input.role)&&responsibilities&&Number.isInteger(input.revision)&&input.revision>=0&&Number.isInteger(input.profileRevision)&&input.profileRevision>=0,'INVALID_STAFF_ACCOUNT',400);
    return this.store.atomic(async tx=>{await this.manager(tx,uid);
      const r=await tx.get(`staff/${id}`);
      check(r,'STAFF_ACCOUNT_NOT_FOUND',404);check(!r.accountPending,'STAFF_ACCOUNT_SYNC_REQUIRED');
      check(!(id===uid&&input.role!=='manager'),'STAFF_SELF_PROTECTION');
      check(input.role===r.role,'STAFF_ROLE_PROTECTED',403);
      const p=await tx.get(`staffScheduling/${id}`),roster=await this.workforce.roster(tx),policy=await tx.get('schedulingSettings/policy')??{revision:0,minimumOnDuty:1},days=await tx.schedulingDays(),visits=await tx.staffAppointments(id);
      check(revision(r)===input.revision&&(p?.revision??0)===input.profileRevision,'STAFF_ACCOUNT_CHANGED');
      if(tx.workspaceTasks)check(!(await tx.workspaceTasks(id)).some(t=>['Scheduled','In Progress'].includes(t.status)&&!taskQualified(input,t.type)),'STAFF_HAS_WORK');
      check(!visits.some(b=>['Requested','Confirmed','AwaitingPayment'].includes(b.status)&&millis(b.startAt)>this.now()&&!offersService(input,b.type,true)&&!(b.status==='AwaitingPayment'&&b.paymentExpiresAt<=this.now())),'STAFF_HAS_SERVICE_BOOKINGS');
      const phone = staffPhoneForSave(input.phone, r.phone);
      check(phone !== null, 'INVALID_STAFF_ACCOUNT', 400);
      const profile={...responsibilities,revision:(p?.revision??0)+1,updatedBy:uid,updatedAt:this.now()};
      const nextRoster=roster.map(s=>s.id===id?{...s,profile}:s);
      if(r.active&&(p?.jobRole!==input.jobRole||JSON.stringify(p?.serviceTypes??[])!==JSON.stringify(input.serviceTypes))){this.workforce.coverage(nextRoster,{},policy);for(const d of days)if(d.day>=malaysiaDay(this.now()))this.workforce.coverage(nextRoster,d.entries??{},policy);}
      tx.set(`staff/${id}`,{...r,name:input.name.trim(),phone,accountRevision:input.revision+1,updatedBy:uid,updatedAt:this.now(),accountHistory:audit(r,{action:'Updated staff details',by:uid,at:this.now()})});
      tx.set(`staffScheduling/${id}`,profile);tx.set('schedulingSettings/policy',{...policy,revision:policy.revision+1});
      return {saved:true};});}
  async status(uid,id,input){check(idOK(id)&&keys(input,['active','revision','requestId','note'])&&typeof input.active==='boolean'&&Number.isInteger(input.revision)&&input.revision>=0&&idOK(input.requestId)&&text(input.note,5,500),'INVALID_STAFF_ACCOUNT_STATUS',400);
    const opId=hash(`status:${uid}:${input.requestId}`).slice(0,32),fingerprint=hash(JSON.stringify({id,...input}));
    const already=await this.store.atomic(async tx=>{await this.manager(tx,uid);const r=await tx.get(`staff/${id}`),op=await tx.get(`staffAccountOperations/${opId}`);
      check(r,'STAFF_ACCOUNT_NOT_FOUND',404);if(op){check(op.fingerprint===fingerprint,'REQUEST_CONFLICT');if(op.state==='Complete'){check(!r.accountPending&&r.active===input.active,'STAFF_ACCOUNT_CHANGED');return true;}check(r.accountPending?.id===opId,'STAFF_ACCOUNT_CHANGED');return false;}
      check(!r.accountPending,'STAFF_ACCOUNT_SYNC_REQUIRED');check(revision(r)===input.revision,'STAFF_ACCOUNT_CHANGED');check(!(id===uid&&!input.active),'STAFF_SELF_PROTECTION');
      const roster=await this.workforce.roster(tx),policy=await tx.get('schedulingSettings/policy')??{revision:0,minimumOnDuty:1},days=await tx.schedulingDays(),p=await tx.get(`staffScheduling/${id}`),work=await tx.staffCommitments(id);
      if(!input.active){if(r.active&&r.role==='manager')check(roster.filter(s=>s.role==='manager').length>1,'LAST_MANAGER_REQUIRED');const counts=this.countWork(work);check(!Object.values(counts).some(n=>n>0),'STAFF_HAS_WORK');
        const remaining=roster.filter(s=>s.id!==id);this.workforce.coverage(remaining,{},policy);for(const d of days)if(d.day>=malaysiaDay(this.now()))this.workforce.coverage(remaining,d.entries??{},policy);
      } else {
        check(p&&staffResponsibilities(p),'STAFF_RESPONSIBILITIES_REQUIRED');
        check(!r.pendingActivation || r.invitationState === 'Sent', 'STAFF_SETUP_EMAIL_REQUIRED');
      }
      const pending={id:opId,active:input.active,by:uid,note:input.note.trim(),at:this.now()};
      tx.set(`staff/${id}`,{...r,active:false,accountPending:pending,accountRevision:input.revision+1,updatedAt:this.now()});
      tx.set(`staffAccountOperations/${opId}`,{id:opId,target:id,by:uid,fingerprint,state:'SyncPending'});tx.set('schedulingSettings/policy',{...policy,revision:policy.revision+1});return false;});
    return already?{saved:true,syncRequired:false}:this.sync(uid,id);
  }
  async sync(uid,id){check(idOK(id),'INVALID_STAFF_ACCOUNT',400);await this.access(uid);
    if(this.syncs.has(id))return this.syncs.get(id);
    const task=this.syncAccount(uid,id);this.syncs.set(id,task);
    try{return await task;}finally{this.syncs.delete(id);}}
  async syncAccount(uid,id){const pending=await this.store.atomic(async tx=>{await this.manager(tx,uid);const r=await tx.get(`staff/${id}`);check(r?.accountPending,'STAFF_ACCOUNT_CHANGED');return r.accountPending;});
    try{await this.access(uid);await this.auth.setDisabled(id,!pending.active);await this.auth.revoke(id);
      await this.store.atomic(async tx=>{await this.manager(tx,uid);const r=await tx.get(`staff/${id}`),policy=await tx.get('schedulingSettings/policy')??{revision:0,minimumOnDuty:1};check(r?.accountPending?.id===pending.id,'STAFF_ACCOUNT_CHANGED');
        const op=await tx.get(`staffAccountOperations/${pending.id}`);
        const next={...r,active:pending.active,pendingActivation:false,accountPending:null,sessionReviewRequired:false,accountRevision:revision(r)+1,updatedBy:uid,updatedAt:this.now(),accountHistory:audit(r,{action:pending.active?'Activated access':'Deactivated access',note:pending.note,by:uid,at:this.now()})};
        tx.set(`staff/${id}`,next);tx.set(`staffAccountOperations/${pending.id}`,{...op,state:'Complete'});tx.set('schedulingSettings/policy',{...policy,revision:policy.revision+1});});
      return {saved:true,syncRequired:false};
    }catch(e){if(e instanceof HttpError)throw e;return {saved:false,syncRequired:true};}}
  async endSessions(uid,id){check(idOK(id),'INVALID_STAFF_ACCOUNT',400);await this.store.atomic(async tx=>{await this.manager(tx,uid);check(await tx.get(`staff/${id}`),'STAFF_ACCOUNT_NOT_FOUND',404);});try{await this.auth.revoke(id);await this.store.atomic(async tx=>{await this.manager(tx,uid);const r=await tx.get(`staff/${id}`);check(r,'STAFF_ACCOUNT_NOT_FOUND',404);tx.set(`staff/${id}`,{...r,sessionReviewRequired:false});});return {saved:true};}
    catch(e){if(e instanceof HttpError)throw e;return {saved:false,sessionReviewRequired:true};}}
  async invite(uid,id,input){check(idOK(id)&&keys(input,['requestId','revision'])&&idOK(input.requestId)&&Number.isInteger(input.revision)&&input.revision>=0,'INVALID_STAFF_ACCOUNT',400);await this.access(uid);check(this.mailer,'STAFF_MAIL_UNAVAILABLE');
    const invitation=hash(`${uid}:${id}:${input.requestId}`).slice(0,32);
    const reserved=await this.store.atomic(async tx=>{await this.manager(tx,uid);const r=await tx.get(`staff/${id}`);check(r,'STAFF_ACCOUNT_NOT_FOUND',404);check(!r.accountPending,'STAFF_ACCOUNT_SYNC_REQUIRED');
      if(r.invitationRequest===invitation){check(r.invitationState==='Sent','STAFF_INVITE_REVIEW');return null;}
      check(revision(r)===input.revision,'STAFF_ACCOUNT_CHANGED');check(!r.invitationAt||this.now()-r.invitationAt>=60000,'STAFF_INVITE_WAIT');
      tx.set(`staff/${id}`,{...r,invitationState:'Sending',invitationRequest:invitation,invitationAt:this.now(),accountRevision:revision(r)+1});return r;});
    if(!reserved)return {sent:true};
    let sent=false;
    try{await this.access(uid);const account=await this.auth.getUser(id);check(!account.disabled&&account.email,'STAFF_AUTH_DISABLED');check(!reserved.email||account.email.toLowerCase()===reserved.email.toLowerCase(),'STAFF_ACCOUNT_CONFLICT');
      const link=await this.auth.setupLink(account.email);await this.access(uid);await this.mailer.send({to:account.email,name:reserved.name,link});sent=true;
    }catch(e){await this.store.atomic(async tx=>{const r=await tx.get(`staff/${id}`);if(r?.invitationRequest===invitation)tx.set(`staff/${id}`,{...r,invitationState:'ReviewRequired'});});if(e instanceof HttpError)throw e;return {sent:false,reviewRequired:true};}
    await this.store.atomic(async tx=>{const r=await tx.get(`staff/${id}`);if(r?.invitationRequest===invitation)tx.set(`staff/${id}`,{...r,invitationState:'Sent',accountHistory:audit(r,{action:'Setup email accepted by mail server',by:uid,at:this.now()})});});return {sent};}
}

export class FirebaseStaffAuth {
  constructor(auth){this.auth=auth;}
  getUser(uid){return this.auth.getUser(uid);}
  async createManagedUser({uid,email,displayName}){try{const u=await this.auth.getUser(uid);check(u.email?.toLowerCase()===email,'STAFF_ACCOUNT_CONFLICT');return u;}
    catch(e){if(e.code!=='auth/user-not-found')throw e;return this.auth.createUser({uid,email,displayName,emailVerified:false,disabled:false,password:`Aa1!${randomBytes(36).toString('base64url')}`});}}
  setDisabled(uid,disabled){return this.auth.updateUser(uid,{disabled});}
  revoke(uid){return this.auth.revokeRefreshTokens(uid);}
  setupLink(email){return this.auth.generatePasswordResetLink(email);}
}

// Only the account owner receives this short-lived Firebase action link. It is
// never returned to the manager, stored in Firestore, or written to a log.
export class StaffSetupMailer {
  constructor({transport,from}){Object.assign(this,{transport,from});}
  async send({to,name,link}){
    const result=await this.transport.sendMail({from:{name:'Luvly Bridal',address:this.from},to,
      subject:'Set up your Luvly staff password',
      text:`Hello ${name},\n\nYour manager requested a Luvly staff password setup or reset. Use this secure link to choose your own password:\n\n${link}\n\nYour manager must also activate your staff access before you can use the portal. If you did not expect this email, contact the boutique and do not share this link.\n\nLuvly Bridal Boutique`});
    if(!result.accepted?.some(address=>String(address).toLowerCase()===to.toLowerCase()))throw Error('MAIL_NOT_ACCEPTED');
  }
}
