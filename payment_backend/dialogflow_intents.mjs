// Local training source. Importing this module never connects to Google or writes an agent.
import {helpGuide} from './support_assistant.mjs';

export const trainingPhrases={
 fitting:{
  en:['How much is a fitting?','Is the first gown trial free?','How long does a dress trial last?','Can the fitting fee be credited towards a package?','Do I pay for a follow-up fitting?'],
  'zh-CN':['试穿婚纱多少钱？','第一次试婚纱免费吗？','试穿需要多久？','试穿费可以抵扣套餐吗？','第二次试穿要收费吗？'],
  ms:['Berapakah fi sesi mencuba gaun?','Adakah sesi mencuba pertama percuma?','Berapa lama sesi mencuba gaun?','Bolehkah fi mencuba ditolak daripada deposit pakej?','Adakah sesi susulan dikenakan bayaran?'],
 },
 payments:{
  en:['How much is the package booking deposit?','When must I pay the remaining balance?','Is security included in the package price?','How much is the refundable gown security?','How does the RM50 credit apply to my deposit?'],
  'zh-CN':['套餐订金是多少？','什么时候结清尾款？','套餐价格包含押金吗？','每件婚纱可退押金多少？','RM50怎样抵扣订金？'],
  ms:['Berapakah deposit tempahan pakej?','Bila perlu bayar baki pakej?','Adakah deposit keselamatan termasuk dalam harga?','Berapakah deposit keselamatan bagi satu gaun?','Bagaimana kredit RM50 digunakan?'],
 },
 dates:{
  en:['How many days can I rent a gown?','Can my wedding be after the return date?','When should I pick up and return the dress?','How long is the cleaning period?','Does saving rental dates reserve inventory?'],
  'zh-CN':['婚纱可以租几天？','婚礼可以在归还日期之后吗？','什么时候取件和归还？','清洗需要多少天？','保存租期会锁库存吗？'],
  ms:['Berapa hari tempoh sewaan gaun?','Bolehkah majlis selepas tarikh pulang?','Bila perlu ambil dan pulangkan gaun?','Berapa lama tempoh pembersihan?','Adakah simpan tarikh mengunci stok?'],
 },
 appointments:{
  en:['How do I book an appointment?','What fitting times are available?','Does staff need to confirm my appointment manually?','When can I book a bridal consultation?','Can I book a fitting after my wedding?'],
  'zh-CN':['怎样预约到店？','有什么试穿时段？','预约需要员工手动确认吗？','怎样预约婚纱咨询？','婚礼后还能预约试穿吗？'],
  ms:['Bagaimana menempah janji temu?','Apakah waktu sesi mencuba?','Perlukah staf mengesahkan janji temu secara manual?','Bagaimana tempah konsultasi pengantin?','Bolehkah sesi mencuba selepas majlis?'],
 },
 cancellation:{
  en:['How do I cancel an appointment?','Can I reschedule a fitting?','What happens if I miss my appointment?','Are refunds automatic after cancellation?','When is gown security returned?'],
  'zh-CN':['怎样取消预约？','可以改试穿时间吗？','没有出席预约会怎样？','取消后会自动退款吗？','婚纱押金什么时候退？'],
  ms:['Bagaimana membatalkan janji temu?','Bolehkah tukar jadual sesi mencuba?','Apa berlaku jika tidak hadir?','Adakah bayaran balik automatik selepas batal?','Bila deposit keselamatan dipulangkan?'],
 },
 accessories:{
  en:['How do I choose accessories?','Can I rent a necklace?','Where can I see ring styles?','Are veils included in the package?','Do different jewellery items have different rental prices?'],
  'zh-CN':['怎样选择配饰？','可以租项链吗？','哪里可以挑选戒指款式？','套餐包含头纱吗？','不同首饰租金不同吗？'],
  ms:['Bagaimana memilih aksesori?','Bolehkah menyewa rantai leher?','Di mana boleh melihat pilihan cincin?','Adakah veil termasuk dalam pakej?','Adakah harga sewa barang kemas berbeza?'],
 },
 sizes:{
  en:['How do I find my gown size?','Where do I enter bust waist and hip measurements?','Are the size ranges actual gown measurements?','Does the size recommendation guarantee a fit?','Can staff help me confirm the size at fitting?'],
  'zh-CN':['怎样找到适合的婚纱尺码？','胸围腰围臀围填在哪里？','尺寸表是这件婚纱的实测吗？','推荐尺码保证合身吗？','试穿时可以确认尺码吗？'],
  ms:['Bagaimana mencari saiz gaun saya?','Di mana masukkan ukuran dada pinggang dan pinggul?','Adakah carta saiz ukuran sebenar gaun?','Adakah cadangan saiz menjamin padanan?','Bolehkah saiz disahkan semasa sesi mencuba?'],
 },
 calendar:{
  en:['How do I connect Google Calendar?','Why is my cancelled appointment still on the calendar?','How long does calendar sync take?','Which appointments appear in Google Calendar?','Does calendar sync confirm a payment?'],
  'zh-CN':['怎样连接Google日历？','为什么取消的预约还在日历？','日历同步要等多久？','什么预约会加进Google日历？','日历同步代表付款成功吗？'],
  ms:['Bagaimana menyambung Google Calendar?','Mengapa janji temu dibatalkan masih dalam kalendar?','Berapa lama penyegerakan kalendar?','Janji temu mana muncul dalam Google Calendar?','Adakah kalendar mengesahkan bayaran?'],
 },
 receipts:{
  en:['Where can I view my payment receipt?','Can I download a receipt as PDF?','How do I save a receipt image?','What should I do when payment is pending?','Does returning from the bank page prove payment success?'],
  'zh-CN':['在哪里查看付款收据？','可以下载PDF收据吗？','怎样保存收据图片？','付款一直待确认怎么办？','从银行网页返回代表付款成功吗？'],
  ms:['Di mana melihat resit bayaran?','Bolehkah muat turun resit PDF?','Bagaimana menyimpan imej resit?','Apa perlu dibuat jika bayaran masih menunggu?','Adakah kembali dari halaman bank bermaksud bayaran berjaya?'],
 },
 ar:{
  en:['How does AR try-on work?','Why is my gown AR preview not showing?','Does AR guarantee that the gown will fit?','Why does the app need camera access?','What if my phone does not support AR?'],
  'zh-CN':['AR虚拟试穿怎样使用？','为什么婚纱AR预览没有显示？','AR保证婚纱合身吗？','为什么需要相机权限？','手机不支持AR怎么办？'],
  ms:['Bagaimana mencuba gaun dengan AR?','Mengapa pratonton AR tidak muncul?','Adakah AR menjamin gaun sesuai?','Mengapa aplikasi perlu akses kamera?','Apa jika telefon tidak menyokong AR?'],
 },
};
const extraPhrases={
 'Luvly.welcome':{en:['Hello','Hi there','What can you help with?','Tell me about Luvly support','Good morning'], 'zh-CN':['你好','您好','你能帮我什么？','客服助手能做什么？','早安'],ms:['Helo','Hai','Apakah bantuan yang tersedia?','Apa fungsi pembantu Luvly?','Selamat pagi']},
 'Luvly.handoff':{en:['I want to speak to staff','Please help with my own order','I was charged twice','I want a refund for my payment','Can a person reply to my question?'],'zh-CN':['我要找人工客服','请帮我检查我的订单','我被重复扣款了','我的付款需要退款','可以让员工回复我吗？'],ms:['Saya mahu bercakap dengan staf','Tolong semak pesanan saya','Saya dicaj dua kali','Saya perlukan bayaran balik','Bolehkah staf membalas soalan saya?']},
};
const moreExamples={
 fitting:{en:['What do you charge for the first bridal try-on?','What is included in a 60-minute Dress Trial?','Is a Bridal Consultation free?','Does attending the fitting give me a credit?','Will an older appointment keep its original fee?'],'zh-CN':['首次到店试婚纱收费多少？','一次试穿是六十分钟吗？','婚纱咨询要付费吗？','到店试穿后能抵扣费用吗？','以前预约会保留原本收费吗？'],ms:['Apakah caj percubaan gaun yang pertama?','Adakah sesi Dress Trial selama sejam?','Adakah Bridal Consultation dikenakan caj?','Adakah saya mendapat kredit selepas hadir?','Adakah tempahan lama mengekalkan fi asal?']},
 payments:{en:['Do I settle the package balance before collection?','Is the refundable security separate from the rental fee?','Explain the fifty percent booking payment','How long is the rental deposit payment deadline?','Can you explain the RM899 package payment breakdown?'],'zh-CN':['取婚纱前需要结清套餐吗？','可退押金和租金分开吗？','百分之五十的预订付款怎样算？','租借订金付款期限是多久？','RM899套餐分几次付款？'],ms:['Perlukah baki dijelaskan sebelum ambil gaun?','Adakah cagaran berasingan daripada sewa?','Terangkan bayaran tempahan lima puluh peratus','Berapa lama tempoh untuk membayar deposit sewaan?','Terangkan pecahan bayaran pakej RM899']},
 dates:{en:['Does the rental period include collection and return days?','May I add an extra rental day?','Can two customers reserve the same gown and size at once?','What happens to stock during cleaning?','When does my selected dress become reserved?'],'zh-CN':['租期包含取件和归还当天吗？','可以加一天租期吗？','同款同尺码婚纱能重复预订吗？','清洗期间婚纱可以租吗？','选中的婚纱什么时候正式保留？'],ms:['Adakah hari ambil dan pulang dikira dalam sewaan?','Boleh tambah satu hari sewaan?','Bolehkah dua pelanggan menempah gaun dan saiz sama serentak?','Adakah stok tersedia semasa pembersihan?','Bilakah gaun pilihan saya dikunci?']},
 appointments:{en:['Where do I choose a time for my boutique visit?','Are appointments shown in Malaysia time?','Do you offer a one oclock fitting slot?','How does the system check staff availability?','Should I fit the dress before collection?'],'zh-CN':['在哪里选择到店时段？','预约时间是马来西亚时间吗？','下午一点可以试穿吗？','系统怎样判断员工有空？','应该在取件前试穿吗？'],ms:['Di mana memilih waktu lawatan butik?','Adakah janji temu menggunakan waktu Malaysia?','Adakah slot mencuba pukul satu petang tersedia?','Bagaimana sistem menyemak ketersediaan staf?','Perlukah mencuba gaun sebelum pengambilan?']},
 cancellation:{en:['Where is the cancel appointment option?','Can I change a booking by cancelling and rebooking?','What is the policy for a paid cancellation?','Are late payments automatically refunded?','Are security deductions reviewed after inspection?'],'zh-CN':['取消预约按钮在哪里？','改期是不是取消后重新预约？','已付款预约取消有什么规定？','逾时付款会自动退款吗？','押金扣款要经过归还检查吗？'],ms:['Di mana pilihan batal janji temu?','Perlukah batal dan tempah semula untuk tukar waktu?','Apakah polisi pembatalan yang sudah dibayar?','Adakah bayaran lewat dipulangkan secara automatik?','Adakah potongan cagaran disemak selepas pemeriksaan?']},
 accessories:{en:['Can I select a ring separately from a necklace?','What happens when I untick accessory rental?','How does the accessory allowance work?','Are the accessory pictures sample styles?','Do I pay only the amount above the accessory allowance?'],'zh-CN':['戒指和项链可以分开挑选吗？','取消勾选配饰租借后会怎样？','套餐配饰额度怎样计算？','首饰照片是示例吗？','配饰超出额度才加价吗？'],ms:['Bolehkah pilih cincin dan rantai secara berasingan?','Apa berlaku apabila sewaan aksesori dinyahpilih?','Bagaimana elaun aksesori digunakan?','Adakah gambar aksesori sekadar contoh?','Adakah hanya lebihan elaun aksesori dikenakan caj?']},
 sizes:{en:['Should I measure in centimetres or inches?','Which body measurements are needed for the size guide?','Are demo size charts guaranteed to match the actual gown?','Should I select a listed size before booking?','Can the chatbot tell me my exact dress size?'],'zh-CN':['测量尺寸用厘米还是英寸？','尺码推荐需要哪些身体数据？','示例尺码一定符合实物吗？','预约前要选择已有尺码吗？','聊天助手能判断我的确切尺码吗？'],ms:['Perlukah ukuran dalam sentimeter atau inci?','Ukuran badan manakah diperlukan untuk panduan saiz?','Adakah carta demo dijamin sama dengan gaun sebenar?','Perlukah pilih saiz yang disenaraikan sebelum tempahan?','Bolehkah chatbot menentukan saiz tepat saya?']},
 calendar:{en:['Where is the Sync now button?','Can I reconnect my Google Calendar?','Are unconfirmed visits added to my calendar?','Do cancelled events disappear immediately?','Does Calendar syncing reserve a wedding gown?'],'zh-CN':['Sync now按钮在哪里？','可以重新连接Google Calendar吗？','未确认预约会同步日历吗？','取消的日历事件会立即消失吗？','日历同步会保留婚纱库存吗？'],ms:['Di mana butang Sync now?','Bolehkah sambung semula Google Calendar?','Adakah lawatan belum disahkan masuk kalendar?','Adakah acara dibatalkan hilang serta-merta?','Adakah penyegerakan menempah stok gaun?']},
 receipts:{en:['Where is the Payments and receipts screen?','Can a receipt be saved as PNG?','Why is there no receipt for an unverified payment?','Should I pay again when the bank page returns?','How do I check a saved invoice payment status?'],'zh-CN':['Payments and receipts在哪里？','收据可以保存成PNG吗？','未核实的付款为什么没有收据？','银行页面返回后应该再付一次吗？','怎样检查已保存账单状态？'],ms:['Di mana skrin Payments and receipts?','Bolehkah resit disimpan sebagai PNG?','Mengapa bayaran belum disahkan tiada resit?','Perlukah bayar lagi selepas kembali dari bank?','Bagaimana menyemak status invois tersimpan?']},
 ar:{en:['Is virtual try-on the same as a real fitting?','How should I position myself for the gown preview?','Does a dress need a linked AR model?','Who can help with a rendering problem?','Does trying on a gown virtually reserve it?'],'zh-CN':['虚拟试穿等于真实试穿吗？','AR预览时应该怎样站位？','婚纱需要关联AR模型吗？','渲染出问题应该找谁？','虚拟试穿会预订婚纱吗？'],ms:['Adakah percubaan maya sama dengan sesi mencuba sebenar?','Bagaimana kedudukan badan untuk pratonton gaun?','Adakah gaun memerlukan model AR yang dipautkan?','Siapa boleh membantu masalah paparan?','Adakah percubaan maya menempah gaun?']},
};
for(const [id,byLanguage] of Object.entries(moreExamples))for(const [lang,phrases] of Object.entries(byLanguage))trainingPhrases[id][lang].push(...phrases);
for(const [lang,phrases] of Object.entries({en:['Could I get some help?','What topics can you answer?','Hello Luvly assistant','I have a bridal question','Help me understand the services'],'zh-CN':['我想了解一些事情','你可以回答什么问题？','你好Luvly助手','我有婚纱相关问题','请介绍可以咨询的服务'],ms:['Boleh bantu saya?','Topik apa yang boleh dijawab?','Helo pembantu Luvly','Saya ada soalan pengantin','Terangkan bantuan yang tersedia']}))extraPhrases['Luvly.welcome'][lang].push(...phrases);
for(const [lang,phrases] of Object.entries({en:['Connect me to a human agent','I need assistance with a specific bill','Please investigate a charge on my account','I want to make a complaint','I need a person to review my booking'],'zh-CN':['请转接人工','我有一张账单需要处理','请调查我账户的扣款','我要投诉','请员工检查我的预约'],ms:['Sambungkan saya kepada ejen manusia','Saya perlukan bantuan untuk bil tertentu','Tolong siasat caj akaun saya','Saya ingin membuat aduan','Saya perlukan staf menyemak tempahan saya']}))extraPhrases['Luvly.handoff'][lang].push(...phrases);
export function dialogflowIntentPlan(){
 const entries=[...helpGuide.articles.map(a=>({name:`Luvly.faq.${a.id}`,phrases:trainingPhrases[a.id],article:a})),
  ...Object.entries(extraPhrases).map(([name,phrases])=>({name,phrases}))];
 return entries.flatMap(({name,phrases,article})=>Object.entries(phrases).map(([languageCode,items])=>{
  const lang={en:'en','zh-CN':'zh',ms:'ms'}[languageCode];
  if(items.length<10 || items.some(s=>!s.trim() || [...s].length>256) || new Set(items).size!==items.length)throw Error('INVALID_TRAINING_PHRASES');
  return {languageCode,intent:{displayName:name,webhookState:'WEBHOOK_STATE_DISABLED',priority:500000,isFallback:false,
   trainingPhrases:items.map(text=>({type:'EXAMPLE',parts:[{text}]})),
   messages:[{text:{text:[article?.answer[lang] ?? 'Please ask a general Luvly question or contact our team.']}}],
  }};
 }));
}
