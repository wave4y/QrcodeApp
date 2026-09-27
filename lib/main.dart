import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'qr_content.dart';
import 'scan_page.dart';
import 'raptor_transfer_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '二维码工具',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const QRGeneratorPage(),
    );
  }
}

class QRGeneratorPage extends StatefulWidget {
  const QRGeneratorPage({super.key});

  @override
  State<QRGeneratorPage> createState() => _QRGeneratorPageState();
}

class _QRGeneratorPageState extends State<QRGeneratorPage> {
  final TextEditingController _textController = TextEditingController();
  String _currentText = '';
  final PageController _pageController = PageController();
  List<String> _qrCodePages = [];
  int _currentPage = 0;
  bool _openingScanner = false;

  Future<void> _scanQRCode() async {
    if (_openingScanner) return;
    setState(() => _openingScanner = true);
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (context) => const ScanPage()),
      );
      if (!mounted || result == null) return;
      _replaceText(result);
    } finally {
      if (mounted) setState(() => _openingScanner = false);
    }
  }

  Future<void> _pasteText() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      final text = data?.text;
      if (text == null || text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('剪贴板中没有可粘贴的文本')),
        );
        return;
      }
      _replaceText(text);
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法读取剪贴板，请重试')),
      );
    }
  }

  Future<void> _copyResult() async {
    final text = _textController.text;
    if (text.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('已复制')));
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('复制失败，请重试')),
      );
    }
  }

  void _replaceText(String text) {
    _textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _updateQRCodePages(text);
  }

  void _updateQRCodePages(String text) {
    // Reset only while the PageView is attached, including after clearing it.
    if (_pageController.hasClients) _pageController.jumpToPage(0);
    setState(() {
      _currentText = text;
      _qrCodePages = splitQRContent(text);
      _currentPage = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final qrSize = math.min(MediaQuery.of(context).size.width - 32, 320.0);
    return Scaffold(
      appBar: AppBar(
        title: TextButton(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: _openingScanner
              ? null
              : () async {
                  setState(() => _openingScanner = true);
                  FocusManager.instance.primaryFocus?.unfocus();
                  try {
                    final mode = await showModalBottomSheet<int>(
                      context: context,
                      builder: (context) => SafeArea(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          ListTile(
                            leading: const Icon(Icons.bolt),
                            title: const Text('高速流水码 · Cimbar'),
                            subtitle: const Text('手机创建和扫描，彩色码传文件'),
                            onTap: () => Navigator.pop(context, 0),
                          ),
                          ListTile(
                            leading: const Icon(Icons.qr_code),
                            title: const Text('黑白流水码 · 兼容旧版'),
                            subtitle: const Text('接收或创建之前的 RaptorQ 流水码'),
                            onTap: () => Navigator.pop(context, 1),
                          ),
                        ]),
                      ),
                    );
                    if (!context.mounted || mode == null) return;
                    if (mode == 0) {
                      await const MethodChannel('qrcodeapp/raptorq')
                          .invokeMethod<void>('openCimbar');
                    } else {
                      await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RaptorTransferPage(),
                          ));
                    }
                  } on PlatformException catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('无法打开高速传输，请重试')),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _openingScanner = false);
                  }
                },
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text('二维码工具', style: TextStyle(fontSize: 20))),
              Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: '扫描二维码',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _openingScanner ? null : _scanQRCode,
          ),
          IconButton(
            tooltip: '复制结果',
            icon: const Icon(Icons.copy_outlined),
            onPressed: _currentText.isEmpty ? null : _copyResult,
          ),
          IconButton(
            tooltip: '粘贴',
            icon: const Icon(Icons.content_paste),
            onPressed: _pasteText,
          ),
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.clear),
            onPressed: () => _replaceText(''),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                controller: _textController,
                maxLines: null,
                minLines: 3,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  labelText: '请输入要生成二维码的内容',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                  contentPadding: EdgeInsets.all(16),
                ),
                onChanged: _updateQRCodePages,
              ),
              const SizedBox(height: 20),
              if (_qrCodePages.isNotEmpty) ...[
                SizedBox(
                  height: qrSize + 100,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _qrCodePages.length,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      return Column(
                        children: [
                          QrImageView(
                            data: _qrCodePages[index],
                            version: QrVersions.auto,
                            size: qrSize,
                            padding: const EdgeInsets.all(24),
                            backgroundColor: Colors.white,
                            errorCorrectionLevel: QrErrorCorrectLevel.M,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '第 ${index + 1}/${_qrCodePages.length} 页',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '当前页字符数: ${_qrCodePages[index].runes.length}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                if (_qrCodePages.length > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios),
                        onPressed: _currentPage > 0
                            ? () {
                                _pageController.previousPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              }
                            : null,
                      ),
                      Text(
                        '${_currentPage + 1} / ${_qrCodePages.length}',
                        style: const TextStyle(fontSize: 16),
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward_ios),
                        onPressed: _currentPage < _qrCodePages.length - 1
                            ? () {
                                _pageController.nextPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              }
                            : null,
                      ),
                    ],
                  ),
                const SizedBox(height: 10),
                Text(
                  '总字符数: ${_currentText.runes.length}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      resizeToAvoidBottomInset: true,
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _pageController.dispose();
    super.dispose();
  }
}
