import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/checkout_service.dart';

const _pageBackground = Color(0xFF080B09);
const _panelBackground = Color(0xFF111613);
const _accent = Color(0xFF39FF14);
const _mutedText = Color(0xFF9BA69E);

class TrackOrderScreen extends StatefulWidget {
  const TrackOrderScreen({this.initialOrderId, super.key});

  final String? initialOrderId;

  @override
  State<TrackOrderScreen> createState() => _TrackOrderScreenState();
}

class _TrackOrderScreenState extends State<TrackOrderScreen> {
  late final TextEditingController _orderIdController;
  late final _checkoutService = CheckoutService();
  Map<String, dynamic>? _order;
  String? _errorMessage;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _orderIdController = TextEditingController(
      text: widget.initialOrderId ?? '',
    );
    if (widget.initialOrderId?.isNotEmpty == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadOrder();
      });
    }
  }

  @override
  void dispose() {
    _orderIdController.dispose();
    super.dispose();
  }

  Future<void> _loadOrder() async {
    final orderId = _orderIdController.text.trim();
    if (orderId.isEmpty || orderId.length > 64) {
      setState(() {
        _order = null;
        _errorMessage = 'Enter the order ID from your checkout confirmation.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
      _order = null;
    });
    try {
      final order = await _checkoutService.getOrderTracking(orderId);
      if (mounted) setState(() => _order = order);
    } on CheckoutFailure catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (error, stackTrace) {
      debugPrint('[twrxa] Order lookup failed: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not load tracking details. Please retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _statusLabel(Object? value) {
    if (value is! String || value.isEmpty) return 'UPDATING';
    return value.replaceAll('_', ' ').toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        title: const Text('TRACK ORDER'),
        backgroundColor: _pageBackground,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'YOUR ORDER, IN MOTION.',
            style: TextStyle(
              color: _accent,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Enter the order ID from your checkout confirmation. '
            'Tracking appears as soon as Printify ships your items.',
            style: TextStyle(color: _mutedText, height: 1.5),
          ),
          const SizedBox(height: 24),
          TextField(
            key: const ValueKey('track-order-id'),
            controller: _orderIdController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _loadOrder(),
            decoration: const InputDecoration(
              labelText: 'Order ID',
              hintText: 'Paste your order ID',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            key: const ValueKey('track-order-submit'),
            onPressed: _loading ? null : _loadOrder,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('LOOK UP ORDER'),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 18),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Color(0xFFFF8B8B)),
            ),
          ],
          if (order != null) ...[
            const SizedBox(height: 26),
            _OrderCard(
              order: order,
              statusLabel: _statusLabel,
            ),
          ],
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.statusLabel,
  });

  final Map<String, dynamic> order;
  final String Function(Object?) statusLabel;

  @override
  Widget build(BuildContext context) {
    final shipments = order['shipments'] is List
        ? List<dynamic>.from(order['shipments'] as List)
        : const <dynamic>[];
    final items = order['items'] is List
        ? List<dynamic>.from(order['items'] as List)
        : const <dynamic>[];
    final trackingUrl = order['trackingUrl'];
    final trackingUri =
        trackingUrl is String ? Uri.tryParse(trackingUrl) : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _panelBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF28312B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ORDER ${order['orderId'] ?? ''}',
            style: const TextStyle(
              color: _mutedText,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.local_shipping_outlined, color: _accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  statusLabel(order['status']),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Payment: ${statusLabel(order['paymentStatus'])}  ·  '
            'Printify: ${statusLabel(order['printifyStatus'])}',
            style: const TextStyle(color: _mutedText, fontSize: 12),
          ),
          if (items.isNotEmpty) ...[
            const Divider(height: 26, color: Color(0xFF28312B)),
            for (final item in items)
              if (item is Map)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${item['name'] ?? 'Item'}'
                    '${item['variant'] == null ? '' : ' (${item['variant']})'}'
                    ' × ${item['quantity'] ?? 1}',
                    style: const TextStyle(color: _mutedText),
                  ),
                ),
          ],
          if (shipments.isNotEmpty || order['trackingNumber'] != null) ...[
            const Divider(height: 26, color: Color(0xFF28312B)),
            if (order['trackingCarrier'] is String)
              Text(
                'Carrier: ${order['trackingCarrier']}',
                style: const TextStyle(color: _mutedText),
              ),
            if (order['trackingNumber'] is String)
              SelectableText(
                'Tracking: ${order['trackingNumber']}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            if (trackingUri != null &&
                (trackingUri.scheme == 'https' || trackingUri.scheme == 'http'))
              TextButton.icon(
                onPressed: () => launchUrl(
                  trackingUri,
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('OPEN CARRIER TRACKING'),
              ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 18),
              child: Text(
                'Tracking will appear here after the carrier receives your package.',
                style: TextStyle(color: _mutedText),
              ),
            ),
        ],
      ),
    );
  }
}
