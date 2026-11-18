import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'backend_endpoint.dart';

const paymentBackendUrl = String.fromEnvironment('PAYMENT_BACKEND_URL');

class PaymentFailure implements Exception {
  const PaymentFailure(this.message, {this.code});
  final String message;
  final String? code;
}

final _thousandsGroups = RegExp(r'(\d)(?=(?:\d{3})+$)');

String formatRinggit(int cents) {
  final whole = (cents ~/ 100).abs().toString();
  final grouped = whole.replaceAllMapped(
    _thousandsGroups,
    (digit) => '${digit[1]},',
  );
  final fraction = cents.remainder(100).abs().toString().padLeft(2, '0');
  final sign = cents < 0 ? '-' : '';
  return 'RM $sign$grouped.$fraction';
}

String paymentDateLabel(int milliseconds) {
  final d = DateTime.fromMillisecondsSinceEpoch(
    milliseconds,
    isUtc: true,
  ).add(const Duration(hours: 8));
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} MYT';
}

class PaymentAppointment {
  const PaymentAppointment({
    required this.startAt,
    required this.type,
    required this.durationMinutes,
  });
  final int startAt, durationMinutes;
  final String type;
  static PaymentAppointment? parse(dynamic data) {
    if (data is! Map ||
        data['startAt'] is! int ||
        data['startAt'] <= 0 ||
        data['startAt'] >= 4102444800000 ||
        data['durationMinutes'] != 60 ||
        !['Dress Trial', 'Bridal Consultation'].contains(data['type'])) {
      return null;
    }
    return PaymentAppointment(
      startAt: data['startAt'],
      type: data['type'],
      durationMinutes: data['durationMinutes'],
    );
  }
}

class SandboxInvoice {
  const SandboxInvoice({
    required this.id,
    required this.title,
    required this.appointmentId,
    required this.amountCents,
    required this.state,
    this.invoiceNo,
    this.checkoutUrl,
    this.reviewReason,
    this.customerName,
    this.holdExpiresAt,
    this.paidAt,
    this.createdAt,
    this.paymentChannel,
    this.purpose,
    this.paymentPhase,
    this.packageSelectionId,
    this.extensionDetails,
    this.appointment,
    this.pickupDueDate,
    this.paymentBlocked = false,
    this.reviewResolution,
    this.canResolveReview = false,
  });
  final String id, title, appointmentId, state;
  final int amountCents;
  final bool paymentBlocked;
  final int? holdExpiresAt;
  final int? paidAt;
  final int? createdAt;
  final String? paymentChannel, purpose, paymentPhase;
  final String? packageSelectionId;
  final Map<String, dynamic>? extensionDetails;
  final Map<String, dynamic>? reviewResolution;
  final bool canResolveReview;
  final PaymentAppointment? appointment;

  /// Calendar date only, from the owner-bound active rental; not midnight expiry.
  final String? pickupDueDate;
  final String? invoiceNo, checkoutUrl, reviewReason, customerName;
  String get amountLabel => formatRinggit(amountCents);
  bool get holdExpired =>
      holdExpiresAt != null &&
      DateTime.now().millisecondsSinceEpoch >= holdExpiresAt!;
  bool get canPay =>
      !paymentBlocked &&
      !holdExpired &&
      ['Quoted', 'Unpaid', 'Pending'].contains(state);
  bool get hasBill => checkoutUrl != null;
  String get statusLabel => reviewResolution != null
      ? switch (reviewResolution!['state']) {
          'RefundRecorded' => 'Refund recorded',
          'PartialRefundRecorded' => 'Partial refund recorded',
          _ => 'Review completed',
        }
      : switch (state) {
          'Quoted' => 'Awaiting payment',
          'Creating' => 'Preparing payment',
          'SandboxPaid' => 'Paid',
          'ReviewRequired' => 'Manager review required',
          'Pending' => 'Verification pending',
          _ => 'Not paid',
        };
  String get purposeLabel => switch (purpose) {
    'FittingFee' => 'First gown fitting',
    'SecurityDeposit' => 'Refundable gown security deposit',
    'BookingDeposit' => 'Package booking deposit',
    'PackageBalance' => 'Package balance',
    'RentalExtension' => 'Additional rental days',
    'PackagePayment' => 'Package payment',
    'AppointmentDeposit' => 'Appointment deposit',
    'DressPayment' => 'Gown payment',
    _ => title,
  };
  String? get methodLabel => paymentChannel == null
      ? null
      : paymentChannel!.toUpperCase().contains('FPX')
      ? 'FPX online banking'
      : paymentChannel;
  factory SandboxInvoice.fromJson(Map<String, dynamic> data) {
    final amount = data['amountCents'];
    final state = data['state'];
    final extension = data['extensionDetails'];
    if (data['purpose'] == 'RentalExtension' &&
        (extension is! Map ||
            extension['extraDays'] is! int ||
            extension['extraDays'] < 1 ||
            extension['dayRateCents'] is! int ||
            extension['dayRateCents'] < 100 ||
            extension['extraDays'] * extension['dayRateCents'] != amount ||
            [
              'pickupDate',
              'eventDate',
              'returnDate',
              'oldPickupDate',
              'oldReturnDate',
            ].any(
              (k) =>
                  extension[k] is! String ||
                  !RegExp(r'^\d{4}-\d\d-\d\d$').hasMatch(extension[k]),
            ))) {
      throw const PaymentFailure(
        'Could not verify the rental extension quote. Contact the team before paying.',
      );
    }
    if (data['environment'] != 'sandbox' ||
        amount is! int ||
        amount < 100 ||
        amount > 100000000 ||
        ![
          'Quoted',
          'Creating',
          'Unpaid',
          'Pending',
          'SandboxPaid',
          'ReviewRequired',
        ].contains(state) ||
        data['id'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(data['id']) ||
        data['title'] is! String ||
        data['appointmentId'] is! String ||
        (data['appointmentId'] == '' &&
            (data['packageSelectionId'] is! String ||
                !RegExp(
                  r'^[a-f0-9]{32}$',
                ).hasMatch(data['packageSelectionId']))) ||
        (state == 'SandboxPaid' && data['invoiceNo'] is! String)) {
      throw const PaymentFailure(
        'Could not verify the payment response. Try again.',
      );
    }
    final url = data['checkoutUrl'];
    if (url != null) sandboxCheckoutUri(url as String);
    return SandboxInvoice(
      id: data['id'],
      title: data['title'],
      appointmentId: data['appointmentId'],
      packageSelectionId: data['packageSelectionId'] as String?,
      extensionDetails: extension is Map
          ? Map<String, dynamic>.from(extension)
          : null,
      appointment: PaymentAppointment.parse(data['appointmentSummary']),
      pickupDueDate: parsePickupDueDate(data['paymentDue']),
      amountCents: amount,
      state: state,
      invoiceNo: data['invoiceNo'],
      checkoutUrl: url,
      reviewReason: data['reviewReason'],
      customerName: data['customerName'],
      holdExpiresAt: data['holdExpiresAt'] as int?,
      paidAt: data['paidAt'] as int?,
      createdAt: data['createdAt'] is int ? data['createdAt'] : null,
      paymentChannel: data['paymentChannel'] as String?,
      purpose: data['purpose'] as String?,
      paymentPhase: data['paymentPhase'] as String?,
      paymentBlocked: data['paymentBlocked'] == true,
      reviewResolution: data['reviewResolution'] is Map
          ? Map<String, dynamic>.from(data['reviewResolution'])
          : null,
      canResolveReview: data['canResolveReview'] == true,
    );
  }
}

String? parsePickupDueDate(dynamic data) {
  if (data is! Map ||
      data['kind'] != 'BeforePickup' ||
      data['date'] is! String) {
    return null;
  }
  final value = data['date'] as String;
  if (!RegExp(r'^\d{4}-\d\d-\d\d$').hasMatch(value)) return null;
  final day = DateTime.tryParse('${value}T00:00:00Z');
  if (day == null ||
      day.year < 2000 ||
      day.year > 2100 ||
      day.toIso8601String().substring(0, 10) != value) {
    return null;
  }
  return value;
}

Uri sandboxCheckoutUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'dev.toyyibpay.com' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.hasQuery ||
      uri.hasFragment ||
      !RegExp(r'^/[A-Za-z0-9]{1,64}$').hasMatch(uri.path)) {
    throw const PaymentFailure(
      'Could not verify the payment link. Please contact Luvly.',
    );
  }
  return uri;
}

