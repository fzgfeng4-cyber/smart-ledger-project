import 'package:flutter/material.dart';

import '../../domain/ocr/ocr_contract.dart';
import 'ocr_capture.dart';

class OcrPage extends StatefulWidget {
  const OcrPage({
    required this.capture,
    required this.today,
    required this.onContinueToConfirmation,
    super.key,
  });

  final OcrCaptureService capture;
  final DateTime today;
  final Future<bool> Function(String input) onContinueToConfirmation;

  @override
  State<OcrPage> createState() => _OcrPageState();
}

class _OcrPageState extends State<OcrPage> {
  final _recognizedTextController = TextEditingController();
  OcrResult? _result;
  String _recognizedText = '';
  String? _errorMessage;
  String? _statusMessage;
  bool _isRecognizing = false;
  bool _isOpeningConfirmation = false;
  bool _confirmedResult = false;

  bool get _hasUnsavedDraft {
    return _recognizedText.trim().isNotEmpty || (_result?.hasText ?? false);
  }

  @override
  void dispose() {
    _recognizedTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final canContinue =
        _recognizedText.trim().isNotEmpty &&
        _confirmedResult &&
        !_isRecognizing &&
        !_isOpeningConfirmation;

    return PopScope<Object?>(
      canPop: !_isRecognizing && !_isOpeningConfirmation && !_hasUnsavedDraft,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: Scaffold(
        key: const Key('ocr-page'),
        appBar: AppBar(
          leading: IconButton(
            key: const Key('ocr-back'),
            tooltip: '返回',
            onPressed: _isOpeningConfirmation ? null : _handleBack,
            icon: const Icon(Icons.arrow_back),
          ),
          title: const Text('拍照识别'),
        ),
        body: SafeArea(
          child: CustomScrollView(
            key: const Key('ocr-scroll'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 180),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Text(
                      '选择账单图片',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const Key('ocr-camera-button'),
                            onPressed: _isRecognizing
                                ? null
                                : () => _recognize(OcrImageSourceType.camera),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('拍照识别'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const Key('ocr-gallery-button'),
                            onPressed: _isRecognizing
                                ? null
                                : () => _recognize(OcrImageSourceType.gallery),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('从相册选图'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '图片仅用于本机 OCR 识别，默认识别完成后不保留原图。',
                      key: const Key('ocr-privacy-note'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_isRecognizing) ...[
                      const SizedBox(height: 20),
                      const _OcrLoadingState(),
                    ],
                    if (!_isRecognizing && result == null) ...[
                      const SizedBox(height: 28),
                      const _OcrEmptyState(),
                    ],
                    if (!_isRecognizing && _errorMessage != null) ...[
                      const SizedBox(height: 20),
                      _OcrErrorState(
                        message: _errorMessage!,
                        onRetry: () => _recognize(
                          result?.source.type == OcrImageSourceType.camera
                              ? OcrImageSourceType.camera
                              : OcrImageSourceType.gallery,
                        ),
                        onOpenSettings:
                            result?.status == OcrStatus.permissionDenied
                            ? widget.capture.openAppSettings
                            : null,
                      ),
                    ],
                    if (!_isRecognizing && result != null) ...[
                      const SizedBox(height: 20),
                      _OcrResultPanel(
                        result: result,
                        controller: _recognizedTextController,
                        onChanged: _updateRecognizedText,
                      ),
                      if (_recognizedText.trim().isNotEmpty) ...[
                        const SizedBox(height: 14),
                        CheckboxListTile(
                          key: const Key('ocr-confirm-result'),
                          contentPadding: EdgeInsets.zero,
                          value: _confirmedResult,
                          onChanged: _isOpeningConfirmation
                              ? null
                              : (value) {
                                  setState(() {
                                    _confirmedResult = value ?? false;
                                  });
                                },
                          title: const Text('我已核对识别文字'),
                          subtitle: const Text('确认后进入账目详情，保存前仍可修改。'),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ],
                    ],
                    if (_statusMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _statusMessage!,
                        key: const Key('ocr-status-message'),
                      ),
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton.icon(
              key: const Key('ocr-confirm-button'),
              onPressed: canContinue ? _continueToConfirmation : null,
              icon: _isOpeningConfirmation
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward),
              label: Text(_isOpeningConfirmation ? '确认中...' : '进入账目确认'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _recognize(OcrImageSourceType source) async {
    if (_isRecognizing || _isOpeningConfirmation) {
      return;
    }

    setState(() {
      _isRecognizing = true;
      _result = null;
      _recognizedText = '';
      _recognizedTextController.clear();
      _errorMessage = null;
      _statusMessage = null;
      _confirmedResult = false;
    });

    try {
      final result = await widget.capture.pickAndRecognize(
        source: source,
        requestId: 'ocr-${DateTime.now().microsecondsSinceEpoch}',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _result = result;
        _recognizedText = result.recognizedText;
        _recognizedTextController
          ..text = result.recognizedText
          ..selection = TextSelection.collapsed(
            offset: result.recognizedText.length,
          );
        _errorMessage = result.isFailure
            ? result.failureReason?.displayMessage ?? '识别失败，请重试。'
            : null;
        _statusMessage = result.status == OcrStatus.cancelled
            ? '已取消识别，账本未修改。'
            : result.status == OcrStatus.emptyText
            ? '没有识别到可用文字，请重试或手动补录。'
            : result.status == OcrStatus.lowConfidence
            ? '识别置信度较低，请先核对文字。'
            : null;
      });
    } on Object catch (_) {
      if (mounted) {
        setState(() {
          _result = null;
          _errorMessage = '识别失败，请重试。';
          _statusMessage = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRecognizing = false;
        });
      }
    }
  }

  void _updateRecognizedText(String value) {
    setState(() {
      _recognizedText = value;
      _confirmedResult = false;
      _statusMessage = null;
    });
  }

  Future<void> _continueToConfirmation() async {
    final input = _recognizedText.trim();
    if (input.isEmpty || !_confirmedResult || _isOpeningConfirmation) {
      return;
    }

    setState(() {
      _isOpeningConfirmation = true;
      _errorMessage = null;
      _statusMessage = null;
    });

    try {
      final completed = await widget.onContinueToConfirmation(input);
      if (!mounted) {
        return;
      }
      setState(() {
        _isOpeningConfirmation = false;
        if (completed) {
          _result = null;
          _recognizedText = '';
          _recognizedTextController.clear();
          _confirmedResult = false;
          _statusMessage = '账目已保存。';
        } else {
          _statusMessage = '已取消确认，账本未修改。';
        }
      });
    } on Object catch (_) {
      if (mounted) {
        setState(() {
          _isOpeningConfirmation = false;
          _errorMessage = '无法进入账目确认，请重试。';
        });
      }
    }
  }

  Future<void> _handleBack() async {
    if (_isRecognizing) {
      await widget.capture.cancel();
      if (mounted) {
        setState(() {
          _isRecognizing = false;
          _statusMessage = '已取消识别，账本未修改。';
        });
      }
      return;
    }
    if (!_hasUnsavedDraft) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('ocr-discard-dialog'),
        title: const Text('放弃识别结果？'),
        content: const Text('识别结果还没有保存。'),
        actions: [
          TextButton(
            key: const Key('ocr-continue-editing'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            key: const Key('ocr-discard-result'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('放弃结果'),
          ),
        ],
      ),
    );

    if (shouldDiscard == true && mounted) {
      setState(() {
        _result = null;
        _recognizedText = '';
        _recognizedTextController.clear();
        _confirmedResult = false;
      });
      Navigator.of(context).pop();
    }
  }
}

class _OcrLoadingState extends StatelessWidget {
  const _OcrLoadingState();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('ocr-loading-state'),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(20),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('正在识别图片...'),
          ],
        ),
      ),
    );
  }
}

class _OcrEmptyState extends StatelessWidget {
  const _OcrEmptyState();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('ocr-empty-state'),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.document_scanner_outlined, size: 42),
            SizedBox(height: 10),
            Text('选择一张清晰的账单图片开始识别。'),
          ],
        ),
      ),
    );
  }
}

