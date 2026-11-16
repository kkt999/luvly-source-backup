import { createServer } from 'node:http';
import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadEnvFile } from 'node:process';
import { ToyyibPaySandbox } from './toyyibpay.mjs';
import { PaymentService } from './payment_service.mjs';
import { FirestoreStore } from './firestore_store.mjs';
import {withBusinessNotifications} from './business_notifications.mjs';
import { createHandler } from './http_app.mjs';
import { PackageService } from './package_service.mjs';
import { CalendarService, GoogleCalendarGateway } from './calendar_service.mjs';
import { RentalService } from './rental_service.mjs';
import { PackageRentals } from './package_rentals.mjs';
import {BookingService} from './booking_service.mjs';
import {gmailMail} from './appointment_mail.mjs';
import {SupportAssistant,helpGuide} from './support_assistant.mjs';
import {geminiConfig,GeminiHelpGateway} from './gemini_assistant.mjs';
import {PromotionService} from './promotions.mjs';
import {AnalyticsService} from './analytics.mjs';
import {AnalyticsEvents} from './analytics_events.mjs';
import {CustomerPlanningService} from './customer_planning.mjs';
import {FittingWorkflow} from './fitting_workflow.mjs';
import {DirectoryService} from './directory_service.mjs';
import {WorkforceService} from './workforce.mjs';
import {StaffAccountsService,FirebaseStaffAuth,StaffSetupMailer} from './staff_accounts.mjs';
import {StaffWorkspaceService} from './staff_workspace.mjs';
import {ProfilePhotosService} from './profile_photos.mjs';
import {RecommendationProfilesService} from './recommendation_profiles.mjs';
import {CustomerReviews} from './customer_reviews.mjs';
import {ReviewMediaBucket} from './review_media.mjs';
import {ReviewTextModeration} from './review_text_moderation.mjs';
import {prepareCloudConfig,maintenance,scheduledHandler} from './cloud_runtime.mjs';
import {FirestoreCalendarCoordination} from './calendar_coordination.mjs';

