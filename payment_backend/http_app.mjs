import { HttpError } from './payment_service.mjs';
import { PaymentError } from './toyyibpay.mjs';
import {serveAnalyticsEvents} from './analytics_events.mjs';
import {reviewVideoLimit,reviewPhotoLimit} from './review_media.mjs';

async function readReviewFile(req){
  const mime=req.headers['content-type'];
  if(!['image/jpeg','video/mp4'].includes(mime))throw new HttpError(415,'INVALID_REVIEW_MEDIA');
  const max=mime==='video/mp4'?reviewVideoLimit:reviewPhotoLimit,chunks=[];let size=0;
  if(Number(req.headers['content-length'])>max)throw new HttpError(413,'REVIEW_MEDIA_TOO_LARGE');
  for await(const chunk of req){size+=chunk.length;if(size>max)throw new HttpError(413,'REVIEW_MEDIA_TOO_LARGE');chunks.push(chunk);}
  return {bytes:Buffer.concat(chunks),mime};
}

async function readBody(req, form = false, limit = 8192) {
  const expected = form ? 'application/x-www-form-urlencoded' : 'application/json';
  if (req.headers['content-type']?.split(';')[0] !== expected) throw new HttpError(415, 'UNSUPPORTED_CONTENT_TYPE');
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > limit) throw new HttpError(413, 'BODY_TOO_LARGE');
    chunks.push(chunk);
  }
  const body = Buffer.concat(chunks).toString('utf8');
  if (form) {
    const params = new URLSearchParams(body);
    if ([...params.keys()].some(key => params.getAll(key).length !== 1)) throw new HttpError(400, 'DUPLICATE_FIELDS');
    return Object.fromEntries(params);
  }
  try {
    const data = JSON.parse(body);
    if (!data || Array.isArray(data) || typeof data !== 'object') throw new Error();
    return data;
  } catch { throw new HttpError(400, 'INVALID_JSON'); }
}