int? quoteAmountCents(String value) {
  if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(value.trim())) return null;
  final parts = value.trim().split('.');
  final cents =
      int.parse(parts[0]) * 100 +
      int.parse(parts.length == 1 ? '00' : parts[1].padRight(2, '0'));
  return cents >= 100 && cents <= 100000000 ? cents : null;
}

abstract class PaymentApi {
  bool get configured;
  Future<List<SandboxInvoice>> list();
  Future<SandboxInvoice> quote(
    String appointmentId,
    String purpose,
    int amountCents,
  );
  Future<SandboxInvoice> checkout(String id, {String paymentMethod = 'FPX'});
  Future<SandboxInvoice> refresh(String id);
  void close();
}

class HttpPaymentApi implements PaymentApi {
  HttpPaymentApi({
    String? baseUrl,
    Future<String> Function()? resolveBaseUrl,
    http.Client? client,
    Future<String?> Function()? token,
  }) : _base = baseUrl,
       _resolveBaseUrl = resolveBaseUrl ?? loadBackendEndpoint,
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _token =
           token ??
           (() =>
               FirebaseAuth.instance.currentUser?.getIdToken() ??
               Future.value());
  final String? _base;
  final Future<String> Function() _resolveBaseUrl;
  final http.Client _client;
  final bool _ownsClient;
  final Future<String?> Function() _token;
  @override
  bool get configured => _base == null || _base.isNotEmpty;
  Future<dynamic> businessRequest(String path, {Map<String, dynamic>? body}) =>
      _request(path, body: body);
  Future<dynamic> uploadBusinessFile(
    String path,
    Uint8List bytes,
    String mime,
  ) => _request(path, bytes: bytes, contentType: mime);

