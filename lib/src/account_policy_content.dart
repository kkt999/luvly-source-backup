const accountTermsVersion = '2026-11-03.1';

// Describe implemented behaviour. Do not promise automatic deletion, physical
// fit, real bank settlement or features that the application does not provide.
const accountTermsSections = <(String, String)>[
  (
    'About this notice',
    'Luvly provides gown discovery, visual previews, fitting appointments and rental management. '
        'These terms and privacy notice explain how the service and your information are used. '
        'Effective 3 November 2026. Version $accountTermsVersion. Optional permissions are requested separately when you use those features.',
  ),
  (
    '1. Your account and contact details',
    'Provide an email address you control and accurate name and phone details so we can manage your account and visits. '
        'Keep your password private and sign out on shared devices. Required registration details are needed to create and manage your account; '
        'profile notes, contact preferences, profile photos and body information are optional. '
        'Firebase Authentication manages sign-in credentials; your password is not stored in your Firestore profile. '
        'Linking Google for sign-in does not grant Luvly access to your Gmail or Calendar.',
  ),
  (
    '2. Body information and recommendations',
    'Measurements and style, colour and budget preferences you save are stored in your private recommendation profile in Firestore. '
        'They support your saved preferences and optional styling suggestions. The manual proportion guide uses simplified rules. '
        'Android has optional camera tools for joint-span proportions and for approximate bust, waist and hip measurements from front and side views. '
        'Scan frames are processed on your phone and are not saved or uploaded. Saving a proportion scan stores ratios and scan stability metadata in your private profile. '
        'Circumference estimates stay in the review session until you check them with a tape and choose to copy them. Save body information stores the checked values as body measurements. '
        'An optional comparison of two scans stays in the review session; only the scan you choose can be saved. Similar scans do not establish measurement accuracy. '
        'You can remove the scan and save to clear it, and separately choose whether to use it for styling suggestions. Camera estimates are not included in Manager statistics. '
        'Neither guide is a medical assessment or guaranteed size prediction. You can edit or clear measurements in Profile > Body information and change styling preferences in recommendations. '
        'Your private recommendation measurements are not included in Manager reports. Measurements separately taken and recorded by staff during a fitting '
        'form part of your rental service record and may be accessed by authorised staff handling the service.',
  ),
  (
    '3. Optional boutique statistics',
    'The separate “Include my guide in boutique statistics” switch is off by default. If you enable it and save, '
        'the server adds your approximate proportion category to current aggregate counts and percentages for the Manager. '
        'That report does not show your name or raw measurements. Switch it off and save to withdraw; disabling the guide or clearing required measurements '
        'also removes your category from the current counts. This choice does not prevent you from using personal recommendations. '
        'It does not remove a report that someone has already exported.',
  ),
  (
    '4. Camera, AR and saved looks',
    'Body try-on processes live camera frames on your Android device. Luvly does not upload those frames as part of body tracking. '
        'Camera permission is optional; declining it prevents camera try-on, not the other account features. '
        'Saved try-on photos stay in account-associated app storage on that phone, with no Luvly cloud backup. '
        'Remove them in Try-on history; uninstalling can remove them. If you export or share a photo or a diagnostic trace, the destination receives that file. '
        'Diagnostic traces can include tracking and performance metrics. Room AR opens a model in a supported browser/viewer and may request its own camera or spatial permissions. '
        'Avoid including other people without permission.',
  ),
  (
    '5. What a preview and selection mean',
    'AR and 360° views are visual references. Tracking, lighting, the model and your screen affect the result; they do not measure physical fit or reserve stock. '
        'Confirm the actual gown, colour, size, condition, adjustments and rental dates with the team. '
        'A saved package or gown selection is a preference. The final proposal, customer acceptance, stock check and verified booking deposit are separate steps. '
        'Follow the availability and payment deadlines shown for your rental.',
  ),
  (
    '6. Profile photo and review media',
    'An optional profile photo is resized and re-encoded by the app and saved in an owner-only Firestore photo record. '
        'It is separate from review media and is not automatically published with a review. You can replace or remove it in Personal profile. '
        'Photos and videos attached to reviews are uploaded through the authenticated backend to Firebase Storage; review text, stars and moderation records are stored in Firestore. '
        'These cloud records can be available on another device after you sign in. App-prepared photos are re-encoded, but original video metadata may remain. '
        'Check your files and remove private information before uploading.',
  ),
  (
    '7. Publishing reviews, safety checks and reports',
    'Eligible customers can review a completed rental. Published reviews show the review author name, stars, text and attached media to other signed-in customers and authorised staff. '
        'Review publication requires its own agreement. Review text may be sent to Google Gemini for a safety check; photos, video, stars and order details are not sent to Gemini by that check. '
        'Do not include contact details, account references or other private information in the text. Local checks may block explicit abuse; uncertain or unavailable AI checks leave content awaiting staff approval. '
        'Honest negative reviews and low ratings are allowed. Authorised staff and Managers may handle reports, hide policy-breaking content or publish a reply, but cannot rewrite your stars or words. '
        'Use My reviews to edit or withdraw a review and Report to flag another review. Withdrawal hides it from customer view; it does not erase all cloud, moderation or report records.',
  ),
  (
    '8. Support and optional AI assistance',
    'Support messages and replies are stored in Firestore for you and authorised team members to handle the conversation. '
        'Assistant chats are saved to your Luvly account in Firestore and are available through your conversation history. Staff cannot browse your assistant history. '
        'You can permanently remove a chat and its messages from that history. Deleting a chat does not recall content already sent to Gemini or voluntarily shared in a support ticket. '
        'If you opt into the Gemini assistant, Google receives your question, up to four recent questions from that conversation and the help guide; '
        'the assistant does not receive your account records or have authority to change bookings, payments or stock. '
        'Provider handling depends on the applicable Google service terms; unpaid Gemini services may use content to improve products and may involve human review. '
        'Avoid personal or confidential information. You can use the help guide without sending a question to AI, switch AI off, or contact the team directly. '
        'An assistant excerpt is shared with the team only after you review and send a support ticket. AI answers can be wrong.',
  ),
  (
    '9. Google Calendar and notifications',
    'Calendar linking is a separate, optional Google permission. It synchronises appointment information such as visit type, date, time and status '
        'to a Luvly-created calendar; it is separate from Google sign-in. The backend stores the connection and an encrypted refresh credential to continue syncing. '
        'Disconnect in Profile > Google Calendar to stop future sync and remove the stored refresh credential. Existing Google calendars or events are not automatically deleted. '
        'Appointment emails use your saved contact information. In-app notifications show supported account and service updates; they are not phone push notifications.',
  ),
  (
    '10. Appointments, payments and rental records',
    'Review the fee, rental dates, proposal, cancellation conditions and deadlines shown before confirming or paying. '
        'The first fitting fee is for the appointment session, not each gown. An eligible attended fitting may earn the one-time credit shown in your package. '
        'Refundable security is separate from the rental price and is reviewed after return inspection and any agreed deductions. '
        'Refund records in Luvly do not themselves transfer money to a bank account. '
        'Online checkout currently uses ToyyibPay’s test environment. Test payments do not debit your bank account. '
        'ToyyibPay receives the bill amount, reference and required payer/contact details to operate that checkout. '
        'Luvly stores invoice references, verified status, amounts and receipts, not your bank password or payment-card details. Never enter real banking credentials in a test payment flow.',
  ),
  (
    '11. Cloud processing and access',
    'Google Firebase Authentication, Firestore and Storage support accounts, service records and uploaded review media. '
        'Google Cloud Run hosts the authenticated backend, with scheduled service processing, server-side secrets and operational logging. '
        'Technical logs may include request, error and network metadata. Information can be processed outside Malaysia on the providers’ infrastructure. '
        'Google Calendar, Gmail delivery, Google Gemini and ToyyibPay process the information needed for their respective features. '
        'Cloud storage is not unrestricted public access: app access depends on sign-in, ownership, publication state and staff permissions. '
        'No system can promise absolute security; keep sensitive information out of free-text notes, public reviews and AI questions.',
  ),
  (
    '12. Your choices, retention and privacy requests',
    'You can change supported profile details, replace or remove a profile photo, clear body measurements, withdraw statistics participation, '
        'delete local saved looks, withdraw a review, decline AI, revoke device permissions or disconnect Calendar. '
        'Signing out or uninstalling does not delete cloud records. Self-service account deletion and a fixed automatic cloud purge schedule are not currently available. '
        'For access, correction, deletion, consent withdrawal or a privacy complaint, use Support > New message > Account and state your request. '
        'Before creating an account, contact the person or team who provided you access to Luvly. Do not send a password or verification code. '
        'The team must review requests and explain any records retained for unresolved rental, payment, security or reported-content matters; we do not promise instant deletion of every record or backup.',
  ),
  (
    'Your agreement',
    'Read this notice before deciding whether to create an account. “I agree” records your choice on this registration screen; simply opening, scrolling or closing this notice does not accept it. '
        'General account agreement does not switch on optional statistics, AI, review publication, camera or Calendar permissions. '
        'The current notice is also available in Profile > Terms & privacy. Contact the team if something is unclear.',
  ),
];

