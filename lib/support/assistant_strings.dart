import 'package:flutter/material.dart';

const assistantPreferences = {
  'auto': '',
  'en': 'English',
  'zh': '中文',
  'ms': 'Bahasa Melayu',
};

bool assistantSupports(String? language) =>
    language != null &&
    language != 'auto' &&
    assistantPreferences.containsKey(language);

String assistantUiLanguage(
  String preference, {
  Locale? application,
  Iterable<Locale> device = const [],
}) {
  if (assistantSupports(preference)) return preference;
  if (assistantSupports(application?.languageCode)) {
    return application!.languageCode;
  }
  for (final locale in device) {
    if (assistantSupports(locale.languageCode)) return locale.languageCode;
  }
  return 'en';
}

class AssistantStrings {
  const AssistantStrings(this.language);
  final String language;

  factory AssistantStrings.of(BuildContext context, String preference) {
    final inherited = Localizations.maybeLocaleOf(context);
    final configured = context
        .findAncestorWidgetOfExactType<MaterialApp>()
        ?.locale;
    // The application has no language picker. Flutter's implicit English
    // fallback still allows Auto to follow a supported device language.
    final application =
        configured ?? (inherited?.languageCode == 'en' ? null : inherited);
    return AssistantStrings(
      assistantUiLanguage(
        preference,
        application: application,
        device: WidgetsBinding.instance.platformDispatcher.locales,
      ),
    );
  }

  String operator [](AssistantText key) => switch (language) {
    'zh' => key.chinese,
    'ms' => key.malay,
    _ => key.english,
  };

  String format(AssistantText key, String value) =>
      this[key].replaceFirst('{value}', value);
}

