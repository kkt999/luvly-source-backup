import {hasBoutiqueOperationsAccess} from './appointment_access.mjs';
import {HttpError} from './payment_service.mjs';

// Share the read-only database listeners across open dashboards. The wire carries
// invalidation events only, never receipts, profiles, tokens or document IDs.
export class AnalyticsEvents {
  constructor({store,access,idleMs=30000,debounceMs=350}) {
    Object.assign(this,{store,access,idleMs,debounceMs});this.channels=new Map();
  }
  async actor(uid) {
    const actor=await this.access(uid);
    if(!['staff','manager'].includes(actor.role))throw new HttpError(403,'STAFF_REQUIRED');
    if (actor.role==='staff' && !await hasBoutiqueOperationsAccess(
      this.store, uid, await this.store.get(`staff/${uid}`),
    )) throw new HttpError(403,'OPERATIONS_ACCESS_REQUIRED');
    return actor;
  }
  async subscribe(uid,emit) {
    const key=(await this.actor(uid)).role;
    let channel=this.channels.get(key);
    if(!channel) {
      channel={clients:new Set(),ready:false,failed:false,stops:[],idle:null,pending:null};
      this.channels.set(key,channel);
      const collections=key==='manager'?['appointments','rentals','supportTickets','sandboxInvoices','packageSelections','brides','bodyTypeSummaries']:['appointments','rentals','supportTickets'];
      const initialized=new Set();
      const broadcast=event=>{for(const client of channel.clients)client(event);};
      try {
        for(const collection of collections){const stop=this.store.watchAnalytics(collection,()=>{
          initialized.add(collection);
          if(initialized.size!==collections.length)return;
          if(!channel.ready){channel.ready=true;broadcast('ready');return;}
          if(channel.pending)return;
          channel.pending=setTimeout(()=>{channel.pending=null;broadcast('changed');},this.debounceMs);
        },()=>{channel.failed=true;broadcast('unavailable');this.stop(key,channel);});
          if(channel.failed){stop();throw new HttpError(503,'SERVICE_UNAVAILABLE');}
          channel.stops.push(stop);
        }
      } catch(error) {this.stop(key,channel);throw error;}
    }
    clearTimeout(channel.idle);channel.idle=null;
    channel.clients.add(emit);
    if(channel.ready)emit('ready');
    let closed=false;
    return {role:key,close:()=>{
      if(closed)return;closed=true;channel.clients.delete(emit);
      if(!channel.clients.size && this.channels.get(key)===channel) {
        channel.idle=setTimeout(()=>this.stop(key,channel),this.idleMs);channel.idle.unref?.();
      }
    }};
  }
  stop(key,channel) {
    clearTimeout(channel.idle);clearTimeout(channel.pending);
    for(const close of channel.stops)close();
    channel.clients.clear();
    if(this.channels.get(key)===channel)this.channels.delete(key);
  }
  close(){for(const [key,channel] of this.channels)this.stop(key,channel);}
}

export async function serveAnalyticsEvents({req,res,events,uid,verifySession,durationMs=50000,heartbeatMs=10000}) {
  let subscription,heartbeat,expiry,closed=false,checking=false;
  const close=()=>{
    if(closed)return;closed=true;clearInterval(heartbeat);clearTimeout(expiry);
    subscription?.close();res.end();
  };
  const emit=event=>{
    if(closed||res.destroyed)return;
    if(!res.headersSent){res.writeHead(200,{'Content-Type':'text/event-stream; charset=utf-8','Cache-Control':'no-store, no-transform','X-Accel-Buffering':'no'});res.flushHeaders?.();}
    res.write(`data: ${event}\n\n`);
    if(['unavailable','access-denied'].includes(event))close();
  };
  res.on('close',close);
  try {
    subscription=await events.subscribe(uid,emit);
    if(closed){subscription.close();return;}
    emit('connecting');
    heartbeat=setInterval(async()=>{
      if(checking||closed)return;checking=true;
      try {
        await verifySession();
        const actor=await events.actor(uid);
        if(actor.role!==subscription.role)throw new Error('access changed');
        if(!closed)res.write(': heartbeat\n\n');
      } catch {emit('access-denied');} finally {checking=false;}
    },heartbeatMs);
    heartbeat.unref?.();
    expiry=setTimeout(close,durationMs);expiry.unref?.();
  } catch(error) {
    res.off('close',close);
    if(res.headersSent){emit('unavailable');return;}
    closed=true;clearInterval(heartbeat);clearTimeout(expiry);subscription?.close();throw error;
  }
}
