import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/courier.dart';

/// Shopleap support email.
const String kSupportEmail = 'shopleapmobile@gmail.com';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  Future<void> _sendEmail(
    BuildContext context, {
    required String subject,
    required String body,
  }) async {
    final uri = Uri.parse(
      'mailto:$kSupportEmail'
      '?subject=${Uri.encodeComponent(subject)}'
      '&body=${Uri.encodeComponent(body)}',
    );

    bool opened = false;
    try {
      opened = await launchUrl(uri);
    } catch (_) {
      opened = false;
    }

    if (!opened && context.mounted) {
      await Clipboard.setData(const ClipboardData(text: kSupportEmail));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No email app found. The email address was copied.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = Courier.current.name.trim();
    final who = name.isEmpty ? 'Courier' : name;

    Widget sectionTitle(String t) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(
            t,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        sectionTitle('Contact us'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.email_outlined),
                title: const Text('Email support'),
                subtitle: const Text(kSupportEmail),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _sendEmail(
                  context,
                  subject: 'Courier app support',
                  body: 'Hello Shopleap,\n\n\n\nFrom: $who',
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('Report a problem'),
                subtitle: const Text('Tell us what happened'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _sendEmail(
                  context,
                  subject: 'Problem report - Courier app',
                  body: 'What happened?\n\n\n'
                      'Which screen were you on?\n\n\n'
                      'Order # (if any):\n\n\n'
                      'From: $who',
                ),
              ),
            ],
          ),
        ),
        sectionTitle('FAQ'),
        const Card(
          child: Column(
            children: [
              _Faq(
                q: 'How do I scan a parcel?',
                a: 'Tap the Scan button in the middle of the bottom bar and point the camera at the parcel\'s QR code.',
              ),
              Divider(height: 1),
              _Faq(
                q: 'Where can I see my earnings?',
                a: 'Open the menu and choose Profit / Earnings. You can pick Today, Week, Month, or All.',
              ),
              Divider(height: 1),
              _Faq(
                q: 'Where can I see my past deliveries?',
                a: 'Open the menu and choose Delivery history. Tap a delivery to see its details.',
              ),
              Divider(height: 1),
              _Faq(
                q: 'How do I change my photo or name?',
                a: 'Open the menu, choose Account, and edit your information there.',
              ),
              Divider(height: 1),
              _Faq(
                q: 'How do I turn on dark mode?',
                a: 'Open the menu, choose Settings, and pick System, Light, or Dark.',
              ),
              Divider(height: 1),
              _Faq(
                q: 'I have a problem with the app or an order.',
                a: 'Use Report a problem above and describe what happened, including the order number if you have one.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Faq extends StatelessWidget {
  final String q;
  final String a;
  const _Faq({required this.q, required this.a});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(q, style: const TextStyle(fontWeight: FontWeight.w600)),
        children: [Text(a)],
      ),
    );
  }
}