const accountTermsSectionsMalay = <(String, String)>[
  (
    'Tentang notis ini',
    'Luvly menyediakan carian gaun, pratonton visual, janji temu mencuba pakaian dan pengurusan sewaan. '
        'Terma dan notis privasi ini menerangkan penggunaan perkhidmatan serta maklumat anda. '
        'Berkuat kuasa 3 November 2026. Versi $accountTermsVersion. Kebenaran pilihan diminta secara berasingan apabila anda menggunakan ciri berkenaan.',
  ),
  (
    '1. Akaun dan maklumat hubungan',
    'Gunakan alamat e-mel yang anda kawal serta nama dan nombor telefon yang tepat untuk mengurus akaun dan lawatan. '
        'Rahsiakan kata laluan dan log keluar pada peranti yang dikongsi. Maklumat pendaftaran wajib diperlukan untuk membuka dan mengurus akaun; '
        'nota profil, pilihan hubungan, foto profil dan maklumat badan adalah pilihan. '
        'Firebase Authentication mengurus kelayakan log masuk; kata laluan tidak disimpan dalam profil Firestore anda. '
        'Memautkan Google untuk log masuk tidak memberi Luvly akses kepada Gmail atau Calendar anda.',
  ),
  (
    '2. Maklumat badan dan cadangan',
    'Ukuran serta pilihan gaya, warna dan bajet yang disimpan berada dalam profil cadangan peribadi anda di Firestore. '
        'Maklumat ini menyokong pilihan tersimpan dan cadangan gaya pilihan. Panduan perkadaran manual menggunakan peraturan ringkas. '
        'Imbasan kamera Android pilihan menganggarkan nisbah rentang sendi bahu/pinggul dan torso, bukan ukuran lilitan atau sentimeter yang tepat. '
        'Bingkai imbasan diproses pada telefon dan tidak disimpan atau dimuat naik. Selepas semakan, Save body information hanya menyimpan nisbah dan metadata kestabilan dalam profil peribadi anda. '
        'Perbandingan pilihan antara dua imbasan kekal dalam sesi semakan; hanya imbasan yang anda pilih boleh disimpan. Imbasan yang serupa tidak membuktikan ketepatan ukuran. '
        'Anda boleh membuang imbasan dan menyimpan untuk memadamnya, serta memilih secara berasingan sama ada ia digunakan untuk cadangan gaya. Anggaran kamera tidak dimasukkan dalam statistik Manager. '
        'Kedua-dua panduan bukan penilaian perubatan atau jaminan saiz. Anda boleh mengubah atau mengosongkan ukuran di Profile > Body information dan mengubah pilihan gaya dalam cadangan. '
        'Ukuran peribadi dalam profil cadangan tidak dimasukkan dalam laporan Manager. Ukuran yang diambil dan direkodkan secara berasingan oleh staf semasa sesi mencuba '
        'menjadi sebahagian rekod perkhidmatan sewaan dan boleh diakses oleh staf yang diberi kuasa untuk mengendalikan perkhidmatan itu.',
  ),
  (
    '3. Statistik butik secara pilihan',
    'Suis berasingan “Include my guide in boutique statistics” dimatikan secara lalai. Jika anda menghidupkan dan menyimpannya, '
        'pelayan memasukkan kategori anggaran perkadaran anda dalam jumlah dan peratusan semasa untuk Manager. '
        'Laporan itu tidak memaparkan nama atau ukuran asal anda. Matikan suis dan simpan untuk menarik diri; mematikan panduan atau mengosongkan ukuran wajib '
        'juga mengeluarkan kategori anda daripada jumlah semasa. Pilihan ini tidak menghalang cadangan peribadi. '
        'Ia tidak memadam laporan yang telah dieksport oleh seseorang.',
  ),
  (
    '4. Kamera, AR dan foto tersimpan',
    'Ciri mencuba pakaian pada badan memproses bingkai kamera langsung pada peranti Android anda. Luvly tidak memuat naik bingkai itu untuk penjejakan badan. '
        'Kebenaran kamera adalah pilihan; jika ditolak, ciri kamera tidak dapat digunakan tetapi ciri akaun lain tidak terjejas. '
        'Foto cuba pakai disimpan dalam storan aplikasi yang dikaitkan dengan akaun pada telefon itu, tanpa sandaran awan Luvly. '
        'Padamkannya di Try-on history; menyahpasang aplikasi boleh memadam foto tersebut. Jika anda mengeksport atau berkongsi foto atau jejak diagnostik, destinasi menerima fail itu. '
        'Jejak diagnostik boleh mengandungi metrik penjejakan dan prestasi. Room AR membuka model dalam pelayar/pemapar yang disokong dan mungkin meminta kebenaran kamera atau ruangnya sendiri. '
        'Elakkan merakam orang lain tanpa izin.',
  ),
  (
    '5. Maksud pratonton dan pilihan',
    'AR dan paparan 360° ialah rujukan visual. Penjejakan, pencahayaan, model dan skrin mempengaruhi hasil; ia tidak mengukur kesesuaian fizikal atau menempah stok. '
        'Sahkan gaun sebenar, warna, saiz, keadaan, pengubahsuaian dan tarikh sewaan dengan staf. '
        'Pakej atau gaun yang disimpan ialah pilihan awal. Cadangan akhir, penerimaan pelanggan, semakan stok dan deposit tempahan yang disahkan ialah langkah berasingan. '
        'Patuhi ketersediaan serta tarikh akhir bayaran yang dipaparkan untuk sewaan anda.',
  ),
  (
    '6. Foto profil dan media ulasan',
    'Foto profil pilihan diubah saiz dan dikod semula oleh aplikasi, kemudian disimpan dalam rekod foto Firestore untuk pemilik sahaja. '
        'Ia berasingan daripada media ulasan dan tidak diterbitkan secara automatik bersama ulasan. Ganti atau padamkannya di Personal profile. '
        'Foto dan video ulasan dimuat naik melalui pelayan yang memerlukan pengesahan ke Firebase Storage; teks, bintang dan rekod penyederhanaan disimpan di Firestore. '
        'Rekod awan ini boleh tersedia pada peranti lain selepas log masuk. Foto yang disediakan aplikasi dikod semula, tetapi metadata video asal mungkin kekal. '
        'Semak fail dan buang maklumat peribadi sebelum memuat naik.',
  ),
  (
    '7. Penerbitan ulasan, semakan keselamatan dan laporan',
    'Pelanggan yang layak boleh mengulas sewaan yang telah selesai. Ulasan diterbitkan memaparkan nama penulis, bintang, teks dan media kepada pelanggan lain yang telah log masuk serta staf yang diberi kuasa. '
        'Penerbitan memerlukan persetujuan tersendiri. Teks ulasan mungkin dihantar kepada Google Gemini untuk semakan keselamatan; foto, video, bintang dan butiran pesanan tidak dihantar oleh semakan ini. '
        'Jangan masukkan maklumat hubungan, rujukan akaun atau maklumat peribadi lain. Semakan setempat boleh menyekat bahasa kesat yang jelas; jika semakan AI tidak pasti atau tidak tersedia, kandungan menunggu kelulusan staf. '
        'Ulasan negatif yang jujur dan penilaian rendah dibenarkan. Staf yang diberi kuasa serta Manager boleh mengurus laporan, menyembunyikan kandungan yang melanggar dasar atau menerbitkan balasan, tetapi tidak boleh menulis semula bintang atau kata-kata anda. '
        'Gunakan My reviews untuk mengubah atau menarik balik ulasan dan Report untuk melaporkan ulasan lain. Penarikan balik menyembunyikannya daripada pelanggan; ia tidak memadam semua rekod awan, penyederhanaan atau laporan.',
  ),
  (
    '8. Sokongan dan bantuan AI pilihan',
    'Mesej sokongan dan balasan disimpan di Firestore untuk anda serta pasukan yang diberi kuasa mengendalikan perbualan. '
        'Perbualan pembantu disimpan dalam akaun Luvly anda di Firestore dan boleh dibuka melalui sejarah perbualan. Staf tidak boleh melihat sejarah pembantu anda. '
        'Anda boleh memadamkan perbualan dan mesejnya daripada sejarah tersebut. Pemadaman tidak menarik balik kandungan yang telah dihantar ke Gemini atau dikongsi melalui tiket sokongan. '
        'Jika anda memilih pembantu Gemini, Google menerima soalan anda, sehingga empat soalan terkini daripada perbualan itu dan panduan bantuan; '
        'pembantu tidak menerima rekod akaun atau mempunyai kuasa mengubah tempahan, bayaran atau stok. '
        'Pengendalian oleh penyedia bergantung pada terma perkhidmatan Google yang berkenaan; perkhidmatan Gemini tanpa bayaran mungkin menggunakan kandungan untuk menambah baik produk dan melibatkan semakan manusia. '
        'Elakkan maklumat peribadi atau sulit. Anda boleh menggunakan panduan tanpa menghantar soalan kepada AI, mematikan AI atau menghubungi staf secara langsung. '
        'Petikan perbualan pembantu hanya dikongsi dengan staf selepas anda menyemak dan menghantar tiket sokongan. Jawapan AI boleh tersilap.',
  ),
  (
    '9. Google Calendar dan pemberitahuan',
    'Pautan Calendar ialah kebenaran Google berasingan yang bersifat pilihan. Ia menyegerakkan maklumat janji temu seperti jenis lawatan, tarikh, masa dan status '
        'ke kalendar yang dicipta oleh Luvly; ia berasingan daripada log masuk Google. Pelayan menyimpan sambungan dan kelayakan penyegaran yang disulitkan untuk meneruskan penyegerakan. '
        'Putuskan sambungan di Profile > Google Calendar untuk menghentikan penyegerakan akan datang dan membuang kelayakan penyegaran tersimpan. Kalendar atau acara Google sedia ada tidak dipadam secara automatik. '
        'E-mel janji temu menggunakan maklumat hubungan tersimpan. Pemberitahuan dalam aplikasi memaparkan kemas kini akaun dan perkhidmatan yang disokong; ia bukan pemberitahuan tolak telefon.',
  ),
  (
    '10. Janji temu, bayaran dan rekod sewaan',
    'Semak fi, tarikh sewaan, cadangan, syarat pembatalan dan tarikh akhir sebelum mengesahkan atau membayar. '
        'Fi sesi mencuba pertama adalah untuk sesi janji temu, bukan setiap gaun. Kehadiran yang layak mungkin mendapat kredit sekali seperti dipaparkan dalam pakej. '
        'Deposit keselamatan boleh dipulangkan adalah berasingan daripada harga sewaan dan disemak selepas pemeriksaan pemulangan serta potongan yang dipersetujui. '
        'Rekod bayaran balik dalam Luvly tidak memindahkan wang ke akaun bank dengan sendirinya. '
        'Pembayaran dalam talian kini menggunakan persekitaran ujian ToyyibPay. Bayaran ujian tidak mendebit akaun bank anda. '
        'ToyyibPay menerima amaun bil, rujukan dan butiran pembayar/hubungan yang diperlukan untuk pembayaran itu. '
        'Luvly menyimpan rujukan invois, status disahkan, amaun dan resit, bukan kata laluan bank atau butiran kad bayaran. Jangan masukkan kelayakan perbankan sebenar dalam aliran bayaran ujian.',
  ),
  (
    '11. Pemprosesan awan dan akses',
    'Google Firebase Authentication, Firestore dan Storage menyokong akaun, rekod perkhidmatan dan media ulasan yang dimuat naik. '
        'Google Cloud Run menjadi hos pelayan yang memerlukan pengesahan, dengan pemprosesan berjadual, rahsia pelayan dan log operasi. '
        'Log teknikal mungkin merangkumi metadata permintaan, ralat dan rangkaian. Maklumat boleh diproses di luar Malaysia pada infrastruktur penyedia. '
        'Google Calendar, penghantaran Gmail, Google Gemini dan ToyyibPay memproses maklumat yang diperlukan untuk ciri masing-masing. '
        'Storan awan bukan akses awam tanpa had: akses aplikasi bergantung pada log masuk, pemilikan, status penerbitan dan kebenaran staf. '
        'Tiada sistem boleh menjamin keselamatan mutlak; jangan masukkan maklumat sensitif dalam nota bebas, ulasan awam atau soalan AI.',
  ),
  (
    '12. Pilihan, penyimpanan dan permintaan privasi',
    'Anda boleh mengubah butiran profil yang disokong, mengganti atau membuang foto profil, mengosongkan ukuran badan, menarik diri daripada statistik, '
        'memadam foto setempat, menarik balik ulasan, menolak AI, membatalkan kebenaran peranti atau memutuskan Calendar. '
        'Log keluar atau menyahpasang aplikasi tidak memadam rekod awan. Pemadaman akaun secara layan diri dan jadual pembersihan awan automatik yang tetap belum tersedia. '
        'Untuk akses, pembetulan, pemadaman, penarikan persetujuan atau aduan privasi, gunakan Support > New message > Account dan nyatakan permintaan anda. '
        'Sebelum membuka akaun, hubungi orang atau pasukan yang memberi anda akses kepada Luvly. Jangan hantar kata laluan atau kod pengesahan. '
        'Pasukan perlu menyemak permintaan dan menjelaskan rekod yang dikekalkan untuk urusan sewaan, bayaran, keselamatan atau laporan kandungan yang belum selesai; kami tidak menjanjikan pemadaman serta-merta semua rekod atau sandaran.',
  ),
  (
    'Persetujuan anda',
    'Baca notis ini sebelum membuat keputusan membuka akaun. “Saya setuju” merekod pilihan anda pada skrin pendaftaran ini; membuka, menatal atau menutup notis sahaja tidak bermakna anda bersetuju. '
        'Persetujuan akaun umum tidak menghidupkan statistik pilihan, AI, penerbitan ulasan, kamera atau Calendar. '
        'Notis semasa juga tersedia di Profile > Terms & privacy. Hubungi staf jika ada perkara yang tidak jelas.',
  ),
];
