import {randomUUID,createHash} from 'node:crypto';
import {HttpError} from './payment_service.mjs';
const key=uid=>createHash('sha256').update(uid).digest('hex');

// Keep OAuth state and per-user leases across cold starts / revision changes.
// All collections are server-only under the Firestore default-deny rules.
export class FirestoreCalendarCoordination{
  constructor({db,now=Date.now}){Object.assign(this,{db,now});}
  async put(id,state){
    const current=this.db.doc(`calendarOAuthCurrent/${key(state.uid)}`);
    await this.db.runTransaction(async tx=>{const old=(await tx.get(current)).data();
      if(old?.id)tx.delete(this.db.doc(`calendarOAuthStates/${old.id}`));
      tx.set(this.db.doc(`calendarOAuthStates/${id}`),state);tx.set(current,{id});});
  }
  async take(id){
    const ref=this.db.doc(`calendarOAuthStates/${id}`);
    return this.db.runTransaction(async tx=>{
      const state=(await tx.get(ref)).data();if(!state)return null;
      const current=this.db.doc(`calendarOAuthCurrent/${key(state.uid)}`),old=(await tx.get(current)).data();
      tx.delete(ref);
      if(old?.id!==id)return null;
      tx.delete(current);return state;
    });
  }
  async clear(uid){
    const ref=this.db.doc(`calendarOAuthCurrent/${key(uid)}`);
    await this.db.runTransaction(async tx=>{const current=(await tx.get(ref)).data();
      if(current?.id)tx.delete(this.db.doc(`calendarOAuthStates/${current.id}`));tx.delete(ref);});
  }
  async locked(uid,action){
    const ref=this.db.doc(`calendarSyncLeases/${key(uid)}`),owner=randomUUID();
    const acquired=await this.db.runTransaction(async tx=>{const old=(await tx.get(ref)).data();
      if(old?.expiresAt>this.now())return false;
      tx.set(ref,{owner,expiresAt:this.now()+180000});return true;});
    if(!acquired)throw new HttpError(409,'CALENDAR_BUSY');
    try{return await action();}
    finally{await this.db.runTransaction(async tx=>{const old=(await tx.get(ref)).data();if(old?.owner===owner)tx.delete(ref);});}
  }
}