class _OcrErrorState extends StatelessWidget {
  const _OcrErrorState({
    required this.message,
    required this.onRetry,
    this.onOpenSettings,
  });

  final String message;
  final VoidCallback onRetry;
  final Future<bool> Function()? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('ocr-error-state'),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 10),
            TextButton.icon(
              key: const Key('ocr-retry-button'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试识别'),
            ),
            if (onOpenSettings != null)
              TextButton.icon(
                key: const Key('ocr-open-settings'),
                onPressed: () async {
                  await onOpenSettings!();
                },
                icon: const Icon(Icons.settings_outlined),
                label: const Text('打开系统设置'),
              ),
          ],
        ),
      ),
    );
  }
}

class _OcrResultPanel extends StatelessWidget {
  const _OcrResultPanel({
    required this.result,
    required this.controller,
    required this.onChanged,
  });

  final OcrResult result;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final confidence = result.confidence?.value;
    return Column(
      key: const Key('ocr-result-panel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '识别结果',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('ocr-recognized-text'),
          controller: controller,
          onChanged: onChanged,
          minLines: 4,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: '识别文字',
            hintText: '可直接修改识别结果',
          ),
        ),
        if (confidence != null) ...[
          const SizedBox(height: 8),
          Text('识别置信度：${(confidence * 100).toStringAsFixed(0)}%'),
        ],
        for (final issue in result.candidateIssues) ...[
          const SizedBox(height: 6),
          Text(
            issue.message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}