enum AssistantText {
  dismiss('Dismiss', '关闭此窗口', 'Tutup tetingkap ini'),
  openAssistant('Open Luvly assistant', '打开 Luvly 助手', 'Buka Pembantu Luvly'),
  history('Conversation history', '聊天记录', 'Sejarah perbualan'),
  chatOptions('Chat options', '聊天选项', 'Pilihan perbualan'),
  closeAssistant('Close assistant', '关闭助手', 'Tutup pembantu'),
  aiStatus(
    'AI chat · powered by Gemini',
    'AI 聊天 · 由 Gemini 提供支持',
    'Perbualan AI · dikuasakan oleh Gemini',
  ),
  connecting('Connecting…', '正在连接…', 'Sedang menyambung…'),
  companion('Here to help', '你的婚纱顾问', 'Pembantu pengantin anda'),
  guideAiOff(
    'Help guide · AI is off',
    '帮助指南 · AI 已关闭',
    'Panduan bantuan · AI dimatikan',
  ),
  enableAi('Enable AI', '启用 AI', 'Hidupkan AI'),
  disableAi('Turn AI off', '关闭 AI', 'Matikan AI'),
  contact('Contact the team', '联系 Luvly 团队', 'Hubungi pasukan Luvly'),
  askTeam('Ask the Luvly team', '向 Luvly 团队求助', 'Minta bantuan pasukan Luvly'),
  compareModes(
    'How AI differs from the guide',
    'AI 与帮助指南有什么区别',
    'Perbezaan antara AI dan panduan',
  ),
  newChat('New conversation', '新对话', 'Perbualan baharu'),
  auto('Auto language', '自动选择语言', 'Bahasa automatik'),
  languageSelection(
    'Response and interface language',
    '回复和界面语言',
    'Bahasa jawapan dan antara muka',
  ),
  appName('Luvly Assistant', 'Luvly Assistant', 'Luvly Assistant'),
  loadChatFailed(
    'Couldn’t load your saved chat.',
    '无法加载已保存的对话。',
    'Perbualan yang disimpan tidak dapat dimuatkan.',
  ),
  retry('Retry', '重试', 'Cuba lagi'),
  useOffline(
    'Use offline help guide',
    '使用离线帮助指南',
    'Guna panduan bantuan luar talian',
  ),
  older('Load older messages', '加载更早的消息', 'Muatkan mesej terdahulu'),
  loadingOlder(
    'Loading older messages…',
    '正在加载更早的消息…',
    'Sedang memuatkan mesej terdahulu…',
  ),
  welcome(
    'Hi, I’m your Luvly Assistant. How can I help with your fitting or bridal rental today?',
    '你好！我是 Luvly 智能助手。关于婚纱试穿、租借或配套服务，有什么可以帮你的吗？',
    'Hai! Saya Pembantu Luvly. Ada apa yang boleh saya bantu tentang sesi mencuba gaun atau sewaan pengantin hari ini?',
  ),
  suggestions('You can ask…', '你可以这样问…', 'Anda boleh tanya…'),
  fittingQuestion(
    'How much is a fitting?',
    '试穿需要多少钱？',
    'Berapakah bayaran sesi mencuba gaun?',
  ),
  depositQuestion(
    'How does the deposit work?',
    '婚纱配套订金如何计算？',
    'Bagaimanakah deposit pakej pengantin dikira?',
  ),
  scheduleQuestion(
    'When should I book my fitting?',
    '应该什么时候预约试穿？',
    'Bilakah saya patut menempah sesi mencuba gaun?',
  ),
  checkReply('Check response', '查看回复', 'Semak jawapan'),
  retryMessage('Retry message', '重试这条消息', 'Cuba hantar semula'),
  generating(
    'Understanding your question…',
    '正在理解你的问题…',
    'Sedang memahami soalan anda…',
  ),
  findingGuide(
    'Finding a guide topic…',
    '正在查找相关指南…',
    'Sedang mencari topik panduan…',
  ),
  restoreToChat(
    'Restore to continue chatting',
    '恢复对话后继续聊天',
    'Pulihkan untuk meneruskan perbualan',
  ),
  composer('Message Luvly…', '向 Luvly 提问…', 'Tanya Luvly…'),
  send('Send question', '发送问题', 'Hantar soalan'),
  sendEmpty(
    'Enter a question to send.',
    '输入问题后即可发送。',
    'Taip soalan untuk dihantar.',
  ),
  offlineSaved(
    'Offline help guide · messages are not saved.',
    '离线帮助指南 · 消息只在当前窗口显示。',
    'Panduan luar talian · mesej tidak disimpan.',
  ),
  aiReminder(
    'AI can make mistakes. Check policies. Don’t share personal details.',
    'AI 可能出错。请核对 Luvly 政策，避免分享个人资料。',
    'AI boleh tersilap. Semak dasar Luvly. Jangan kongsi maklumat peribadi.',
  ),
  connectingLuvly(
    'Connecting to Luvly…',
    '正在连接 Luvly…',
    'Sedang menyambung ke Luvly…',
  ),
  savedReminder(
    'Chats are saved to your account. Don’t share personal details.',
    '对话会保存到你的账号。请勿分享个人资料。',
    'Perbualan disimpan dalam akaun anda. Jangan kongsi maklumat peribadi.',
  ),
  guideOnly(
    'AI is not connected · help guide answers only.',
    'AI 未连接 · 当前由帮助指南提供回复。',
    'AI tidak disambungkan · jawapan daripada panduan bantuan sahaja.',
  ),
  generalReminder(
    'General questions only · please don’t share personal details.',
    '请提出一般问题，避免分享个人资料。',
    'Untuk soalan umum sahaja. Jangan kongsi maklumat peribadi.',
  ),
  guideReminder(
    'Help guide · no question is sent to AI.',
    '帮助指南 · 问题不会发送给 AI。',
    'Panduan bantuan · soalan tidak dihantar kepada AI.',
  ),
  consentTitle(
    'Use AI-assisted answers?',
    '要启用 AI 回复吗？',
    'Guna jawapan berbantu AI?',
  ),
  consentBody(
    'Google Gemini receives your question, up to four recent questions from this conversation, and Luvly’s help guide. Your account records are not included.\n\nGoogle may use submitted content and responses to improve its products, and human reviewers may review them. Do not share names, contact details, order references, passwords, banking information or other personal details. Messages are not guaranteed to be fully anonymised.\n\nAI can make mistakes and cannot check or change your orders, payments, stock or refunds. You can contact our team or switch AI off at any time.',
    'Google Gemini 会收到你的问题、这段对话中最近最多四条问题，以及 Luvly 的帮助指南。你的账号记录不会随请求发送。\n\nGoogle 可能使用提交的内容和回复来改进产品，也可能由人工审核。请勿分享姓名、联系方式、订单编号、密码、银行资料或其他个人信息。消息无法保证完全匿名。\n\nAI 可能出错，无法查询或更改你的订单、付款、库存或退款。你可以随时联系 Luvly 团队或关闭 AI。',
    'Google Gemini menerima soalan anda, sehingga empat soalan terkini daripada perbualan ini dan panduan bantuan Luvly. Rekod akaun anda tidak disertakan.\n\nGoogle mungkin menggunakan kandungan dan jawapan yang dihantar untuk menambah baik produknya. Penyemak manusia juga mungkin menyemaknya. Jangan kongsi nama, butiran hubungan, rujukan pesanan, kata laluan, maklumat bank atau maklumat peribadi lain. Mesej mungkin tidak dinyahnamakan sepenuhnya.\n\nAI boleh tersilap dan tidak boleh menyemak atau mengubah pesanan, bayaran, stok atau bayaran balik anda. Anda boleh menghubungi pasukan kami atau mematikan AI pada bila-bila masa.',
  ),
  useGuide('Use help guide', '使用帮助指南', 'Guna panduan bantuan'),
  startNew('Start a new conversation?', '开启新对话？', 'Mulakan perbualan baharu?'),
  legacyClear(
    'This chat stays on this screen only. Clear it when you no longer need it. Team tickets already sent are not deleted.',
    '这段聊天只保留在当前窗口。你可以随时清除，已发送的客服工单会保留。',
    'Perbualan ini hanya kekal pada skrin ini. Kosongkannya apabila tidak diperlukan. Tiket yang sudah dihantar akan kekal.',
  ),
  keepChat('Keep chat', '保留对话', 'Kekalkan perbualan'),
  clearChat('Clear chat', '清除对话', 'Kosongkan perbualan'),
  unsentWarning(
    'Your unsent message will be cleared. Saved conversations stay in your history.',
    '未发送的消息会清除，已保存的对话仍在聊天记录里。',
    'Mesej yang belum dihantar akan dipadam. Perbualan yang disimpan akan kekal dalam sejarah anda.',
  ),
  keepDraft('Keep message', '保留消息', 'Kekalkan mesej'),
  waysTitle(
    'Two ways to find an answer',
    '两种获取解答的方式',
    'Dua cara untuk mendapatkan jawapan',
  ),
  aiMode(
    'AI chat · conversational answers',
    'AI 聊天 · 支持连续追问',
    'Perbualan AI · jawapan dalam bentuk perbualan',
  ),
  aiModeDetail(
    'Gemini generates a natural answer using Luvly’s policy guide and up to four recent general questions from this conversation. You can ask follow-up questions. It cannot read your account or perform actions, and it can make mistakes.',
    'Gemini 会参考 Luvly 的政策指南和这段对话中最近最多四条一般问题来回答。你可以继续追问。AI 无法读取你的账号或代你操作，也可能出错。',
    'Gemini menggunakan panduan dasar Luvly dan sehingga empat soalan umum terkini dalam perbualan ini untuk menjawab. Anda boleh bertanya soalan susulan. AI tidak boleh membaca rekod akaun atau membuat tindakan untuk anda dan boleh tersilap.',
  ),
  guideMode(
    'Help guide · finds matching keywords',
    '帮助指南 · 按关键词查找',
    'Panduan bantuan · padanan kata kunci',
  ),
  guideModeDetail(
    'Browse common questions or search using clear keywords such as fitting, deposit or cancellation. No question is sent to Gemini.',
    '你可以浏览常见问题，或用「试穿」「订金」「取消」等关键词查找。问题不会发给 Gemini。',
    'Lihat soalan lazim atau gunakan kata kunci seperti sesi mencuba, deposit atau pembatalan. Soalan tidak dihantar kepada Gemini.',
  ),
  compareDetail(
    'Both use the same approved Luvly policies, so prices and rules should agree. Check policy details for important decisions. Only our team can help with a personal order, payment or refund.',
    '两种方式都依据 Luvly 的正式政策。做重要决定前请核对政策详情。个人订单、付款或退款只能由 Luvly 团队协助。',
    'Kedua-duanya menggunakan dasar rasmi Luvly. Semak butiran dasar sebelum membuat keputusan penting. Hanya pasukan kami boleh membantu dengan pesanan, bayaran atau bayaran balik peribadi.',
  ),
  noticeOffline(
    'Connection unavailable · showing the saved guide',
    '连接暂不可用 · 正在显示离线指南',
    'Sambungan tidak tersedia · panduan tersimpan dipaparkan',
  ),
  noticeSetup(
    'AI not connected · using the help guide',
    'AI 未连接 · 正在使用帮助指南',
    'AI tidak disambungkan · menggunakan panduan bantuan',
  ),
  noticeShorten(
    'Please shorten your question · showing the guide',
    '请简化你的问题 · 正在显示帮助指南',
    'Ringkaskan soalan anda · panduan dipaparkan',
  ),
  noticeQuota(
    'Daily AI limit reached · the help guide is still available',
    '今日 AI 用量已达上限 · 仍可使用帮助指南',
    'Had harian AI telah dicapai · panduan bantuan masih tersedia',
  ),
  noticeBusy(
    'AI is busy · showing the guide instead',
    'AI 正忙 · 正在显示帮助指南',
    'AI sedang sibuk · panduan bantuan dipaparkan',
  ),
  noticePersonal(
    'For a personal action, please contact our team',
    '如需处理个人事务，请联系 Luvly 团队',
    'Hubungi pasukan Luvly untuk urusan peribadi',
  ),
  noticeScope(
    'Please ask our team for help beyond the policy guide',
    '如需指南以外的帮助，请联系 Luvly 团队',
    'Hubungi pasukan Luvly untuk bantuan di luar panduan dasar',
  ),
  noticeAnswered(
    'Previous request completed · showing its guide without another AI call',
    '上次请求已完成 · 正在显示相关指南',
    'Permintaan sebelum ini telah selesai · panduan berkaitan dipaparkan',
  ),
  noticeUnavailable(
    'AI unavailable · using the help guide',
    'AI 暂不可用 · 正在使用帮助指南',
    'AI tidak tersedia · menggunakan panduan bantuan',
  ),
  aiAnswer('Gemini · AI answer', 'Gemini · AI 回复', 'Gemini · jawapan AI'),
  guideAnswer('Help guide answer', '帮助指南回复', 'Jawapan panduan bantuan'),
  basedOn('Based on: {value}', '参考：{value}', 'Berdasarkan: {value}'),
  guideTopic('Guide topic: {value}', '指南主题：{value}', 'Topik panduan: {value}'),
  checkPolicy(
    'Check Luvly policy details',
    '查看 Luvly 政策详情',
    'Semak butiran dasar Luvly',
  ),
  policyVersion(
    'Policy version {value}',
    '政策版本 {value}',
    'Versi dasar {value}',
  ),
  olderFailed(
    'Couldn’t load older messages. Please try again.',
    '无法加载更早的消息，请重试。',
    'Mesej terdahulu tidak dapat dimuatkan. Sila cuba lagi.',
  ),
  missing(
    'This conversation is no longer available.',
    '这段对话已无法查看。',
    'Perbualan ini tidak lagi tersedia.',
  ),
  checkFailed(
    'Couldn’t check the reply. Try Check response again.',
    '无法查看回复，请再点一次「查看回复」。',
    'Jawapan tidak dapat disemak. Pilih “Semak jawapan” untuk mencuba lagi.',
  ),
  length(
    'Use 1–256 characters.',
    '请输入 1 至 256 个字符。',
    'Gunakan 1 hingga 256 aksara.',
  ),
  invalidChars(
    'Remove unsupported characters.',
    '请移除不受支持的字符。',
    'Buang aksara yang tidak disokong.',
  ),
  limitNew(
    'Start a new conversation to continue.',
    '请开启新对话后继续。',
    'Mulakan perbualan baharu untuk meneruskan.',
  ),
  answerFailed(
    'We couldn’t answer your question. Try sending it again or contact our team.',
    '暂时无法回答你的问题。请重试，或联系 Luvly 团队。',
    'Soalan anda tidak dapat dijawab. Cuba hantar semula atau hubungi pasukan Luvly.',
  ),
  changedDraft(
    'The conversation changed. Your message is in the composer.',
    '对话已更新。你的消息仍在输入框里。',
    'Perbualan telah berubah. Mesej anda masih dalam ruang menaip.',
  ),
  newFailed(
    'Couldn’t start a new chat. Please try again.',
    '无法开启新对话，请重试。',
    'Perbualan baharu tidak dapat dimulakan. Sila cuba lagi.',
  ),
  openFailed(
    'Couldn’t open that conversation. Open history to try again.',
    '无法打开这段对话。请从聊天记录重试。',
    'Perbualan tidak dapat dibuka. Buka sejarah untuk mencuba lagi.',
  ),
  languageFailed(
    'Couldn’t save your language. Please try again.',
    '无法保存语言设置，请重试。',
    'Pilihan bahasa tidak dapat disimpan. Sila cuba lagi.',
  ),
  restoreFailed(
    'Couldn’t restore the conversation. Please try again.',
    '无法恢复对话，请重试。',
    'Perbualan tidak dapat dipulihkan. Sila cuba lagi.',
  ),
  deleteTitle('Delete this conversation?', '删除这段对话？', 'Padam perbualan ini?'),
  deleteBody(
    'This permanently deletes this chat and its messages from your Luvly history.',
    '这会永久删除 Luvly 聊天记录中的这段对话和相关消息。',
    'Perbualan ini dan semua mesejnya akan dipadam secara kekal daripada sejarah Luvly anda.',
  ),
  cancel('Cancel', '取消', 'Batal'),
  deleteForever('Delete permanently', '永久删除', 'Padam secara kekal'),
  updated('Conversation updated.', '对话已更新。', 'Perbualan dikemas kini.'),
  renamed('Conversation renamed.', '对话已重命名。', 'Nama perbualan telah ditukar.'),
  restored('Conversation restored.', '对话已恢复。', 'Perbualan dipulihkan.'),
  archived('Conversation archived.', '对话已归档。', 'Perbualan diarkibkan.'),
  deleted('Conversation deleted.', '对话已删除。', 'Perbualan dipadam.'),
  unsafeTitle(
    'Please use a short title without contact or account details.',
    '请输入简短标题，避免包含联系方式或账号资料。',
    'Gunakan tajuk ringkas tanpa butiran hubungan atau akaun.',
  ),
  updateFailed(
    'Couldn’t update the conversation. Please try again.',
    '无法更新对话，请重试。',
    'Perbualan tidak dapat dikemas kini. Sila cuba lagi.',
  ),
  yourChats('Your conversations', '聊天记录', 'Sejarah perbualan'),
  search('Search conversations', '搜索聊天记录', 'Cari perbualan'),
  clearSearch('Clear search', '清除搜索', 'Kosongkan carian'),
  recent('Recent', '最近', 'Terkini'),
  archiveTab('Archived', '已归档', 'Diarkibkan'),
  historyFailed(
    'Couldn’t load your conversations.',
    '无法加载聊天记录。',
    'Sejarah perbualan tidak dapat dimuatkan.',
  ),
  noMatches(
    'No matching conversations.',
    '没有匹配的对话。',
    'Tiada perbualan yang sepadan.',
  ),
  noArchived(
    'No archived conversations.',
    '没有已归档的对话。',
    'Tiada perbualan yang diarkibkan.',
  ),
  noHistory(
    'No conversations yet. Start a chat with Luvly Assistant.',
    '还没有聊天记录。开启与 Luvly 助手的对话吧。',
    'Belum ada perbualan. Mulakan perbualan dengan Luvly Assistant.',
  ),
  retryLoad('Retry loading', '重新加载', 'Cuba muatkan semula'),
  loadMore('Load more', '加载更多', 'Muatkan lagi'),
  rowOptions('Options for {value}', '「{value}」的选项', 'Pilihan untuk {value}'),
  rename('Rename', '重命名', 'Namakan semula'),
  archive('Archive', '归档', 'Arkibkan'),
  restore('Restore', '恢复', 'Pulihkan'),
  retryDelete('Retry deletion', '重试删除', 'Cuba padam semula'),
  delete('Delete', '删除', 'Padam'),
  deletionPending(
    'Conversation pending deletion',
    '对话等待删除',
    'Perbualan menunggu pemadaman',
  ),
  renameTitle('Rename conversation', '重命名对话', 'Namakan semula perbualan'),
  titleField('Conversation title', '对话标题', 'Tajuk perbualan'),
  saveTitle('Save title', '保存标题', 'Simpan tajuk'),
  back('Back', '返回', 'Kembali'),
  loadingHistory(
    'Loading conversations…',
    '正在加载聊天记录…',
    'Sedang memuatkan sejarah perbualan…',
  ),
  savingChanges('Saving changes…', '正在保存更改…', 'Sedang menyimpan perubahan…'),
  customer('Customer', '顾客', 'Pelanggan'),
  guide('Help guide', '帮助指南', 'Panduan bantuan'),
  noAnswer('(No answer)', '（暂无回复）', '(Tiada jawapan)'),
  reviewDraft(
    'Assistant follow-up — please review before sending.',
    'Luvly 助手转交的对话。发送前请核对内容。',
    'Susulan daripada pembantu. Sila semak sebelum menghantar.',
  ),
  privacyReply(
    'Please do not send passwords, verification codes, API keys or bank/card details. This message was not sent to AI.',
    '请勿发送密码、验证码、API 密钥或银行／银行卡资料。这条消息没有发送给 AI。',
    'Jangan hantar kata laluan, kod pengesahan, kunci API atau butiran bank/kad. Mesej ini tidak dihantar kepada AI.',
  ),
  guideIntro(
    'I can explain fittings, payments, rental dates, accessories, sizes, Calendar and receipts. Contact our team for your own order or refund.',
    '我可以说明试穿、付款、租期、配饰、尺码、日历和收据。涉及你的具体订单或退款，请联系人工客服。',
    'Saya boleh menerangkan sesi mencuba, bayaran, sewaan, aksesori, saiz, Calendar dan resit. Hubungi staf untuk pesanan atau bayaran balik peribadi.',
  );

  const AssistantText(this.english, this.chinese, this.malay);
  final String english, chinese, malay;
}