  Future<Uint8List> downloadBusinessFile(
    String path, {
    required Set<String> types,
    required int maxBytes,
  }) async {
    final token = await _token().timeout(const Duration(seconds: 10));
    if (token == null) throw const PaymentFailure('Please sign in again.');
    final origin =
        _base ?? await _resolveBaseUrl().timeout(const Duration(seconds: 10));
    final request = http.Request('GET', _url(origin, path))
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer $token';
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    final output = BytesBuilder(copy: false);
    final type = response.headers['content-type']?.split(';').first;
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      if (response.statusCode != 200 ||
          !types.contains(type) ||
          (response.contentLength ?? 0) > maxBytes ||
          output.length + chunk.length > maxBytes) {
        throw const PaymentFailure(
          'Could not download the file. Please try again.',
        );
      }
      output.add(chunk);
    }
    if (output.isEmpty) {
      throw const PaymentFailure(
        'Could not download the file. Please try again.',
      );
    }
    return output.takeBytes();
  }

  /// Authenticated invalidations only. Cancellation aborts the browser fetch;
  /// tokens never appear in URLs and redirects are never followed.
  Stream<String> analyticsEvents(Future<void> abort) => Stream.fromFuture(
    _openAnalyticsEvents(abort),
  ).asyncExpand((events) => events);

  Future<Stream<String>> _openAnalyticsEvents(Future<void> abort) async {
    final token = await _token().timeout(const Duration(seconds: 10));
    if (token == null) throw const PaymentFailure('Please sign in again.');
    final origin =
        _base ?? await _resolveBaseUrl().timeout(const Duration(seconds: 10));
    final request =
        http.AbortableRequest(
            'GET',
            _url(origin, '/v1/analytics/events'),
            abortTrigger: abort,
          )
          ..followRedirects = false
          ..headers.addAll({
            'Authorization': 'Bearer $token',
            'Accept': 'text/event-stream',
          });
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 ||
        !(response.headers['content-type'] ?? '').startsWith(
          'text/event-stream',
        )) {
      await response.stream.drain<void>();
      throw const PaymentFailure(
        'Live connection unavailable. Refresh to check current data.',
      );
    }
    return response.stream
        .timeout(const Duration(seconds: 25))
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.startsWith('data: '))
        .map((line) => line.substring(6));
  }

  Uri _url(String origin, String path) {
    final base = Uri.tryParse(origin);
    if (base == null ||
        (base.scheme != 'https' && !isLocalPortalEndpoint(base)) ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        !['', '/'].contains(base.path)) {
      throw const PaymentFailure(
        'Payment service is not configured. Contact Luvly.',
      );
    }
    return base.resolve(path);
  }

  Future<dynamic> _request(
    String path, {
    Map<String, dynamic>? body,
    Uint8List? bytes,
    String? contentType,
  }) async {
    try {
      final token = await _token().timeout(const Duration(seconds: 10));
      if (token == null) throw const PaymentFailure('Please sign in again.');
      // Read fresh configuration for every action/Retry. Do not retry POSTs or
      // fall back to a retired tunnel that might no longer belong to Luvly.
      final origin =
          _base ?? await _resolveBaseUrl().timeout(const Duration(seconds: 10));
      final url = _url(origin, path);
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': contentType ?? 'application/json',
      };
      final request =
          http.Request(body == null && bytes == null ? 'GET' : 'POST', url)
            ..followRedirects = false
            ..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      if (bytes != null) request.bodyBytes = bytes;
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(Duration(seconds: bytes == null ? 25 : 90));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String? code;
        try {
          code = (jsonDecode(response.body) as Map)['error'] as String?;
        } catch (_) {}
        throw PaymentFailure(switch (code) {
          'REVIEW_NOT_ELIGIBLE' =>
            'Reviews open after your rental has been collected, returned and inspected by Luvly.',
          'REVIEW_TEXT_BLOCKED' =>
            'Please remove profanity, abusive language or threats before submitting. You can edit your review and try again.',
          'REVIEW_POLICY_REQUIRED' =>
            'Update Luvly and confirm the text-safety checking notice before submitting.',
          'REVIEW_REPLY_PENDING' =>
            'The reply could not be cleared by the safety check, so it has not been published. Please review the wording or try again later.',
          'INVALID_REVIEW_APPROVAL' =>
            'Check the pending review and record a clear safety-approval reason.',
          'INVALID_REVIEW_REPORT' =>
            'Choose a content-policy reason and keep report details within 500 characters.',
          'REVIEW_REPORT_ACCESS' =>
            'You can report another customer’s published review, not your own.',
          'REVIEW_REPORT_LIMIT' =>
            'You have reached the daily limit of 10 review reports. Existing reports are still being reviewed.',
          'REVIEW_REPORT_CHANGED' || 'REVIEW_REPORT_NOT_FOUND' =>
            'This report was already handled or changed. Refresh the report queue before taking another action.',
          'CUSTOMER_REVIEW_REQUIRED' =>
            'Only customers can review their own completed rentals.',
          'INVALID_REVIEW' =>
            'Choose 1–5 stars, keep your review within 1,000 characters and confirm sharing before submitting.',
          'INVALID_REVIEW_MEDIA' =>
            'Choose a JPG/PNG photo or a valid H.264 MP4 video, at most 30 seconds and 1920 pixels per side.',
          'REVIEW_MEDIA_TOO_LARGE' =>
            'This file is too large. Choose a video up to 20 MB or a smaller photo.',
          'REVIEW_CHANGED' =>
            'This review changed elsewhere. Reopen My reviews to check the latest version before editing again.',
          'REVIEW_MEDIA_LIMIT' =>
            'Attach up to 5 photos and 1 video to each review.',
          'REVIEW_UPLOAD_LIMIT' =>
            'There are too many unfinished uploads for this rental. Reopen your saved review or try again after the temporary uploads are cleared.',
          'REVIEW_UPLOAD_IN_PROGRESS' =>
            'This upload is still being verified. Wait briefly, then retry the same submission.',
          'REVIEW_UPLOAD_EXPIRED' =>
            'This temporary upload has expired. Remove that attachment, choose the file again and retry.',
          'REVIEW_MEDIA_UNAVAILABLE' =>
            'Media storage is temporarily unavailable. Your review has not been confirmed; please retry.',
          'REVIEW_MEDIA_NOT_FOUND' =>
            'This photo or video is no longer available to view. Refresh the reviews.',
          'REVIEW_RENTAL_NOT_FOUND' || 'REVIEW_NOT_FOUND' =>
            'This review or rental is unavailable to your account. Please refresh.',
          'INVALID_REVIEW_MODERATION' =>
            'Choose a valid content-policy reason and explain the moderation decision.',
          'REVIEW_ACCESS_REQUIRED' =>
            'You do not have permission to change this review.',
          'INVALID_RECOMMENDATION_PROFILE' =>
            'Check your measurements and preferences, then save again.',
          'RECOMMENDATION_PROFILE_CHANGED' =>
            'Your preferences changed on another device. Reopen this page to load the latest details before saving.',
          'RECOMMENDATION_PROFILE_UNAVAILABLE' =>
            'Your preferences could not be loaded. Retry before making changes.',
          'CUSTOMER_PROFILE_REQUIRED' =>
            'Sign in with a customer account to save bridal preferences.',
          'INVALID_PROFILE_PHOTO' =>
            'Choose a JPG or PNG and review your square crop. The saved photo must be 64 KB or less and up to 512 pixels per side.',
          'PROFILE_PHOTO_CHANGED' =>
            'Your photo changed on another device. Go back, reopen Profile photo and review the latest image before saving again.',
          'PROFILE_PHOTO_UNAVAILABLE' =>
            'Your saved profile photo could not be loaded. Please retry; your profile and rental records are unchanged.',
          'INVALID_SELF_PROFILE' =>
            'Enter a valid name and contact number. Your access role cannot be changed here.',
          'INVALID_TASK' => 'Check the task title, employee, type and notes.',
          'INVALID_TASK_TIME' =>
            'Choose a future MYT time within 10:00–13:00 or 14:00–17:00, up to 179 days ahead.',
          'TASK_SKILL_REQUIRED' =>
            'This employee does not have the required service role. Choose qualified staff or ask the manager to review their skills.',
          'TASK_STAFF_UNAVAILABLE' || 'TASK_APPOINTMENT_CONFLICT' =>
            'This employee has an appointment, another task or approved leave during that time. Choose another employee or time.',
          'AVAILABILITY_HAS_TASKS' =>
            'An assigned task overlaps this time off. Ask your manager to reassign or cancel the task first.',
          'TASK_CHANGED' =>
            'This task changed elsewhere or has already started. Reload tasks and review the current assignment before retrying.',
          'TASK_ACCESS_DENIED' || 'TASK_NOT_FOUND' =>
            'This task is no longer available to your account. Reload your task list.',
          'INVALID_TASK_TRANSITION' =>
            'Review the current task status. Start a task at or after its scheduled time before completing it; only a manager can cancel tasks.',
          'TASK_LIST_LIMIT' =>
            'The task history exceeds this project’s display limit. Contact the manager; no incomplete workload is shown.',
          'SUPPORT_CHANGED' =>
            'This conversation changed or is already closed. Review its latest status before retrying.',
          'SUPPORT_ACCESS_DENIED' =>
            'This conversation is not available to your account.',
          'INVALID_SUPPORT_MESSAGE' =>
            'Check the support subject, category and message before sending.',
          'INVALID_NOTIFICATION' || 'NOTIFICATION_NOT_FOUND' =>
            'This notification is no longer available. Reload your inbox.',
          'PLANNING_LIMIT_REACHED' =>
            'Your planning history exceeds this project’s display limit. No incomplete journey is shown; contact the team to review your records.',
          'BRIDE_REQUIRED' =>
            'Please use a customer account to view your personal bridal plan.',
          'INVALID_REPORT_RANGE' =>
            'Choose valid MYT dates with the start on or before the end, and no future dates.',
          'REPORT_RANGE_TOO_LONG' =>
            'Choose a reporting period of up to 366 days.',
          'ANALYTICS_LIMIT_REACHED' =>
            'The reporting snapshot exceeds the project limit. No partial totals are shown; contact the manager for a paginated reporting setup.',
          'PROMOTION_UNAVAILABLE' =>
            'This offer is inactive, expired or not yet available. Remove the code or choose a current offer before rental confirmation.',
          'PROMOTION_PACKAGE' =>
            'This code does not apply to the selected package.',
          'PROMOTION_MINIMUM' =>
            'This package does not meet the offer’s minimum spend.',
          'PROMOTION_PRICE_REVIEW' =>
            'This discount would leave an invalid package total. Choose another offer or contact the manager.',
          'PROMOTION_PRICE_REVIEW_REQUIRED' =>
            'Review the discounted total before issuing a deposit.',
          'PROMOTION_NEW_CUSTOMER_ONLY' =>
            'This welcome voucher is available during the first 30 days after registration.',
          'PROMOTION_USED' =>
            'You have already used this offer. Each customer can use a campaign once.',
          'PROMOTION_HELD' =>
            'This offer is temporarily held for another package. Complete that payment or wait for its 15-minute hold to expire.',
          'PROMOTION_CHANGED' =>
            'This offer or package changed. Refresh and reapply the code before continuing.',
          'PROMOTION_ORDER_LOCKED' =>
            'Promo codes can only be changed on a gown package before its deposit invoice is issued.',
          'PROMOTION_CODE_EXISTS' =>
            'This code has already been assigned. Choose a different unique code.',
          'PROMOTION_CODE_IMMUTABLE' =>
            'A campaign’s type and code cannot be changed. Create a new campaign instead.',
          'INVALID_PROMOTION' ||
          'INVALID_PROMOTION_DATES' ||
          'INVALID_PROMOTION_VALUE' =>
            'Check the campaign fields, discount amount and date range.',
          'FITTING_QUOTE_ACCEPTANCE_REQUIRED' =>
            'Ask the customer to review and accept the current fitting proposal before issuing a deposit.',
          'DRESS_IN_USE' =>
            'This dress is linked to records in Luvly. You can unpublish it from the customer catalogue.',
          'DRESS_AR_IN_USE' =>
            'This dress has a Tripo model or generation job. You can unpublish the dress.',
          'DRESS_DELETE_CHANGED' =>
            'This dress changed. Refresh the inventory before trying again.',
          'DRESS_REFERENCE_CHECK_LIMIT' =>
            'The service could not check all references. You can unpublish the dress.',
          'PACKAGE_SERVICE_TIMING_REQUIRED' =>
            'Confirm the timing of each selected team-arranged service before sending the proposal.',
          'PACKAGE_MAKEUP_TRIAL_CHANGED' =>
            'The makeup trial changed. Ask the team to refresh the arrangement and send an updated proposal.',
          'PACKAGE_MAKEUP_ARTIST_UNAVAILABLE' =>
            'This team member is no longer available to assign. Refresh and choose an eligible makeup artist.',
          'PACKAGE_ACCESSORY_APPROVAL_REQUIRED' =>
            'Confirm the approved package and veil prices before publishing.',
          'INVALID_PACKAGE_ACCESSORY_PRICING' =>
            'Use one separate Veil Rental and one Bridal Accessories service. Remove any legacy allowance services from this configuration.',
          'PACKAGE_ACCESSORY_SELECTION_REQUIRED' =>
            'Ask the customer to select available accessories or remove the optional service before sending a proposal.',
          'PACKAGE_SERVICE_PLAN_UPDATE_REQUIRED' =>
            'Update Luvly to review the agreed service schedule before accepting the proposal.',
          'FITTING_PLAN_UPDATE_REQUIRED' =>
            'Update Luvly to review the complete alteration plan before accepting this proposal.',
          'FITTING_QUOTE_CHANGED' ||
          'FITTING_SELECTION_CHANGED' ||
          'FITTING_CLIENT_UPDATE_REQUIRED' =>
            'This plan or proposal changed. Reopen it to review the latest details.',
          'FITTING_ORDER_LOCKED' =>
            'A bill or reservation already exists. The team must review it before any selection or price change.',
          'FITTING_ADJUSTMENTS_PENDING' =>
            'Record the agreed adjustments as completed in service preparation before handing over the gown.',
          'FINAL_FITTING_PENDING' =>
            'Record the required final fitting and customer fit acceptance before marking items ready or handing them over.',
          'FINAL_FITTING_VISIT_REQUIRED' =>
            'Choose a separate included Dress Trial linked to this rental, booked after reservation.',
          'FINAL_FITTING_DATE_CONFLICT' =>
            'The final fitting must actually take place after alterations and no later than pickup. Review the appointment and rental dates.',
          'FINAL_FITTING_NOT_REQUIRED' || 'FINAL_FITTING_ALREADY_RECORDED' =>
            'Refresh the rental to review its latest final fitting and collection status.',
          'INVALID_FINAL_FITTING' =>
            'Choose the attended follow-up appointment, confirm the fit was accepted and add a note of at least 10 characters.',
          'NO_SHOW_REASON_REQUIRED' =>
            'Add a clear note of at least 10 characters explaining the missed appointment.',
          'INVALID_PAYMENT_RESOLUTION' =>
            'Check the refund amount, add a reason of at least 10 characters and enter a verified reference for any refund.',
          'PAYMENT_RESOLUTION_NOT_AVAILABLE' =>
            'Only verified payments for cancelled, expired or missed bookings can be reconciled here. Refresh the payment or review the rental cancellation first.',
          'FITTING_CREDIT_IN_USE' =>
            'This fitting payment is linked to a rental deposit. Review that rental before settling the fee.',
          'MANAGER_QUOTE_REQUIRED' =>
            'A manager must approve any additional adjustment fee.',
          'MANAGER_ASSESSMENT_REQUIRED' =>
            'A manager must assess special alterations and prepare this proposal, even with no extra fee.',
          'FITTING_FOLLOW_UP_DECISION_REQUIRED' =>
            'Update the fitting assessment to decide whether a final fitting is required before sending the proposal.',
          'INVALID_FITTING_ASSESSMENT' =>
            'Check the measurements, gown assessments and completion date. Leave unmeasured values blank; completion must be between today and pickup.',
          'FITTING_ADJUSTMENT_DETAILS_REQUIRED' || 'INVALID_FITTING_QUOTE' =>
            'Add clear adjustment details, a customer-facing summary and valid amounts.',
          'FITTING_SELECTION_REQUIRED' =>
            'Record the chosen gown and adjustment needs before preparing a proposal.',
          'FITTING_FEE_ALREADY_ISSUED' =>
            'This booking already uses the fitting-fee policy. Do not issue a second appointment deposit.',
          'PAYMENT_TERMS_REQUIRED' =>
            'Update Luvly and accept the booking and payment terms before reserving a time.',
          'COMPLETED_FITTING_REQUIRED' =>
            'Mark the attended fitting completed before confirming the package rental.',
          'DEPOSIT_QUOTE_CHANGED' =>
            'The fitting credit or package amount changed. Reopen the package to review the calculated deposit.',
          'PACKAGE_PRICE_REVIEW_REQUIRED' =>
            'This price needs staff review before a deposit invoice can be issued.',
          'PICKUP_PAYMENT_REQUIRED' =>
            'The package balance and refundable security must both be verified paid before handover.',
          'EXTENSION_CONSENT_REQUIRED' =>
            'Review the extension dates and additional fee, then confirm your agreement before continuing.',
          'EXTENSION_PRICE_REQUIRED' =>
            'An extra-day price is not configured for this package. Ask a manager to update the package before quoting.',
          'EXTENSION_QUOTE_CHANGED' =>
            'The extra-day price changed. Reload the rental and check the quote again.',
          'EXTENSION_PENDING' =>
            'A rental date change is awaiting payment. Complete or cancel that request first; original dates remain valid until payment is verified.',
          'EXTENSION_EXPIRED' =>
            'This extension hold ended or was cancelled. Original rental dates remain unchanged. Check any existing payment before requesting another invoice.',
          'EXTENSION_CHANGED' =>
            'The extension request changed or is already paid. Reload the rental.',
          'EXTENSION_PAYMENT_BINDING' =>
            'The extension payment needs staff review. Do not pay again.',
          'INVALID_DATE_CHANGE' =>
            'Choose valid dates and add a clear customer discussion note (at least 10 characters).',
          'DATE_CHANGE_CONSENT_REQUIRED' =>
            'Record the customer’s agreement to these exact dates before saving.',
          'PACKAGE_DATE_CHANGE_REQUIRED' =>
            'This rental requires a package-specific date review. Contact the team.',
          'DATE_CHANGE_BEFORE_PICKUP_ONLY' =>
            'Dates can only be changed for an active reserved package before actual collection.',
          'RENTAL_DATES_CHANGED' =>
            'Another date change was saved. Reload the rental and review its latest dates.',
          'RENTAL_DATES_UNCHANGED' =>
            'Choose a different pickup or return date before checking availability.',
          'DATE_CHANGE_LIMIT_REACHED' =>
            'This rental has reached its amendment limit. Ask a manager to review the history.',
          'PICKUP_DATE_REQUIRED' =>
            'Handover is available on the agreed pickup date only. Review the rental dates.',
          'UNRETURNED_ITEMS_REVIEW_REQUIRED' =>
            'Stock is still out with another customer, or current capacity is insufficient. Resolve it before handover.',
          'RETURN_INSPECTION_REQUIRED' =>
            'These items have been collected. Use return inspection; do not cancel or release physical stock.',
          'COLLECTED_RENTAL_REQUIRED' =>
            'Items must be collected first; a saved return inspection cannot be overwritten here.',
          'INVALID_INSPECTION' =>
            'Confirm all items returned. Deductions must be valid amounts within security, with a documented reason.',
          'INVALID_RETURN_ISSUE' =>
            'Record a clear issue note of at least 10 characters after collection and before completing return inspection.',
          'REFUND_REFERENCE_REQUIRED' =>
            'Enter a verified refund or test payment reconciliation reference (5–100 characters).',
          'REFUND_NOT_DUE' ||
          'REFUND_REVIEW_REQUIRED' ||
          'REFUND_ALREADY_RECORDED' =>
            'Refresh the rental and review its existing inspection and refund record.',
          'PACKAGE_CANCELLATION_REVIEW_REQUIRED' =>
            'This fitting fee has already been credited to a rental. Contact staff to review the package cancellation.',
          'PAYMENT_METHOD_UNAVAILABLE' =>
            'This payment method is not connected. Choose FPX online banking.',
          'NO_STAFF_AVAILABLE' =>
            'No employee is available at this time. Choose another available time.',
          'AVAILABILITY_CHANGED' =>
            'This schedule changed. Refresh it before saving.',
          'AVAILABILITY_HAS_BOOKINGS' =>
            'You have assigned appointments in this time. Ask a manager to arrange qualified cover or agree a new appointment time first.',
          'TIME_OFF_REQUEST_REQUIRED' =>
            'Time off requires manager approval. Open Staff scheduling to submit a request.',
          'MINIMUM_STAFF_COVERAGE' =>
            'Not enough employees would remain on duty. Choose another time or ask the manager to arrange cover.',
          'MINIMUM_ROLE_COVERAGE' =>
            'This would leave insufficient cover for a required work role.',
          'MINIMUM_SERVICE_COVERAGE' =>
            'Not enough qualified employees would remain for a required service.',
          'STAFF_PROFILES_REQUIRED' =>
            'Configure scheduling responsibilities for every active employee before requiring explicit service assignments.',
          'STAFF_EMAIL_IN_USE' =>
            'This email is already in use or reserved. Enter another work email for this employee.',
          'STAFF_ACCOUNT_LIMIT' =>
            'This project supports up to 100 staff account records, including retained history. Contact the system administrator before adding more accounts.',
          'STAFF_ACCOUNT_CHANGED' || 'STAFF_ACCOUNT_CONFLICT' =>
            'This account changed or the identity could not be verified. Refresh its details before continuing.',
          'STAFF_ACCOUNT_BUSY' =>
            'This account request is still being processed. Wait a minute, then retry the same request.',
          'STAFF_ACCOUNT_SYNC_REQUIRED' =>
            'Access is paused while authentication needs synchronisation. Open the account and retry access sync.',
          'STAFF_SELF_PROTECTION' =>
            'You cannot deactivate yourself or remove your own manager access.',
          'LAST_MANAGER_REQUIRED' => 'At least one active manager must remain.',
          'STAFF_ROLE_PROTECTED' =>
            'Only Staff accounts can be created here. Contact the system administrator to change system access roles.',
          'STAFF_HAS_WORK' =>
            'This employee has unfinished assigned appointments, tasks or support tickets. Reassign or properly complete them before deactivation.',
          'STAFF_RESPONSIBILITIES_REQUIRED' =>
            'Set the employee’s work role and eligible services before activation.',
          'STAFF_SETUP_EMAIL_REQUIRED' =>
            'Send the password setup email before activating this account.',
          'STAFF_AUTH_MISSING' ||
          'STAFF_AUTH_UNAVAILABLE' ||
          'STAFF_AUTH_DISABLED' =>
            'The login account is unavailable or disabled. Refresh its details and check authentication sync.',
          'STAFF_ACCOUNT_NOT_FOUND' =>
            'This staff account is no longer available. Refresh the staff list.',
          'STAFF_MAIL_UNAVAILABLE' =>
            'Password setup email is not configured. Contact the system administrator.',
          'STAFF_INVITE_WAIT' =>
            'Wait at least one minute before requesting another setup email.',
          'STAFF_INVITE_REVIEW' =>
            'This email request needs review. Check the employee’s inbox before sending a new email.',
          'INVALID_STAFF_ACCOUNT' || 'INVALID_STAFF_ACCOUNT_STATUS' =>
            'Review the employee details, work role and contact information, then try again.',
          'STAFF_HAS_SERVICE_BOOKINGS' =>
            'This employee has future appointments for a service you are removing. Reassign those appointments first.',
          'STAFF_SERVICE_REQUIRED' =>
            'Choose an active employee qualified for this service.',
          'STAFF_NOT_AVAILABLE' =>
            'This employee is unavailable or already assigned at that time.',
          'TIME_OFF_DAY_HAS_EXCEPTION' =>
            'This day already has a schedule exception. Ask a manager to review it before requesting another window.',
          'SCHEDULING_CHANGED' =>
            'Scheduling information changed. Refresh before saving.',
          'SCHEDULE_ACCESS_DENIED' || 'TIME_OFF_ACCESS_DENIED' =>
            'You do not have access to this scheduling action.',
          'TIME_OFF_STATE' || 'TIME_OFF_NOT_FOUND' =>
            'This time-off record changed or is no longer available. Refresh the requests.',
          'INVALID_TIME_OFF' =>
            'Choose a valid date and time, and enter a brief reason of at least five characters.',
          'INVALID_TIME_OFF_REVIEW' ||
          'INVALID_STAFF_SCHEDULING' ||
          'INVALID_COVERAGE_POLICY' =>
            'Review the scheduling details and try again.',
          'INVALID_AVAILABILITY_DATE' =>
            'Choose today or a date within the next 179 days.',
          'INVALID_SCHEDULE_MONTH' =>
            'Choose this month or a month within the next 179 days.',
          'SCHEDULE_LIMIT' =>
            'Your schedule contains too many records to load completely. Contact the manager for help.',
          'INVALID_AVAILABILITY' =>
            'Choose a valid availability window between 09:00 and 18:00.',
          'BOOKING_CHANGED' =>
            'This appointment changed. Refresh before updating it.',
          'INVALID_RESCHEDULE' || 'RESCHEDULE_SAME_TIME' =>
            'Choose a different available appointment date or time.',
          'RESCHEDULE_PAYMENT_REQUIRED' =>
            'Complete the fitting payment before changing this appointment.',
          'RESCHEDULE_PAYMENT_REVIEW' =>
            'This fitting payment needs staff review before the appointment can be changed.',
          'RESCHEDULE_NOT_AVAILABLE' =>
            'Only a confirmed appointment that has not started can be rescheduled.',
          'BOOKING_RESERVATION_CHANGED' ||
          'APPOINTMENT_PACKAGE_REVIEW_REQUIRED' =>
            'This visit or linked package needs staff review. Your current appointment has not been changed.',
          'OPERATIONS_ACCESS_REQUIRED' =>
            'This action is available to front desk and managers.',
          'BOOKING_ACCESS_DENIED' => 'You cannot update this appointment.',
          'INVALID_BOOKING_TRANSITION' =>
            'This appointment cannot be changed. Completion is available only after the visit starts.',
          'RENTAL_PLAN_REQUIRED' =>
            'Set your rental dates before booking the fitting.',
          'FITTING_CONSENT_REQUIRED' =>
            'The customer must first request and acknowledge renting without a fitting.',
          'CANCEL_FITTING_FIRST' =>
            'Cancel the existing fitting in Bookings before requesting no fitting. Paid cancellations require refund review.',
          'FITTING_CHANGED' =>
            'The fitting arrangement changed. Reload this package and try again.',
          'INVALID_SERVICE_PROGRESS' =>
            'Review the preparation status and add a staff note.',
          'SERVICE_PROGRESS_CHANGED' =>
            'This service record changed. Refresh the rental before updating it.',
          'SERVICE_PROGRESS_CLOSED' =>
            'Preparation cannot be changed after collection or on a closed rental.',
          'SERVICE_ITEMS_REQUIRED' =>
            'Select the rental items before recording their preparation.',
          'SERVICE_NOT_READY' =>
            'Approve the fitting, reserve the rental and complete any alterations before marking items prepared.',
          'FITTING_CHOICE_CONFLICT' =>
            'This package requests no fitting. Change the fitting preference before booking a visit.',
          'FITTING_RESULT_REQUIRED' =>
            'Record a satisfactory fitting outcome or approve the customer’s no-fitting request first.',
          'COMPLETED_FITTING_UNAVAILABLE' =>
            'This fitting is no longer eligible for this package. Check your dates or contact Luvly.',
          'COMPLETED_FITTING_ALREADY_LINKED' =>
            'A completed fitting is already linked. Wait for Luvly to review it before booking again.',
          'INVALID_COMPLETED_FITTING' =>
            'Reopen the package and select a completed fitting again.',
          'FITTING_FEE_REVIEW' =>
            'The fitting payment must be verified and free of review flags before recording attendance.',
          'INVALID_FITTING_RESULT' =>
            'Select a confirmed fitting, add a clear note and confirm the actual service record.',
          'INVALID_FITTING_CHOICE' =>
            'Review the fitting preference and consent before saving.',
          'FITTING_DATE_CONFLICT' =>
            'Same-day pickup requires recorded fitting completion. Otherwise choose a fitting before pickup. The fitting must always be before the wedding date.',
          'PAYMENT_HISTORY_LIMIT' =>
            'We could not load your complete payment history. Please contact Luvly for assistance.',
          'APPOINTMENT_AFTER_PICKUP' =>
            'The fitting appointment is after the pickup date. Adjust the rental dates or arrange an earlier appointment.',
          'PACKAGE_RENTAL_PERIOD' =>
            'This package includes three rental days (pickup and return included). Select the extra rental-day service for one additional day.',
          'RENTAL_PLAN_CHANGED' =>
            'Rental dates have changed. Refresh the package and review them again.',
          'PACKAGE_RENTAL_ITEMS_REQUIRED' =>
            'Select the actual rental items before staff confirmation.',
          'PACKAGE_PAYMENT_REVIEW_REQUIRED' =>
            'This package already has a payment invoice. Staff must review it before creating another deposit.',
          'PACKAGE_RENTAL_CONFIRMATION_REQUIRED' =>
            'Set rental dates and confirm package stock before issuing a booking deposit.',
          'INVALID_VARIANT' => 'Enter a whole stock quantity from 0 to 100.',
          'INVALID_VARIANT_SIZE' =>
            'This size is no longer listed. Reopen the dress details.',
          'VARIANT_CHANGED' =>
            'Another staff member changed this stock. Refresh before editing.',
          'QUANTITY_BELOW_RESERVED' =>
            'This quantity is below stock already reserved. Resolve the reservations first.',
          'INVENTORY_NOT_CONFIGURED' =>
            'Stock has not been confirmed for one of your selected items. Choose another gown, size or accessory, or contact Luvly.',
          'RENTAL_STOCK_UNAVAILABLE' =>
            'A selected item is unavailable for your rental and cleaning dates. Choose another item or change your dates.',
          'RENTAL_HOLD_EXPIRED' =>
            'The 15-minute rental hold has ended. Ask staff to check availability before paying.',
          'RENTAL_ALREADY_EXISTS' =>
            'This appointment already has an active rental. Review it before creating another.',
          'INVALID_RENTAL_DATE_ORDER' ||
          'INVALID_RENTAL_DATE' ||
          'RENTAL_DATE_RANGE' =>
            'Check pickup, event and return dates. Pickup must not be in the past; rentals can span up to 31 calendar dates.',
          'PACKAGE_RENTAL_INTEGRATION_REQUIRED' =>
            'Package rental reservation is not enabled yet. No extra deposit has been created.',
          'SIGN_IN_REQUIRED' => 'Please sign in again.',
          'ACCOUNT_ACCESS_REQUIRED' ||
          'BRIDE_REQUIRED' ||
          'STAFF_REQUIRED' ||
          'SELECTION_ACCESS_DENIED' =>
            'Your account cannot perform this action. Please sign in with the correct account.',
          'INVALID_PACKAGE_TEXT' =>
            'Enter a package name (3–100 characters) and description (10–1,500 characters).',
          'INVALID_PACKAGE_PRICE' =>
            'Check the base price and deductions. The total must be at least RM 2.00 for a published gown rental and RM 1.00 for other packages.',
          'PACKAGE_PRICE_LIMIT' =>
            'The total with all add-ons must be at most RM 1,000,000.00.',
          'INVALID_PACKAGE_ACCESSORY_ALLOWANCE' =>
            'Enter an accessory allowance for each accessory service.',
          'PACKAGE_GOWNS_NOT_READY' =>
            'Link enough different published gowns with stock in at least one size. Check Dress inventory before publishing.',
          'PACKAGE_GOWN_LIMIT_CHANGED' =>
            'The number of rentable gown styles has changed. Refresh the limit and choose a quantity again.',
          'PACKAGE_LINKED_GOWN_REQUIRED' =>
            'Include a gown rental before publishing a package with scheduled services, accessories or an extra rental day.',
          'INVALID_PACKAGE_SERVICES' || 'INVALID_PACKAGE' =>
            'Check the package and service details before saving.',
          'DUPLICATE_SERVICE' => 'Each service can only appear once.',
          'REQUIRED_SERVICE_NEEDED' =>
            'Include at least one mandatory service.',
          'BRIDAL_SERVICE_PRICE_CHANGED' =>
            'A linked service price changed. Select its current catalogue revision and review again.',
          'INVALID_BRIDAL_SERVICE_PRICE' =>
            'Check the service name, pricing method and unit price.',
          'INVALID_BUNDLE_DISCOUNT' =>
            'Enter a valid bundle discount that does not exceed the subtotal.',
          'PACKAGE_PRICING_CONFIGURATION_REQUIRED' =>
            'Link a catalogue price to each service and choose a price source for each included gown.',
          'APPROVED_PACKAGE_SUBTOTAL_TOO_LOW' =>
            'The configured services and gowns total less than the approved price. Check the linked prices and quantities.',
          'PACKAGE_REVIEW_CHANGED' =>
            'The package changed since review. Review the saved draft again before publishing.',
          'CUSTOM_SERVICE_REQUIRES_GOWN' =>
            'A selected service or accessory requires a gown rental. Review your choices.',
          'INVALID_CUSTOM_EVENT_DATE' =>
            'Choose a valid event date for your service quote.',
          'INVALID_STANDALONE_ELIGIBILITY' =>
            'Enable custom packages and choose a supported standalone service type.',
          'SERVICE_APPOINTMENT_TEAM_REVIEW' =>
            'Contact Luvly to arrange the timing and payment for this service quote.',
          'SERVICE_APPOINTMENT_DATE' =>
            'Choose an appointment on or before your event date.',
          'PACKAGE_GOWN_ALLOWANCE_REQUIRED' =>
            'Set an active standard gown allowance in Manage service prices before reviewing this package.',
          'PACKAGE_GOWN_PRICE_REQUIRED' =>
            'A selected gown needs a valid rental price before it can be quoted.',
          'INVALID_PACKAGE_GOWN_PRICING' =>
            'Choose one distinct, eligible catalogue gown price per included gown.',
          'INVALID_PACKAGE_COMPONENT' =>
            'Check linked service references, pricing methods and quantities.',
          'PACKAGE_CHANGED' =>
            'This package has changed. Reopen it to review the latest details and price.',
          'ACCESSORY_CATALOGUE_CHANGED' =>
            'Accessory prices have changed. Update Luvly and review your selection again.',
          'INVALID_ACCESSORY_SELECTION' =>
            'Check your accessories: select each item once, under an included service. Veils must use the veil service.',
          'INVALID_GOWN_MEASUREMENTS' =>
            'Enter all measurement ranges and gown length in cm (20–300, at most one decimal). Minimum cannot exceed maximum.',
          'INVALID_PACKAGE_GOWNS' =>
            'Choose a valid gown quantity for this package.',
          'PACKAGE_CLIENT_UPDATE_REQUIRED' =>
            'Update or restart Luvly before editing this package.',
          'INVALID_GOWN_SELECTION' || 'PACKAGE_GOWN_COUNT' =>
            'Choose the required number of different gowns and a size for each.',
          'PACKAGE_GOWN_NOT_ELIGIBLE' =>
            'A selected gown is not included in this package. Please choose again.',
          'FITTING_GOWNS_UNCHANGED' =>
            'The gown selection has not changed. Keep the current selection, or choose a different gown or size.',
          'PACKAGE_GOWN_UNAVAILABLE' ||
          'PACKAGE_GOWN_CHANGED' ||
          'PACKAGE_GOWN_SIZE' =>
            'A gown or size has changed or is unavailable. Reopen the gown picker to choose again.',
          'PACKAGE_UNAVAILABLE' =>
            'This package is no longer available for new selections.',
          'MANDATORY_SERVICE' => 'Mandatory services cannot be removed.',
          'INVALID_ADDON' =>
            'One of these extras is no longer available. Reopen the package.',
          'REQUEST_CONFLICT' =>
            'This request was already saved with different details. Refresh before continuing.',
          'PACKAGE_BOOKING_EXISTS' =>
            'This package already has an appointment request. View it under Bookings.',
          'SLOT_UNAVAILABLE' =>
            'This time has been booked. Please choose another time.',
          'INVALID_BOOKING' =>
            'Choose a future appointment time and keep notes within 700 characters.',
          'TOO_MANY_APPOINTMENTS' =>
            'Please contact Luvly to arrange another appointment for this package.',
          'BODY_TOO_LARGE' =>
            'These details are too long. Shorten the descriptions and try again.',
          'MANAGER_REQUIRED' =>
            'Only an active manager can perform this action.',
          'DIRECTORY_ACCESS_REQUIRED' =>
            'Your account does not have access to these records.',
          'DIRECTORY_LIMIT' =>
            'There are too many records to load safely. Contact the manager for a scoped report.',
          'LIST_LIMIT' =>
            'There are too many records to load completely. Please contact Luvly for help finding your record.',
          'INVALID_DIRECTORY_QUERY' =>
            'Could not load this list. Refresh and try again.',
          'PACKAGE_IN_USE' =>
            'This package has customer records and cannot be deleted. Deactivate it to stop new selections while keeping existing records.',
          'APPOINTMENT_HAS_PACKAGE' =>
            'This appointment belongs to a package. Review its invoice in Customer rentals.',
          'QUOTE_ALREADY_EXISTS' =>
            'An invoice already exists with a different amount. Contact the manager.',
          'CONFIRMED_APPOINTMENT_REQUIRED' =>
            'This appointment is no longer confirmed. Contact Luvly.',
          'APPOINTMENT_DRESS_REQUIRED' =>
            'Select a confirmed appointment linked to a dress.',
          'DRESS_UNAVAILABLE' => 'The linked dress is no longer available.',
          'BILL_CREATION_REQUIRES_REVIEW' || 'BILL_CREATION_UNCERTAIN' =>
            'Bill creation needs manager review. Do not submit another payment.',
          'INVOICE_ALREADY_SETTLED_OR_REVIEW' =>
            'Check the invoice status before continuing.',
          'TRY_LATER' => 'Please wait a minute before trying again.',
          _ =>
            'Unable to complete this request. Check the status before retrying.',
        }, code: code);
      }
      if (response.body.length > 1048576) throw const FormatException();
      return jsonDecode(response.body);
    } on PaymentFailure {
      rethrow;
    } catch (_) {
      throw const PaymentFailure(
        'Cannot connect to Luvly right now. Please try again shortly. If you already submitted a payment, check its status before paying again.',
      );
    }
  }

  @override
  Future<List<SandboxInvoice>> list() async {
    final data = await _request('/v1/invoices') as Map<String, dynamic>;
    if (data['limited'] == true) {
      throw const PaymentFailure(
        'We could not load your complete payment history. Please contact Luvly for assistance.',
      );
    }
    return (data['invoices'] as List)
        .map((row) => SandboxInvoice.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<SandboxInvoice> quote(
    String appointmentId,
    String purpose,
    int amountCents,
  ) async => SandboxInvoice.fromJson(
    await _request(
          '/v1/invoices',
          body: {
            'appointmentId': appointmentId,
            'purpose': purpose,
            'amountCents': amountCents,
          },
        )
        as Map<String, dynamic>,
  );
  @override
  Future<SandboxInvoice> checkout(
    String id, {
    String paymentMethod = 'FPX',
  }) async => SandboxInvoice.fromJson(
    await _request(
          '/v1/invoices/$id/checkout',
          body: {'paymentMethod': paymentMethod},
        )
        as Map<String, dynamic>,
  );
  @override
  Future<SandboxInvoice> refresh(String id) async => SandboxInvoice.fromJson(
    await _request('/v1/invoices/$id/refresh', body: {})
        as Map<String, dynamic>,
  );
  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}
