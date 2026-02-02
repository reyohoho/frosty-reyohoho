import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frosty/screens/settings/stores/auth_store.dart';
import 'package:frosty/widgets/frosty_app_bar.dart';
import 'package:ua_parser/ua_parser.dart';
import 'package:webview_flutter/webview_flutter.dart';

const _uaCheckUrl = 'https://cdn.rte.net.ru/ua';

/// Screen that loads the UA check URL in a WebView (same config as auth/login)
/// to debug what User-Agent the server receives from the WebView.
class UserAgentDebugScreen extends StatefulWidget {
  const UserAgentDebugScreen({super.key});

  @override
  State<UserAgentDebugScreen> createState() => _UserAgentDebugScreenState();
}

class _UserAgentDebugScreenState extends State<UserAgentDebugScreen> {
  late final WebViewController _controller;
  bool _captured = false;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(AuthBase.webViewUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _capturePageContent(),
        ),
      )
      ..loadRequest(Uri.parse(_uaCheckUrl));
  }

  Future<void> _capturePageContent() async {
    if (_captured) return;
    _captured = true;

    try {
      final result = await _controller.runJavaScriptReturningResult(
        "document.body ? document.body.innerText : document.documentElement.innerText",
      );

      final rawUa = _extractString(result);
      if (rawUa != null && rawUa.isNotEmpty && mounted) {
        _showResultDialog(rawUa.trim());
      }
    } catch (e) {
      debugPrint('UserAgent debug capture error: $e');
      if (mounted) {
        _showResultDialog(null, error: e.toString());
      }
    }
  }

  String? _extractString(Object? result) {
    if (result == null) return null;
    if (result is String) return result;
    return result.toString();
  }

  void _showResultDialog(String? rawUa, {String? error}) {
    showDialog(
      context: context,
      builder: (context) => _UserAgentResultDialog(
        rawUa: rawUa,
        error: error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: FrostyAppBar(
        title: const Text('Debug: User-Agent (WebView)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload',
            onPressed: () {
              setState(() => _captured = false);
              _controller.loadRequest(Uri.parse(_uaCheckUrl));
            },
          ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}

class _UserAgentResultDialog extends StatelessWidget {
  final String? rawUa;
  final String? error;

  const _UserAgentResultDialog({this.rawUa, this.error});

  Future<void> _copyToClipboard(BuildContext context) async {
    if (rawUa == null || rawUa!.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: rawUa!));

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('User-Agent copied to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Debug: User-Agent'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    error!,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              )
            else if (rawUa != null && rawUa!.isNotEmpty) ...[
              _ParsedUaSection(userAgent: rawUa!),
              const SizedBox(height: 16),
              Text(
                'Raw response (from WebView)',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  rawUa!,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (rawUa != null && rawUa!.isNotEmpty)
          FilledButton.icon(
            onPressed: () => _copyToClipboard(context),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy UA'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ParsedUaSection extends StatelessWidget {
  final String userAgent;

  const _ParsedUaSection({required this.userAgent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = UaParser.parse(userAgent);

    String format(String? value) =>
        value != null && value.isNotEmpty ? value : '—';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Parsed',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _ParsedRow(
            label: 'OS',
            value: '${format(result.os.name)} ${format(result.os.version)}'.trim(),
          ),
          _ParsedRow(
            label: 'Browser',
            value:
                '${format(result.browser.name)} ${format(result.browser.version)}'
                    .trim(),
          ),
          _ParsedRow(
            label: 'Engine',
            value:
                '${format(result.engine.name)} ${format(result.engine.version)}'
                    .trim(),
          ),
          _ParsedRow(
            label: 'Device',
            value:
                '${format(result.device.vendor)} ${format(result.device.model)}'
                    .trim(),
          ),
          if (result.device.type != null && result.device.type!.isNotEmpty)
            _ParsedRow(label: 'Device type', value: result.device.type!),
          _ParsedRow(
            label: 'CPU',
            value: format(result.cpu.architecture),
          ),
        ],
      ),
    );
  }
}

class _ParsedRow extends StatelessWidget {
  final String label;
  final String value;

  const _ParsedRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              '$label:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
