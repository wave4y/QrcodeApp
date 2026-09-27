import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'raptor_camera.dart';
import 'raptor_transfer.dart';

class RaptorTransferPage extends StatefulWidget {
  const RaptorTransferPage({super.key});
  @override
  State<RaptorTransferPage> createState() => _RaptorTransferPageState();
}

class _RaptorTransferPageState extends State<RaptorTransferPage>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  int _tab = 0;
  bool _ready = false;
  bool _working = false;
  bool _decoding = false;
  bool _receiving = true;
  bool _playing = false;
  bool _generating = false;
  bool _complete = false;
  bool _saved = false;
  int _generation = 0;
  int _received = 0;
  int _needed = 0;
  int _sent = 0;
  double _progress = 0;
  double _fps = 4;
  String? _status;
  String? _platformError;
  String? _qr;
  Map<Object?, Object?>? _sender;
  Map<Object?, Object?>? _file;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await RaptorTransfer.keepAwake(true);
      await RaptorTransfer.resetReceiver();
      await RaptorTransfer.clearSender();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) {
        setState(() => _platformError = '请使用 Android 版 App 进行 RaptorQ 文件传输');
      }
    }
  }

  void _message(Object error) {
    if (!mounted) return;
    final text =
        error is PlatformException ? error.message ?? '操作失败，请重试' : '操作失败，请重试';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _pause() {
    _timer?.cancel();
    _timer = null;
    _generation++;
    _playing = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _playing) {
      setState(_pause);
    }
  }

  void _switchTab(int value) {
    if (_working || !_ready || value == _tab) return;
    setState(() {
      _pause();
      _tab = value;
    });
  }

  Future<void> _prepare({bool text = false}) async {
    if (_working) return;
    setState(() {
      _pause();
      _working = true;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final info = text
          ? await RaptorTransfer.createText(_text.text)
          : await RaptorTransfer.pickFile();
      if (!mounted || info == null) return;
      setState(() {
        _sender = info;
        _qr = null;
        _sent = 0;
      });
      await _nextFrame(_generation);
    } catch (error) {
      _message(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _nextFrame(int generation) async {
    if (_generating) return;
    _generating = true;
    try {
      final bytes = await RaptorTransfer.nextFrame();
      if (!mounted || generation != _generation || bytes == null) return;
      final qr = RaptorTransfer.qrText(bytes);
      setState(() {
        _qr = qr;
        _sent++;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(_pause);
        _message(error);
      }
    } finally {
      _generating = false;
    }
  }

  void _play() {
    if (_sender == null || _working) return;
    setState(() {
      _playing = true;
      final generation = _generation;
      _timer = Timer.periodic(Duration(milliseconds: (1000 / _fps).round()),
          (_) => _nextFrame(generation));
    });
  }

  Future<void> _capture(BarcodeCapture capture) async {
    if (!_ready ||
        _decoding ||
        _working ||
        !_receiving ||
        _complete ||
        _tab != 0) {
      return;
    }
    _decoding = true;
    final generation = _generation;
    try {
      for (final code in capture.barcodes) {
        final data = RaptorTransfer.parseQr(code.rawValue ?? '');
        if (data == null) continue;
        final result = await RaptorTransfer.accept(data);
        if (!mounted || result == null) return;
        // A camera/tab change doesn't discard native decoding progress.
        setState(() {
          _received = result['received'] as int? ?? _received;
          _needed = result['needed'] as int? ?? _needed;
          _progress = (result['progress'] as num?)?.toDouble() ?? _progress;
          if (result['status'] == 'other') {
            _status = '已忽略另一份文件；接收新文件请点重新识别';
          } else if (result['status'] == 'accepted') {
            _status = null;
          }
          if (result['status'] == 'complete') {
            _complete = true;
            _receiving = false;
            _file = result;
          }
        });
        if (_complete || generation != _generation) break;
      }
    } catch (error) {
      if (mounted) {
        setState(() => _receiving = false);
        _message(error);
      }
    } finally {
      _decoding = false;
    }
  }

  Future<void> _reset() async {
    if (_working) return;
    setState(() {
      _generation++;
      _working = true;
      _receiving = false;
    });
    try {
      await RaptorTransfer.resetReceiver();
      if (mounted) {
        setState(() {
          _complete = false;
          _saved = false;
          _file = null;
          _received = 0;
          _needed = 0;
          _progress = 0;
          _status = null;
          _receiving = true;
        });
      }
    } catch (error) {
      _message(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _save() async {
    setState(() => _working = true);
    try {
      final saved = await RaptorTransfer.save();
      if (mounted && saved) setState(() => _saved = true);
    } catch (error) {
      _message(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _size(Object? value) {
    final bytes = (value as num?)?.toInt() ?? 0;
    return bytes < 1024
        ? '$bytes B'
        : bytes < 1024 * 1024
            ? '${(bytes / 1024).toStringAsFixed(1)} KB'
            : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_working,
        child: Scaffold(
          appBar: AppBar(
            title: TextButton(
              onPressed: _working ? null : () => Navigator.pop(context),
              child: Text(_tab == 0 ? '流水码识别' : '流水码创建',
                  style: const TextStyle(fontSize: 20)),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                        value: 0,
                        label: Text('识别'),
                        icon: Icon(Icons.qr_code_scanner)),
                    ButtonSegment(
                        value: 1, label: Text('创建'), icon: Icon(Icons.qr_code)),
                  ],
                  selected: {_tab},
                  onSelectionChanged: _working || !_ready
                      ? null
                      : (value) => _switchTab(value.first),
                ),
              ),
            ),
          ),
          body: _platformError != null
              ? Center(child: Text(_platformError!))
              : !_ready
                  ? const Center(child: CircularProgressIndicator())
                  : SafeArea(
                      top: false,
                      child: _tab == 0 ? _receiverView() : _senderView()),
        ),
      );

  Widget _receiverView() => Column(children: [
        Expanded(
            child: _complete
                ? SingleChildScrollView(
                    child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(children: [
                      const Icon(Icons.check_circle,
                          color: Colors.green, size: 64),
                      const SizedBox(height: 16),
                      const Text('文件已恢复，SHA-256 校验通过'),
                      const SizedBox(height: 12),
                      Text(_file?['name'] as String? ?? '',
                          textAlign: TextAlign.center),
                      Text(_size(_file?['size'])),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                          onPressed: _working ? null : _save,
                          icon: const Icon(Icons.save_alt),
                          label: Text(_saved ? '再次保存' : '保存到手机')),
                      if (_saved) const Text('文件已保存'),
                      if (_working)
                        const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator()),
                    ]),
                  ))
                : _receiving
                    ? RaptorCamera(onCapture: _capture)
                    : const Center(child: Text('接收已暂停，进度已保留'))),
        Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_needed == 0
                  ? '对准另一部手机创建的 RaptorQ 流水码'
                  : '已接收 $_received 个有效符号 · 基础需要 $_needed 个'),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(_complete ? '接收完成' : _status ?? '漏帧无需重传，保持扫描直到文件恢复',
                  textAlign: TextAlign.center),
              Wrap(alignment: WrapAlignment.center, spacing: 12, children: [
                if (!_complete)
                  TextButton.icon(
                    onPressed: _working
                        ? null
                        : () => setState(() => _receiving = !_receiving),
                    icon: Icon(_receiving ? Icons.pause : Icons.play_arrow),
                    label: Text(_receiving ? '暂停接收' : '继续接收'),
                  ),
                TextButton.icon(
                    onPressed: _working ? null : _reset,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新识别')),
              ]),
            ])),
      ]);

  Widget _senderView() => LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  if (_sender == null) ...[
                    const Text('选择手机文件或输入文本，让另一部手机扫描。最大支持 8 MB。'),
                    const SizedBox(height: 16),
                  ],
                  OutlinedButton.icon(
                      onPressed: _working ? null : () => _prepare(),
                      icon: const Icon(Icons.attach_file),
                      label: const Text('选择文件')),
                  if (_sender == null) ...[
                    const SizedBox(height: 16),
                    TextField(
                        controller: _text,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                            labelText: '也可以输入文本',
                            border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    FilledButton(
                        onPressed: _working ? null : () => _prepare(text: true),
                        child: const Text('创建文本流水码')),
                  ],
                  if (_working)
                    const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator()),
                  if (_sender != null) ...[
                    Text(_sender!['name'] as String,
                        textAlign: TextAlign.center),
                    Text(_size(_sender!['size'])),
                    const SizedBox(height: 12),
                    if (_qr != null)
                      QrImageView(
                        data: _qr!,
                        version: QrVersions.auto,
                        size: math.min(constraints.maxWidth - 32, 360),
                        padding: const EdgeInsets.all(24),
                        backgroundColor: Colors.white,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                      ),
                    const SizedBox(height: 12),
                    Text('已生成 $_sent 帧 · 每帧 ${_qr?.length ?? 0} 字符'),
                    Text('帧率：${_fps.round()} 帧/秒'),
                    Slider(
                        value: _fps,
                        min: 1,
                        max: 10,
                        divisions: 9,
                        label: '${_fps.round()} 帧/秒',
                        onChanged: _working
                            ? null
                            : (value) {
                                final playing = _playing;
                                setState(() {
                                  _pause();
                                  _fps = value;
                                });
                                if (playing) _play();
                              }),
                    FilledButton.icon(
                        onPressed: _working
                            ? null
                            : () {
                                if (_playing) {
                                  setState(_pause);
                                } else {
                                  _play();
                                }
                              },
                        icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                        label: Text(_playing ? '暂停播放' : '开始播放')),
                    const SizedBox(height: 12),
                    const Text('接收端显示完成后即可停止播放。识别困难时降低帧率、调整距离。',
                        textAlign: TextAlign.center),
                    TextButton(
                        onPressed: _working
                            ? null
                            : () async {
                                setState(() {
                                  _pause();
                                  _sender = null;
                                  _qr = null;
                                });
                                try {
                                  await RaptorTransfer.clearSender();
                                } catch (error) {
                                  _message(error);
                                }
                              },
                        child: const Text('创建另一份流水码')),
                  ],
                ])),
          ));

  @override
  void dispose() {
    _pause();
    WidgetsBinding.instance.removeObserver(this);
    _text.dispose();
    // Native work is serialized; cleanup follows any already submitted packet.
    RaptorTransfer.keepAwake(false).catchError((_) {});
    RaptorTransfer.clearSender().catchError((_) {});
    RaptorTransfer.resetReceiver().catchError((_) {});
    super.dispose();
  }
}
