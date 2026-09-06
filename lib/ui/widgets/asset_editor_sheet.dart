import 'package:flutter/material.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/asset_kind.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

Future<void> showAssetEditor(BuildContext context, {Asset? edit}) async {
  final result = await showModalBottomSheet<_AssetEditorResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _AssetEditorSheet(edit: edit),
    ),
  );
  if (result == null || !context.mounted) return;

  final state = context.read<AppState>();
  final svc = state.tradeService;
  try {
    if (edit == null) {
      await svc.createAsset(
        name: result.name,
        symbol: result.symbol,
        quantity: result.quantity,
        avgBuyPrice: result.buyPrice,
        currentPrice: result.currentPrice,
        notes: result.notes,
      );
    } else {
      edit
        ..name = result.name
        ..symbol = result.symbol
        ..currentPrice = result.currentPrice
        ..notes = result.notes;
      await svc.assets.update(edit);
    }
    await state.refresh();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _AssetEditorResult {
  const _AssetEditorResult({
    required this.name,
    required this.symbol,
    required this.quantity,
    required this.buyPrice,
    required this.currentPrice,
    required this.notes,
  });

  final String name;
  final String symbol;
  final double quantity;
  final double buyPrice;
  final double currentPrice;
  final String notes;
}

class _AssetEditorSheet extends StatefulWidget {
  const _AssetEditorSheet({this.edit});

  final Asset? edit;

  @override
  State<_AssetEditorSheet> createState() => _AssetEditorSheetState();
}

class _AssetEditorSheetState extends State<_AssetEditorSheet> {
  late AssetKind _kind;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _symbolCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _buyCtrl;
  late final TextEditingController _currentCtrl;
  late final TextEditingController _notesCtrl;
  String? _error;

  bool get _isEdit => widget.edit != null;

  @override
  void initState() {
    super.initState();
    final edit = widget.edit;
    _kind = edit == null
        ? AssetKind.other
        : detectAssetKind(
            name: edit.name,
            symbol: edit.symbol,
            notes: edit.notes,
          );
    _nameCtrl = TextEditingController(text: edit?.name ?? '');
    _symbolCtrl = TextEditingController(text: edit?.symbol ?? '');
    _qtyCtrl = TextEditingController(
      text: edit == null
          ? _formatQty(_kind.defaultQuantity)
          : _formatQty(edit.quantity),
    );
    _buyCtrl = TextEditingController(
      text: edit == null || edit.avgBuyPrice <= 0 ? '' : '${edit.avgBuyPrice}',
    );
    _currentCtrl = TextEditingController(
      text: edit == null || edit.currentPrice <= 0
          ? ''
          : '${edit.currentPrice}',
    );
    _notesCtrl = TextEditingController(
      text: edit == null ? '' : stripKindMarker(edit.notes),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _symbolCtrl.dispose();
    _qtyCtrl.dispose();
    _buyCtrl.dispose();
    _currentCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String _formatQty(double v) {
    if ((v - v.roundToDouble()).abs() < 1e-9) return '${v.round()}';
    return '$v';
  }

  void _onKindChanged(AssetKind kind) {
    setState(() {
      _kind = kind;
      _error = null;
      if (_isEdit) return;
      if (_symbolCtrl.text.trim().isEmpty ||
          AssetKind.values.any((k) => k.defaultSymbol == _symbolCtrl.text.trim())) {
        _symbolCtrl.text = kind.defaultSymbol;
      }
      if (_qtyCtrl.text.trim().isEmpty ||
          _qtyCtrl.text.trim() == '0' ||
          _qtyCtrl.text.trim() == '1') {
        _qtyCtrl.text = _formatQty(kind.defaultQuantity);
      }
    });
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'نام دارایی الزامی است.');
      return;
    }
    var symbol = _symbolCtrl.text.trim();
    if (symbol.isEmpty && _kind.defaultSymbol.isNotEmpty) {
      symbol = _kind.defaultSymbol;
    }
    final buy = double.tryParse(_buyCtrl.text.replaceAll(',', '')) ?? 0;
    final current =
        double.tryParse(_currentCtrl.text.replaceAll(',', '')) ?? buy;
    double qty;
    if (_isEdit) {
      qty = widget.edit!.quantity;
    } else {
      qty = double.tryParse(_qtyCtrl.text.replaceAll(',', '')) ?? 0;
      if (_kind.isUnitAsset && qty <= 0) qty = 1;
    }
    if (!_isEdit && qty > 0 && buy <= 0) {
      setState(() => _error = 'برای موجودی اولیه، ${_kind.buyPriceLabel} را وارد کنید.');
      return;
    }
    if (current < 0 || buy < 0 || qty < 0) {
      setState(() => _error = 'مقادیر منفی مجاز نیست.');
      return;
    }

    Navigator.pop(
      context,
      _AssetEditorResult(
        name: name,
        symbol: symbol,
        quantity: qty,
        buyPrice: buy,
        currentPrice: current > 0 ? current : buy,
        notes: notesWithKind(_notesCtrl.text, _kind),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _isEdit ? 'ویرایش دارایی' : 'دارایی جدید',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppTheme.title,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'نوع دارایی',
              textAlign: TextAlign.right,
              style: TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                for (final kind in AssetKind.values)
                  _KindChip(
                    kind: kind,
                    selected: _kind == kind,
                    onTap: () => _onKindChanged(kind),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _kind.helpText,
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameCtrl,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                labelText: 'نام',
                hintText: _kind.nameHint,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _symbolCtrl,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                labelText: 'نماد',
                hintText: _kind.symbolHint,
              ),
            ),
            if (!_isEdit) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _qtyCtrl,
                textAlign: TextAlign.right,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: _kind.quantityLabel),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _buyCtrl,
                textAlign: TextAlign.right,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: _kind.buyPriceLabel),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'برای تغییر مقدار از تب «باز» استفاده کنید.',
                textAlign: TextAlign.right,
                style: const TextStyle(color: AppTheme.muted, fontSize: 11),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _currentCtrl,
              textAlign: TextAlign.right,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: _kind.currentPriceLabel),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notesCtrl,
              textAlign: TextAlign.right,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'توضیح (اختیاری)',
                hintText: 'آدرس، پلاک، مدل، …',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.right,
                style: const TextStyle(color: AppTheme.negative, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('انصراف'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _submit,
                    child: const Text('ذخیره'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final AssetKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? kind.color.withValues(alpha: 0.2) : AppTheme.bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? kind.color : AppTheme.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(kind.icon, size: 16, color: kind.color),
              const SizedBox(width: 6),
              Text(
                kind.label,
                style: TextStyle(
                  color: selected ? AppTheme.title : AppTheme.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