const directory = dirname(fileURLToPath(import.meta.url));
if (existsSync(resolve(directory, '.env'))) loadEnvFile(resolve(directory, '.env'));
try {
  const env = process.env;
  const secretDirectory=prepareCloudConfig(env)??resolve(directory,'secrets');
  const cloud=!!env.K_SERVICE;
  if (env.TOYYIBPAY_ENV !== 'sandbox' || env.FIREBASE_PROJECT_ID !== 'luvly-44c77' ||
      !env.TOYYIBPAY_SECRET_KEY || !cloud&&!env.GOOGLE_APPLICATION_CREDENTIALS) throw new Error('CONFIG_REQUIRED');
  const base = new URL(env.PAYMENT_RETURN_URL);
  const callback = new URL(env.PAYMENT_CALLBACK_URL);
  if (base.protocol !== 'https:' || base.pathname !== '/return' || callback.origin !== base.origin ||
      callback.pathname !== '/callback' || base.search || callback.search) throw new Error('PUBLIC_HTTPS_REQUIRED');
  const credential = cloud?null:JSON.parse(readFileSync(resolve(directory, env.GOOGLE_APPLICATION_CREDENTIALS), 'utf8'));
  if (credential && credential.project_id !== 'luvly-44c77') throw new Error('WRONG_PROJECT');
  // Import after configuration validation so missing setup fails safely.
  const { initializeApp, cert,applicationDefault } = await import('firebase-admin/app');
  const { getAuth } = await import('firebase-admin/auth');
  const { getFirestore } = await import('firebase-admin/firestore');
  const app = initializeApp({ credential: cloud?applicationDefault():cert(credential), projectId: 'luvly-44c77' });
  const gateway = new ToyyibPaySandbox({ secretKey: env.TOYYIBPAY_SECRET_KEY,
    categoryCode: env.TOYYIBPAY_CATEGORY_CODE, environment: env.TOYYIBPAY_ENV });
  const store = withBusinessNotifications(new FirestoreStore(getFirestore(app)));
  const rentals = new RentalService({ store });
  const workforce=new WorkforceService({store});
  const bookings=new BookingService({store,feePolicy:true,workforce});
  const service = new PaymentService({ store, gateway, rentals,bookings,
    returnUrl: env.PAYMENT_RETURN_URL, callbackUrl: env.PAYMENT_CALLBACK_URL });
  const origins = (env.PAYMENT_ALLOWED_ORIGINS ?? '').split(',').map(s => s.trim()).filter(Boolean);
  const port = Number(cloud?env.PORT:env.PAYMENT_PORT ?? 8787);
  if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('INVALID_PORT');
  const packages = new PackageService({ store, paymentService: service,bookings });
  const promotions=new PromotionService({store,access:uid=>service.access(uid)});
  const analytics=new AnalyticsService({store,access:uid=>service.access(uid)});
  const analyticsEvents=new AnalyticsEvents({store,access:uid=>service.access(uid)});
  const customerPlanning=new CustomerPlanningService({store,access:uid=>service.access(uid)});
  const fittingWorkflow=new FittingWorkflow({store});
  const directoryService=new DirectoryService({store,access:uid=>service.access(uid)});
  const packageRentals = new PackageRentals({store,rentals,paymentPolicy:true});
  const assistant=new SupportAssistant({store,access:uid=>service.access(uid),provider:'Gemini',consentVersion:3,
    config:()=>geminiConfig(resolve(secretDirectory,'gemini-config.json')),gateway:config=>new GeminiHelpGateway(config,{guide:helpGuide})});
  let mail;
  try{mail=gmailMail(getFirestore(app),resolve(secretDirectory,'mail-config.json'));}
  catch{console.error('Appointment email setup unavailable; bookings remain active.');}
  const staffAccounts=new StaffAccountsService({store,auth:new FirebaseStaffAuth(getAuth(app)),
    mailer:mail?new StaffSetupMailer({transport:mail.transport,from:mail.from}):null});
  const workspace=new StaffWorkspaceService({store,auth:new FirebaseStaffAuth(getAuth(app))});
  const profilePhotos=new ProfilePhotosService({store,access:(tx,uid)=>workspace.account(tx,uid)});
  const recommendationProfiles=new RecommendationProfilesService({store,access:(tx,uid)=>workspace.account(tx,uid)});
  const {getStorage}=await import('firebase-admin/storage');
  const reviewModerator=new ReviewTextModeration({store,config:()=>geminiConfig(resolve(secretDirectory,'gemini-config.json'))});
  const reviews=new CustomerReviews({store,moderator:reviewModerator,bucket:new ReviewMediaBucket(getStorage(app).bucket('luvly-44c77.firebasestorage.app'))});
  let calendar;
  const calendarConfig = resolve(secretDirectory, 'calendar-config.json');
  if (existsSync(calendarConfig)) {
    try {
      const config = JSON.parse(readFileSync(calendarConfig, 'utf8'));
      if (config.enabled === true) {
        const oauth = JSON.parse(readFileSync(resolve(secretDirectory, 'google-calendar-oauth.json'), 'utf8')).web;
        if (new URL(config.redirectUri).origin !== base.origin) throw Error('STALE_CALENDAR_ENDPOINT');
        calendar = new CalendarService({ db: getFirestore(app), auth: getAuth(app),
          gateway: new GoogleCalendarGateway({ credential: oauth, redirectUri: config.redirectUri }),
          coordination:cloud?new FirestoreCalendarCoordination({db:getFirestore(app)}):null,
          key: readFileSync(resolve(secretDirectory, 'calendar-token.key')) });
      }
    } catch { console.error('Calendar setup unavailable; payment and package services remain active.'); }
  }
  const handler=createHandler({ service, packages, packageRentals, calendar, rentals, bookings, workforce, staffAccounts, workspace, profilePhotos, recommendationProfiles, reviews, assistant, promotions, analytics, analyticsEvents, customerPlanning, fittingWorkflow, directory:directoryService, verifyToken: token => getAuth(app).verifyIdToken(token, true), allowedOrigins: origins });
  const server = createServer(cloud?scheduledHandler({handler,run:()=>maintenance({db:getFirestore(app),store,rentals,bookings,calendar,mail,reviews}),audience:env.MAINTENANCE_AUDIENCE,email:env.MAINTENANCE_EMAIL}):handler);
  server.requestTimeout = 120000; // Authenticated, two-at-a-time 20 MB review uploads.
  server.headersTimeout = 15000;
  server.timeout = 30000;
  server.maxHeadersCount = 30;
  server.on('close',()=>analyticsEvents.close());
  if(!cloud){const stopReviews=reviews.start();server.on('close',stopReviews);}
  // Loopback only. A separately approved tunnel forwards to this port.
  server.listen(port, cloud?'0.0.0.0':'127.0.0.1', () => {
    console.log(`Luvly SANDBOX backend ready (${cloud?'cloud':'local'}).`);
    if(cloud)return; // Cloud Scheduler owns awaited maintenance, even at scale zero.
    if (calendar) { const stop = calendar.start(); server.on('close', stop); }
    const stopRentals = rentals.start(); server.on('close', stopRentals);
    const stopBookings=bookings.start();server.on('close',stopBookings);
    if(mail){const stopMail=mail.start();server.on('close',stopMail);}
  });
  server.on('error', () => { console.error('Payment server could not start. Check the port.'); process.exitCode = 1; });
} catch {
  console.error('Sandbox setup incomplete. Check payment_backend/.env, public HTTPS URLs and local Firebase service-account JSON. No server started. Do not share those secret files.');
  process.exitCode = 1;
}
