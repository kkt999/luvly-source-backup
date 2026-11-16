import 'dart:convert';
import 'package:flutter/services.dart';
import '../payments/payment_api.dart';

class AssistantReply {
  const AssistantReply({
    required this.answer,
    required this.mode,
    required this.handoff,
    required this.sources,
    this.notice,
    this.version = '2026-10-15',
  });
  final String answer, mode, version;
  final String? notice;
  final bool handoff;
  final List<Map<String, String>> sources;
  factory AssistantReply.fromJson(Map<String, dynamic> data) {
    if (!['AI', 'Guide'].contains(data['mode']) ||
        data['answer'] is! String ||
        (data['answer'] as String).length > 6000 ||
        data['handoff'] is! bool ||
        data['sources'] is! List) {
      throw const PaymentFailure('Could not read the assistant response.');
    }
    return AssistantReply(
      answer: data['answer'],
      mode: data['mode'],
      handoff: data['handoff'],
      notice: data['notice'] as String?,
      version: data['guideVersion'] as String? ?? '2026-10-15',
      sources: [
        for (final s in data['sources'])
          {
            'id': s['id'] as String,
            'title': s['title'] as String,
            if (s['excerpt'] is String) 'excerpt': s['excerpt'] as String,
          },
      ],
    );
  }
}

abstract class AssistantApi {
  Future<bool> configured();
  Future<AssistantReply> ask({
    required String message,
    required List<String> history,
    required String language,
    required bool ai,
    required String requestId,
  });
  void close();
}

class LuvlyAssistantApi implements AssistantApi {
  LuvlyAssistantApi({HttpPaymentApi? transport})
    : transport = transport ?? HttpPaymentApi();
  final HttpPaymentApi transport;
  @override
  Future<bool> configured() async {
    try {
      final status = await transport.businessRequest('/v1/support-assistant');
      return status['aiConfigured'] == true &&
          status['provider'] == 'Gemini' &&
          status['consentVersion'] == 3;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<AssistantReply> ask({
    required String message,
    required List<String> history,
    required String language,
    required bool ai,
    required String requestId,
  }) async {
    try {
      return AssistantReply.fromJson(
        await transport.businessRequest(
          '/v1/support-assistant',
          body: {
            'message': message,
            'history': history,
            'language': language,
            'mode': ai ? 'AI' : 'Guide',
            'requestId': requestId,
            if (ai) 'consentVersion': 3,
          },
        ),
      );
    } catch (_) {
      return localHelp(message, history, language);
    }
  }

  @override
  void close() => transport.close();
}

Future<AssistantReply> localHelp(
  String message,
  List<String> history,
  String language,
) async {
  final lang = ['en', 'zh', 'ms'].contains(language)
      ? language
      : RegExp(r'[\u3400-\u9fff]', unicode: true).hasMatch(message)
      ? 'zh'
      : RegExp(
          r'\b(saya|boleh|berapa|gaun|sewa|bayar|janji|saiz|stok|batal)\b',
          caseSensitive: false,
        ).hasMatch(message)
      ? 'ms'
      : 'en';
  if (assistantPrivacyBlocked(message) ||
      history.any(assistantPrivacyBlocked)) {
    return AssistantReply(
      answer: lang == 'zh'
          ? '请勿发送密码、验证码、API 密钥或银行／银行卡资料。这条消息没有发送给 AI。'
          : lang == 'ms'
          ? 'Jangan hantar kata laluan, kod pengesahan, kunci API atau butiran bank/kad. Mesej ini tidak dihantar kepada AI.'
          : 'Please do not send passwords, verification codes, API keys or bank/card details. This message was not sent to AI.',
      mode: 'Guide',
      handoff: true,
      sources: const [],
      notice: 'Privacy',
    );
  }
  final data =
      jsonDecode(await rootBundle.loadString('assets/support/guide.json'))
          as Map;
  final articles = (data['articles'] as List).cast<Map>();
  List<Map> match(String question) {
    final q = question.toLowerCase();
    final ranked = [
      for (final a in articles)
        (
          a,
          (a['keywords'] as List).where((v) {
            final k = (v as String).toLowerCase();
            return RegExp(r'[a-z]').hasMatch(k)
                ? RegExp(
                    '\\b${RegExp.escape(k)}${k.length < 4 ? '\\b' : ''}',
                    caseSensitive: false,
                  ).hasMatch(q)
                : q.contains(k);
          }).length,
        ),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return ranked.where((v) => v.$2 > 0).take(2).map((v) => v.$1).toList();
  }

  var found = match(message);
  if (found.isEmpty &&
      history.isNotEmpty &&
      RegExp(
        r'^(and|then|what next|how much|然后|还有|接下来|多少钱|dan|seterusnya)[?？\s\S]{0,30}$',
        caseSensitive: false,
      ).hasMatch(message.toLowerCase())) {
    found = match(history.last);
  }
  final fallback = lang == 'zh'
      ? '我可以说明试穿、付款、租期、配饰、尺码、日历和收据。涉及你的具体订单或退款，请联系人工客服。'
      : lang == 'ms'
      ? 'Saya boleh menerangkan sesi mencuba, bayaran, sewaan, aksesori, saiz, Calendar dan resit. Hubungi staf untuk pesanan atau bayaran balik peribadi.'
      : 'I can explain fittings, payments, rental dates, accessories, sizes, Calendar and receipts. Contact our team for your own order or refund.';
  return AssistantReply(
    answer: found.isEmpty
        ? fallback
        : found.map((a) => a['answer'][lang] as String).join('\n\n'),
    mode: 'Guide',
    handoff:
        found.isEmpty ||
        RegExp(
          r'refund|charged|deducted|my payment|my order|退款|扣款|人工|bayaran balik',
          caseSensitive: false,
        ).hasMatch(message),
    sources: [
      for (final a in found)
        {'id': a['id'] as String, 'title': a['title'][lang] as String},
    ],
    notice: 'Offline',
    version: data['version'],
  );
}

bool assistantPrivacyBlocked(String text) =>
    RegExp(
      r'AIza[A-Za-z0-9_-]{20,}|\b(?:password|secret|otp|verification code|card number|cvv|pin)\s*[:=]?\s*\d{3,}|(?:密码|验证码|卡号)\s*[:：]?\s*\S+|\b(?:password|api key|secret)\s*[:=]\s*\S+',
      caseSensitive: false,
    ).hasMatch(text) ||
    RegExp(
      r'(?:^|\s)(?=[A-Za-z0-9_.-]*[0-9_.-])[A-Za-z0-9_.-]{40,}(?=$|\s)',
    ).hasMatch(text);