export function createHandler({ service, packages, packageRentals, calendar, rentals, bookings, workforce, staffAccounts, workspace, profilePhotos, recommendationProfiles, reviews, assistant, promotions, analytics, analyticsEvents, customerPlanning, fittingWorkflow, directory, verifyToken, allowedOrigins = [], now = Date.now }) {
  // Demo single-process limiter. Not a replacement for production edge protection.
  const buckets = new Map();
  let reviewUploadsInFlight=0;
  return async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    const send = (status, value) => {
      res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify(value));
    };
    try {
      const origin = req.headers.origin;
      if (origin) {
        if (!allowedOrigins.includes(origin)) throw new HttpError(403, 'ORIGIN_NOT_ALLOWED');
        res.setHeader('Access-Control-Allow-Origin', origin);
        res.setHeader('Vary', 'Origin');
        res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
        res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
      }
      if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }
      const url = new URL(req.url, 'http://localhost');
      if (calendar && req.method === 'GET' && url.pathname === '/oauth/google/calendar/callback') {
        let success = false;
        try { await calendar.callback(url.searchParams); success = true; } catch { /* Never echo OAuth codes or provider errors. */ }
        res.writeHead(success ? 200 : 400, { 'Content-Type': 'text/html; charset=utf-8',
          'Referrer-Policy': 'no-referrer', 'Content-Security-Policy': "default-src 'none'; frame-ancestors 'none'" });
        res.end('<!doctype html><meta name="viewport" content="width=device-width"><title>Luvly Calendar</title><h1>' +
          (success ? 'Calendar connected' : 'Calendar connection not completed') +
          '</h1><p>Return to Luvly, open Google Calendar in your profile, and check status. If connection failed, retry and choose the Google account linked to Luvly.</p>');
        return;
      }
      if (req.method === 'GET' && url.pathname === '/health') { send(200, { environment: 'sandbox',bookingPaymentPolicy:bookings?.feePolicy ? 1 : null,promotionsEnabled:!!promotions,staffSchedulingVersion:workforce?1:null,staffAccountsVersion:staffAccounts?1:null,analyticsLiveVersion:analyticsEvents?1:null,staffWorkspaceVersion:workspace?1:null,profilePhotosVersion:profilePhotos?1:null,recommendationProfilesVersion:recommendationProfiles?1:null,customerReviewsVersion:reviews?1:null,reviewPolicyVersion:reviews?.policyVersion??null,reviewStaffHandlingVersion:reviews?.staffHandlingVersion??null }); return; }
      if (req.method === 'GET' && url.pathname === '/return') {
        // Ignore success query parameters entirely. Do not write data or redirect
        // to untrusted continue URLs. Customer refreshes in their signed-in app.
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8',
          'Content-Security-Policy': "default-src 'none'; frame-ancestors 'none'" });
        res.end('<!doctype html><meta name="viewport" content="width=device-width"><title>Luvly Payments</title><h1>Return to Luvly</h1><p>Open Payments &amp; receipts in Luvly and tap Check status to confirm your payment.</p>');
        return;
      }
      let uid;
      const callback = url.pathname === '/callback' && req.method === 'POST';
      if (!callback) {
        const bearer = req.headers.authorization;
        if (!bearer?.startsWith('Bearer ') || bearer.length > 8192) throw new HttpError(401, 'SIGN_IN_REQUIRED');
        try { uid = (await verifyToken(bearer.slice(7))).uid; }
        catch { throw new HttpError(401, 'SIGN_IN_REQUIRED'); }
      }
      const key = callback ? 'callback' : uid;
      const time = now();
      if (buckets.size > 1000) for (const [k, v] of buckets) if (v.until <= time) buckets.delete(k);
      if (buckets.size > 2000 && !buckets.has(key)) throw new HttpError(429, 'TRY_LATER');
      let bucket = buckets.get(key);
      if (!bucket || bucket.until <= time) { bucket = { count: 0, until: time + 60000 }; buckets.set(key, bucket); }
      if (++bucket.count > (callback ? 120 : 30)) throw new HttpError(429, 'TRY_LATER');
      if (callback) { await service.callback(await readBody(req, true)); send(200, { received: true }); return; }
      if(reviews&&url.pathname.startsWith('/v1/review-reports')){
        if(url.pathname==='/v1/review-reports'&&req.method==='GET'){
          if([...url.searchParams.keys()].some(k=>k!=='status')||url.searchParams.getAll('status').length>1)throw new HttpError(400,'INVALID_REVIEW_REPORT');
          send(200,await reviews.reports(uid,url.searchParams.get('status')??'Open'));return;
        }
        if(url.search)throw new HttpError(400,'INVALID_REVIEW_REPORT');
        const resolve=/^\/v1\/review-reports\/([a-f0-9]{64})\/resolve$/.exec(url.pathname);
        if(resolve&&req.method==='POST'){send(200,await reviews.resolveReport(uid,resolve[1],await readBody(req)));return;}
        const media=/^\/v1\/review-reports\/([a-f0-9]{64})\/media\/([a-f0-9]{32})$/.exec(url.pathname);
        if(media&&req.method==='GET'){send(200,await reviews.reportMediaUrl(uid,media[1],media[2]));return;}
      }
      if(reviews&&url.pathname.startsWith('/v1/reviews')){
        const route=url.pathname;
        if(route==='/v1/reviews/ratings'&&req.method==='GET'){
          if(url.search)throw new HttpError(400,'INVALID_REVIEW');
          send(200,await reviews.ratings(uid));return;
        }
        if(route==='/v1/reviews'&&req.method==='GET'){
          if([...url.searchParams.keys()].some(k=>!['scope','dressId'].includes(k))||['scope','dressId'].some(k=>url.searchParams.getAll(k).length>1))throw new HttpError(400,'INVALID_REVIEW');
          send(200,await reviews.list(uid,url.searchParams.get('scope')??'all',url.searchParams.get('dressId')??undefined));return;
        }
        if(route==='/v1/reviews/eligible'&&req.method==='GET'){
          if([...url.searchParams.keys()].some(k=>k!=='dressId')||url.searchParams.getAll('dressId').length>1)throw new HttpError(400,'INVALID_REVIEW');
          send(200,await reviews.options(uid,url.searchParams.get('dressId')??undefined));return;
        }
        if(url.search)throw new HttpError(400,'INVALID_REVIEW');
        const upload=/^\/v1\/reviews\/([A-Za-z0-9_-]{1,150})\/upload\/([a-f0-9]{32})$/.exec(route);
        if(upload&&req.method==='POST'){
          await reviews.authorizeUpload(uid,upload[1]);
          if(reviewUploadsInFlight>=2)throw new HttpError(429,'TRY_LATER');
          reviewUploadsInFlight++;
          try{const {bytes,mime}=await readReviewFile(req);send(200,await reviews.upload(uid,upload[1],upload[2],bytes,mime));}finally{reviewUploadsInFlight--;}
          return;
        }
        const media=/^\/v1\/reviews\/([a-f0-9]{32})\/media\/([a-f0-9]{32})$/.exec(route);
        if(media&&req.method==='GET'){send(200,await reviews.mediaUrl(uid,media[1],media[2]));return;}
        const report=/^\/v1\/reviews\/([a-f0-9]{32})\/report$/.exec(route);
        if(report&&req.method==='POST'){send(200,await reviews.report(uid,report[1],await readBody(req)));return;}
        const action=/^\/v1\/reviews\/([a-f0-9]{32})\/(withdraw|reply|moderate|approve)$/.exec(route);
        if(action&&req.method==='POST'){send(200,await reviews.action(uid,action[1],action[2],await readBody(req)));return;}
        const save=/^\/v1\/reviews\/([A-Za-z0-9_-]{1,150})$/.exec(route);
        if(save&&req.method==='POST'){send(200,await reviews.save(uid,save[1],await readBody(req)));return;}
      }
      if(recommendationProfiles&&url.pathname==='/v1/my-recommendation-profile'){
        if(url.search)throw new HttpError(400,'INVALID_RECOMMENDATION_PROFILE');
        if(req.method==='GET'){send(200,await recommendationProfiles.get(uid));return;}
        if(req.method==='POST'){send(200,await recommendationProfiles.save(uid,await readBody(req)));return;}
      }
      if(profilePhotos&&url.pathname==='/v1/my-profile-photo'){
        if(url.search)throw new HttpError(400,'INVALID_PROFILE_PHOTO');
        if(req.method==='GET'){send(200,await profilePhotos.get(uid));return;}
        if(req.method==='POST'){send(200,await profilePhotos.save(uid,await readBody(req,false,96*1024)));return;}
      }
      if(workspace){
        const route=url.pathname;
        if(route==='/v1/notifications'&&req.method==='GET'){
          if([...url.searchParams.keys()].some(k=>k!=='cursor')||url.searchParams.getAll('cursor').length>1)throw new HttpError(400,'INVALID_NOTIFICATION');
          send(200,await workspace.notifications(uid,url.searchParams.get('cursor')??undefined));return;
        }
        if(route.startsWith('/v1/my-staff-profile')||route.startsWith('/v1/staff-tasks')||route.startsWith('/v1/support-messages')||route.startsWith('/v1/notifications/')){
          if(url.search)throw new HttpError(400,'INVALID_WORKSPACE_QUERY');
          if(route==='/v1/my-staff-profile'){
            if(req.method==='GET'){send(200,await workspace.profile(uid));return;}
            if(req.method==='POST'){send(200,await workspace.saveProfile(uid,await readBody(req)));return;}
          }
          if(route==='/v1/staff-tasks'){
            if(req.method==='GET'){send(200,await workspace.taskList(uid));return;}
            if(req.method==='POST'){send(201,await workspace.saveTask(uid,null,await readBody(req)));return;}
          }
          const task=/^\/v1\/staff-tasks\/([A-Za-z0-9_-]{1,150})(?:\/(status))?$/.exec(route);
          if(task&&req.method==='POST'){send(200,await workspace[task[2]?'taskStatus':'saveTask'](uid,task[1],await readBody(req)));return;}
          const notice=/^\/v1\/notifications\/([A-Za-z0-9_-]{1,150})\/read$/.exec(route);
          if(notice&&req.method==='POST'){if(Object.keys(await readBody(req)).length)throw new HttpError(400,'INVALID_NOTIFICATION');send(200,await workspace.readNotification(uid,notice[1]));return;}
          if(route==='/v1/support-messages'&&req.method==='POST'){send(200,await workspace.support(uid,null,await readBody(req)));return;}
          const support=/^\/v1\/support-messages\/([A-Za-z0-9_-]{1,150})$/.exec(route);
          if(support&&req.method==='POST'){send(200,await workspace.support(uid,support[1],await readBody(req)));return;}
        }
      }
      if(staffAccounts&&url.pathname.startsWith('/v1/staff-accounts')){
        if(url.search)throw new HttpError(400,'INVALID_STAFF_ACCOUNT');
        if(url.pathname==='/v1/staff-accounts'){
          if(req.method==='GET'){send(200,await staffAccounts.list(uid));return;}
          if(req.method==='POST'){send(201,await staffAccounts.create(uid,await readBody(req)));return;}
        }
        const account=/^\/v1\/staff-accounts\/([A-Za-z0-9_-]{1,150})(?:\/(status|sync|invite|sessions))?$/.exec(url.pathname);
        if(account){
          if(req.method==='GET'&&!account[2]){send(200,await staffAccounts.details(uid,account[1]));return;}
          if(req.method==='POST'){
            const body=await readBody(req),action=account[2]??'update';
            if(['sync','sessions'].includes(action)&&Object.keys(body).length)throw new HttpError(400,'INVALID_STAFF_ACCOUNT');
            send(200,await staffAccounts[action==='sessions'?'endSessions':action](uid,account[1],body));return;
          }
        }
      }
      const directoryRoute=/^\/v1\/directory\/(customers|staff)$/.exec(url.pathname);
      if(directory && directoryRoute && req.method==='GET') {
        if(url.search)throw new HttpError(400,'INVALID_DIRECTORY_QUERY');
        send(200,await directory.list(uid,directoryRoute[1]));return;
      }
      const fittingRoute=/^\/v1\/package-selections\/([a-f0-9]{32})\/(fitting-choice|fitting-result|fitting-quote|fitting-response|fitting-intent|final-fitting|fitting-gown-options)$/.exec(url.pathname);
      if(fittingWorkflow&&fittingRoute&&req.method==='POST'){
          if(url.search)throw new HttpError(400,'INVALID_FITTING_CHOICE');
        send(200,await fittingWorkflow[{'fitting-choice':'choice','fitting-result':'record','fitting-quote':'quote','fitting-response':'respond','fitting-intent':'intent','final-fitting':'final','fitting-gown-options':'gownOptions'}[fittingRoute[2]]](uid,fittingRoute[1],await readBody(req, false, fittingRoute[2] === 'fitting-result' ? 262144 : 8192)));return;
      }
      if(customerPlanning && req.method==='GET' && url.pathname==='/v1/my-planning'){
        if(url.search)throw new HttpError(400,'INVALID_PLANNING_QUERY');
        send(200,await customerPlanning.get(uid));return;
      }
      if(analyticsEvents && req.method==='GET' && url.pathname==='/v1/analytics/events'){
        if(url.search)throw new HttpError(400,'INVALID_REPORT_RANGE');
        await serveAnalyticsEvents({req,res,events:analyticsEvents,uid,
          verifySession:()=>verifyToken(req.headers.authorization.slice(7))});return;
      }
      if(analytics && req.method==='GET' && url.pathname==='/v1/analytics'){
        if([...url.searchParams.keys()].some(k=>!['from','to'].includes(k)||url.searchParams.getAll(k).length!==1))throw new HttpError(400,'INVALID_REPORT_RANGE');
        send(200,await analytics.report(uid,Object.fromEntries(url.searchParams)));return;
      }
      if(analytics && req.method==='GET' && url.pathname==='/v1/dashboard'){
        if(url.search)throw new HttpError(400,'INVALID_REPORT_RANGE');
        send(200,await analytics.dashboard(uid));return;
      }
      if(promotions&&url.pathname==='/v1/promotions'){
        if(req.method==='GET'){send(200,await promotions.list(uid));return;}
        if(req.method==='POST'){send(200,await promotions.save(uid,await readBody(req)));return;}
      }
      const removePromotion=/^\/v1\/promotions\/([A-Za-z0-9_-]{1,100})\/delete$/.exec(url.pathname);
      if(promotions&&removePromotion&&req.method==='POST'){send(200,await promotions.remove(uid,removePromotion[1],await readBody(req)));return;}
      const applyPromotion=/^\/v1\/package-selections\/([a-f0-9]{32})\/promotion$/.exec(url.pathname);
      if(promotions&&applyPromotion&&req.method==='POST'){send(200,await promotions.apply(uid,applyPromotion[1],await readBody(req)));return;}
      if(assistant && url.pathname==='/v1/support-assistant'){
        if(req.method==='GET'){send(200,await assistant.status(uid));return;}
        if(req.method==='POST'){send(200,await assistant.ask(uid,await readBody(req)));return;}
      }
      if(bookings && url.pathname==='/v1/appointment-schedule' && req.method==='GET') {
        if([...url.searchParams.keys()].some(k=>!['month','scope'].includes(k)) || url.searchParams.getAll('month').length!==1 || url.searchParams.getAll('scope').length>1)throw new HttpError(400,'INVALID_SCHEDULE_MONTH');
        send(200,await bookings.calendar(uid,url.searchParams.get('month'),url.searchParams.get('scope')??'default'));return;
      }
      if(workforce) {
        if(url.pathname.startsWith('/v1/staff-scheduling')||url.pathname.startsWith('/v1/staff-time-off')) {
          if(url.search)throw new HttpError(400,'INVALID_TIME_OFF');
          if(req.method==='GET'&&url.pathname==='/v1/staff-scheduling'){send(200,await workforce.context(uid));return;}
          if(req.method==='POST'&&url.pathname==='/v1/staff-scheduling/profile'){send(200,await workforce.saveProfile(uid,await readBody(req)));return;}
          if(req.method==='POST'&&url.pathname==='/v1/staff-scheduling/policy'){send(200,await workforce.savePolicy(uid,await readBody(req)));return;}
          if(req.method==='POST'&&url.pathname==='/v1/staff-scheduling/restore'){send(200,await workforce.restore(uid,await readBody(req)));return;}
          if(req.method==='POST'&&url.pathname==='/v1/staff-time-off'){send(200,await workforce.request(uid,await readBody(req)));return;}
          const review=/^\/v1\/staff-time-off\/([a-f0-9]{32})\/review$/.exec(url.pathname);
          if(req.method==='POST'&&review){send(200,await workforce.review(uid,review[1],await readBody(req)));return;}
        }
      }
      const assign=/^\/v1\/appointments\/([A-Za-z0-9_-]{1,150})\/assign$/.exec(url.pathname);
      if(workforce&&assign&&req.method==='POST'){if(url.search)throw new HttpError(400,'INVALID_STAFF_SCHEDULING');send(200,await workforce.reassign(uid,assign[1],await readBody(req)));return;}
      if(bookings && url.pathname==='/v1/appointment-availability') {
        if(req.method==='GET'){
          if([...url.searchParams.keys()].some(k=>!['day','type'].includes(k))||url.searchParams.getAll('day').length!==1||url.searchParams.getAll('type').length>1)throw new HttpError(400,'INVALID_AVAILABILITY_DATE');
          send(200,await bookings.day(uid,url.searchParams.get('day'),url.searchParams.get('type')??undefined));return;}
        if(req.method==='POST'){send(200,await bookings.availability(uid,await readBody(req)));return;}
      }
      if(bookings && url.pathname==='/v1/appointments' && req.method==='POST') {
        send(201,await bookings.create(uid,await readBody(req)));return;
      }
      const bookingMove=/^\/v1\/appointments\/([A-Za-z0-9_-]{1,150})\/reschedule$/.exec(url.pathname);
      if(bookings&&bookingMove){
        if(url.search)throw new HttpError(400,'INVALID_RESCHEDULE');
        if(req.method==='GET'){send(200,await bookings.rescheduleContext(uid,bookingMove[1]));return;}
        if(req.method==='POST'){send(200,await bookings.reschedule(uid,bookingMove[1],await readBody(req)));return;}
      }
      const bookingAction=/^\/v1\/appointments\/([A-Za-z0-9_-]{1,150})\/transition$/.exec(url.pathname);
      if(bookings && bookingAction && req.method==='POST') {
        send(200,await bookings.transition(uid,bookingAction[1],await readBody(req)));return;
      }
      if (rentals && url.pathname === '/v1/rentals') {
        if (req.method === 'GET') { send(200, await rentals.list(uid)); return; }
        if (req.method === 'POST') { send(201, await rentals.hold(uid, await readBody(req))); return; }
      }
      if(packageRentals && url.pathname==='/v1/accessory-stock') {
        if(req.method==='GET') {send(200,await packageRentals.stock(uid));return;}
        if(req.method==='POST') {send(200,await packageRentals.saveStock(uid,await readBody(req)));return;}
      }
      const rentalAction=/^\/v1\/package-selections\/([a-f0-9]{32})\/(plan|check-plan|confirm-rental)$/.exec(url.pathname);
      if(packageRentals && rentalAction && req.method==='POST') {
        if(url.search)throw new HttpError(400,'INVALID_RENTAL');
        send(200,await packageRentals[{'plan':'plan','check-plan':'checkPlan','confirm-rental':'confirm'}[rentalAction[2]]](uid,rentalAction[1],await readBody(req)));return;
      }
      if (rentals && url.pathname === '/v1/rental-variants') {
        if (req.method === 'GET') { send(200, await rentals.variants(uid, url.searchParams.get('dressId'))); return; }
        if (req.method === 'POST') { send(200, await rentals.saveVariant(uid, await readBody(req))); return; }
      }
      const cancelRental = /^\/v1\/rentals\/([a-f0-9]{32})\/cancel$/.exec(url.pathname);
      const singleRental=/^\/v1\/rentals\/([a-f0-9]{32})$/.exec(url.pathname);
      if(rentals&&singleRental&&req.method==='GET'){if(url.search)throw new HttpError(400,'INVALID_RENTAL');send(200,await rentals.get(uid,singleRental[1]));return;}
      const fulfilRental=/^\/v1\/rentals\/([a-f0-9]{32})\/fulfil$/.exec(url.pathname);
      const dateChange=/^\/v1\/rentals\/([a-f0-9]{32})\/change-dates$/.exec(url.pathname);
      const cancelExtension=/^\/v1\/rentals\/([a-f0-9]{32})\/cancel-extension$/.exec(url.pathname);
      if(packageRentals&&cancelExtension&&req.method==='POST'){
        if(url.search)throw new HttpError(400,'INVALID_DATE_CHANGE');
        send(200,await packageRentals.cancelExtension(uid,cancelExtension[1],await readBody(req)));return;
      }
      if(packageRentals&&dateChange&&req.method==='POST'){
        if(url.search)throw new HttpError(400,'INVALID_DATE_CHANGE');
        send(200,await packageRentals.changeDates(uid,dateChange[1],await readBody(req)));return;
      }
      if(rentals && fulfilRental && req.method==='POST'){send(200,await rentals.fulfil(uid,fulfilRental[1],await readBody(req)));return;}
      if (rentals && cancelRental && req.method === 'POST') {
        if (Object.keys(await readBody(req)).length) throw new HttpError(400, 'UNEXPECTED_FIELDS');
        send(200, await rentals.cancel(uid, cancelRental[1])); return;
      }
      if (url.pathname === '/v1/calendar' && req.method === 'GET') {
        send(200, calendar ? await calendar.status(uid) : { configured: false, connected: false, state: 'Setup required' }); return;
      }
      const calendarAction = /^\/v1\/calendar\/(connect|disconnect|sync)$/.exec(url.pathname);
      if (calendarAction && req.method === 'POST') {
        if (!calendar) throw new HttpError(503, 'CALENDAR_SETUP_REQUIRED');
        if (Object.keys(await readBody(req)).length) throw new HttpError(400, 'UNEXPECTED_FIELDS');
        send(200, await calendar[calendarAction[1]](uid)); return;
      }
      if (packages && url.pathname === '/v1/package-gowns' && req.method === 'GET') {
        send(200, await packages.gowns(uid)); return;
      }
      if (packages && url.pathname === '/v1/package-gown-limit' && req.method === 'GET') {
        if (url.search) throw new HttpError(400, 'INVALID_PACKAGE_GOWNS');
        send(200, await packages.gownLimit(uid)); return;
      }
      if(packages&&url.pathname==='/v1/package-availability'&&req.method==='POST') {
        if(url.search)throw new HttpError(400,'INVALID_SELECTION');
        send(200,await packages.availability(uid,await readBody(req)));return;
      }
      if (packages && url.pathname === '/v1/packages') {
        if (req.method === 'GET') { send(200, await packages.catalogue(uid, url.searchParams.get('serviceTypes') === '1')); return; }
        if (req.method === 'POST') { send(200, await packages.save(uid, await readBody(req, false, 65536))); return; }
      }
      if (packages && url.pathname === '/v1/package-selections') {
        if (req.method === 'GET') { send(200, await packages.selections(uid)); return; }
        if (req.method === 'POST') { send(201, await packages.select(uid, await readBody(req, false, 65536))); return; }
      }
      const assignedFitting=/^\/v1\/package-selections\/([a-f0-9]{32})\/assigned-fitting$/.exec(url.pathname);
      if(packages&&assignedFitting&&req.method==='GET'){
        if(url.search)throw new HttpError(400,'INVALID_FITTING_RESULT');
        send(200,await packages.assignedFitting(uid,assignedFitting[1]));return;
      }
      const completedFittings=/^\/v1\/package-selections\/([a-f0-9]{32})\/completed-fitting$/.exec(url.pathname);
      if(packages&&completedFittings&&['GET','POST'].includes(req.method)){
        if(url.search)throw new HttpError(400,'INVALID_COMPLETED_FITTING');
        send(200,req.method==='GET'?await packages.completedFittings(uid,completedFittings[1]):
          await packages.linkCompletedFitting(uid,completedFittings[1],await readBody(req)));
        return;
      }
      const serviceProgress=/^\/v1\/package-selections\/([a-f0-9]{32})\/service-progress$/.exec(url.pathname);
      if(packages&&serviceProgress&&req.method==='POST'){
        if(url.search)throw new HttpError(400,'INVALID_SERVICE_PROGRESS');
        send(200,await packages.serviceProgress(uid,serviceProgress[1],await readBody(req)));return;
      }
      const deletePackage = /^\/v1\/packages\/([A-Za-z0-9_-]{1,150})\/delete$/.exec(url.pathname);
      if (packages && deletePackage && req.method === 'POST') {
        send(200, await packages.remove(uid, deletePackage[1], await readBody(req))); return;
      }
      const packageAction = /^\/v1\/package-selections\/([a-f0-9]{32})\/(book|invoice|revise)$/.exec(url.pathname);
      if (packages && packageAction && req.method === 'POST') {
        if (packageAction[2] === 'revise' && url.search) throw new HttpError(400, 'INVALID_SELECTION_REVISION');
        send(200, await packages[packageAction[2]](uid, packageAction[1], await readBody(req, false, packageAction[2] === 'revise' ? 65536 : 8192))); return;
      }
      if (url.pathname === '/v1/invoices') {
        if (req.method === 'GET') { send(200, await service.list(uid)); return; }
        if (req.method === 'POST') { send(201, await service.createQuote(uid, await readBody(req))); return; }
      }
      const match = /^\/v1\/invoices\/([A-Za-z0-9_-]{1,150})\/(checkout|refresh)$/.exec(url.pathname);
      const extensionConsent=/^\/v1\/invoices\/([a-f0-9]{32})\/extension-consent$/.exec(url.pathname);
      if(extensionConsent&&req.method==='POST'){if(url.search)throw new HttpError(400,'EXTENSION_CONSENT_REQUIRED');send(200,await service.acceptExtension(uid,extensionConsent[1],await readBody(req)));return;}
      const singleInvoice=/^\/v1\/invoices\/([A-Za-z0-9_-]{1,150})$/.exec(url.pathname);
      const paymentReview=/^\/v1\/invoices\/([a-f0-9]{32})\/resolve-review$/.exec(url.pathname);
      if(paymentReview&&req.method==='POST'){if(url.search)throw new HttpError(400,'INVALID_PAYMENT_RESOLUTION');send(200,await service.resolveReview(uid,paymentReview[1],await readBody(req)));return;}
      if(singleInvoice && req.method==='GET'){send(200,await service.details(uid,singleInvoice[1]));return;}
      if (match && req.method === 'POST') {
        const body = await readBody(req);
        if (Object.keys(body).some(k=>match[2]!=='checkout' || k!=='paymentMethod')) throw new HttpError(400, 'UNEXPECTED_FIELDS');
        send(200, await service[match[2]](uid, match[1],body)); return;
      }
      throw new HttpError(404, 'NOT_FOUND');
    } catch (error) {
      const status = error instanceof HttpError ? error.status : error instanceof PaymentError ? 400 : 503;
      send(status, { error: error instanceof HttpError || error instanceof PaymentError ? error.code : 'SERVICE_UNAVAILABLE' });
      // No raw error logging: SDK/upstream errors may contain credentials or PII.
    }
  };
}
