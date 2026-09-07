import 'package:flutter/material.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/asset_kind.dart';
import 'package:invest/domain/models/asset_meta.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/buy_usd_suggest.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/app_date_picker.dart';
import 'package:provider/provider.dart';

Future<void> showAssetEditor(BuildContext context, {Asset? edit}) async {
  final state = context.read<AppState>();
  final openLots = edit == null
      ? const <Trade>[]
      : state.openTrades
          .where((t) => t.assetId == edit.id && t.quantity > 1e-9)
          .toList();
  final primaryLot = openLots.length == 1 ? openLots.first : null;

  final result = await showModalBottomSheet<_AssetEditorResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _AssetEditorSheet(
        edit: edit,
        openLotCount: openLots.length,
        primaryLot: primaryLot,
      ),
    ),
  );
  if (result == null || !context.mounted) return;

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
        buyDate: result.buyDate,
      );
    } else {
      edit
        ..name = result.name
        ..symbol = result.symbol
        ..currentPrice = result.currentPrice
        ..notes = result.notes;
      if (result.updateBuyPrice) {
        edit.avgBuyPrice = result.buyPrice;
      }
      if (result.updateQuantity) {
        edit.quantity = result.quantity;
      }
      await svc.assets.update(edit);

      // Keep the single open lot in sync so cards/metrics see the edit.
      if (primaryLot != null &&
          (result.updateBuyPrice ||
              result.updateQuantity ||
              result.updateBuyPriceUsd ||
              result.updateBuyDate)) {
        final usd = parseAssetNotes(result.notes).meta.buyPriceUsd;
        await svc.updateOpenTrade(
          tradeId: primaryLot.id!,
          quantity:
              result.updateQuantity ? result.quantity : primaryLot.quantity,
          buyPrice:
              result.updateBuyPrice ? result.buyPrice : primaryLot.buyPrice,
          buyPriceUsd:
              result.updateBuyPriceUsd ? usd : primaryLot.buyPriceUsd,
          buyFee: primaryLot.buyFee,
          buyDate: result.updateBuyDate ? result.buyDate : primaryLot.buyDate,
          buyNote: primaryLot.buyNoteDisplay,
        );
      }
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
    required this.buyDate,
    this.updateBuyPrice = false,
    this.updateQuantity = false,
    this.updateBuyPriceUsd = false,
    this.updateBuyDate = false,
  });

  final String name;
  final String symbol;
  final double quantity;
  final double buyPrice;
  final double currentPrice;
  final String notes;
  final String buyDate;
  final bool updateBuyPrice;
  final bool updateQuantity;
  final bool updateBuyPriceUsd;
  final bool updateBuyDate;
}

class _AssetEditorSheet extends StatefulWidget {
  const _AssetEditorSheet({
    this.edit,
    this.openLotCount = 0,
    this.primaryLot,
  });

  final Asset? edit;
  final int openLotCount;
  final Trade? primaryLot;

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

  // Property
  late final TextEditingController _addressCtrl;
  late final TextEditingController _areaCtrl;
  late final TextEditingController _deedCtrl;
  late String _purchaseDate;
  String? _usage; // residential | commercial

  // Vehicle
  late final TextEditingController _brandCtrl;
  late final TextEditingController _yearCtrl;
  late final TextEditingController _plateCtrl;
  late final TextEditingController _mileageCtrl;
  late final TextEditingController _colorCtrl;

  // Gold
  late final TextEditingController _purityCtrl;

  // Optional USD buy unit price (all kinds)
  late final TextEditingController _buyUsdCtrl;

  /// Buy date for non-property/vehicle kinds (and seed for purchase date).
  late String _buyDate;

  bool _buyUsdManual = false;
  int _usdSuggestGen = 0;
  bool _usdSuggesting = false;

  String? _error;

  bool get _isEdit => widget.edit != null;

  /// Multiple open lots: edit buy/qty via «باز» so we don't overwrite one lot.
  bool get _lotsBlockBuyEdit => _isEdit && widget.openLotCount > 1;

  /// Buy price field visible on create, or on edit for non-crypto kinds
  /// when at most one open lot can stay in sync.
  bool get _showBuyField =>
      !_lotsBlockBuyEdit &&
      (!_isEdit ||
          _kind == AssetKind.property ||
          _kind == AssetKind.vehicle ||
          _kind == AssetKind.gold ||
          _kind == AssetKind.cash ||
          _kind == AssetKind.other);

  /// Qty field: create always; edit only for unit-like kinds that are not lot-traded.
  bool get _showQtyField =>
      !_lotsBlockBuyEdit &&
      (!_isEdit ||
          _kind == AssetKind.property ||
          _kind == AssetKind.vehicle);

  @override
  void initState() {
    super.initState();
    final edit = widget.edit;
    final parts = edit == null
        ? const AssetNotesParts(
            kind: null,
            meta: AssetMeta.empty,
            freeNotes: '',
          )
        : parseAssetNotes(edit.notes);
    final meta = parts.meta;
    _kind = edit == null
        ? AssetKind.other
        : (parts.kind ??
            detectAssetKind(
              name: edit.name,
              symbol: edit.symbol,
              notes: edit.notes,
            ));
    final lot = widget.primaryLot;
    final seedQty = lot?.quantity ?? edit?.quantity;
    final seedBuy = lot?.buyPrice ?? edit?.avgBuyPrice;
    final lotUsd = lot?.buyPriceUsd;
    final seedUsd =
        (lotUsd != null && lotUsd > 0) ? lotUsd : meta.buyPriceUsd;

    _nameCtrl = TextEditingController(text: edit?.name ?? '');
    _symbolCtrl = TextEditingController(text: edit?.symbol ?? '');
    _qtyCtrl = TextEditingController(
      text: edit == null
          ? _formatQty(_kind.defaultQuantity)
          : _formatQty(seedQty ?? edit.quantity),
    );
    _buyCtrl = TextEditingController(
      text: edit == null || (seedBuy ?? 0) <= 0 ? '' : '$seedBuy',
    );
    _currentCtrl = TextEditingController(
      text: edit == null || edit.currentPrice <= 0
          ? ''
          : '${edit.currentPrice}',
    );
    _notesCtrl = TextEditingController(text: parts.freeNotes);

    _addressCtrl = TextEditingController(text: meta.address ?? '');
    _areaCtrl = TextEditingController(
      text: meta.areaM2 == null ? '' : _formatQty(meta.areaM2!),
    );
    _deedCtrl = TextEditingController(text: meta.deedNotes ?? '');
    final rawPurchase = meta.purchaseDate ?? '';
    _buyDate = tryNormalizeToIso(lot?.buyDate) ??
        tryNormalizeToIso(rawPurchase) ??
        todayIso();
    _purchaseDate = tryNormalizeToIso(rawPurchase) ??
        (rawPurchase.trim().isEmpty ? _buyDate : rawPurchase);
    _usage = meta.usage;

    _brandCtrl = TextEditingController(text: meta.brandModel ?? '');
    _yearCtrl = TextEditingController(text: meta.year?.toString() ?? '');
    _plateCtrl = TextEditingController(text: meta.plate ?? '');
    _mileageCtrl = TextEditingController(
      text: meta.mileageKm == null ? '' : _formatQty(meta.mileageKm!),
    );
    _colorCtrl = TextEditingController(text: meta.color ?? '');
    _purityCtrl = TextEditingController(text: meta.purity ?? '');
    _buyUsdCtrl = TextEditingController(
      text: seedUsd == null || seedUsd <= 0 ? '' : _formatQty(seedUsd),
    );
    _buyUsdManual = seedUsd != null && seedUsd > 0;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _symbolCtrl.dispose();
    _qtyCtrl.dispose();
    _buyCtrl.dispose();
    _buyUsdCtrl.dispose();
    _currentCtrl.dispose();
    _notesCtrl.dispose();
    _addressCtrl.dispose();
    _areaCtrl.dispose();
    _deedCtrl.dispose();
    _brandCtrl.dispose();
    _yearCtrl.dispose();
    _plateCtrl.dispose();
    _mileageCtrl.dispose();
    _colorCtrl.dispose();
    _purityCtrl.dispose();
    super.dispose();
  }

  String _formatQty(double v) {
    if ((v - v.roundToDouble()).abs() < 1e-9) return '${v.round()}';
    return '$v';
  }

  bool get _usesPurchaseDate =>
      _kind == AssetKind.property || _kind == AssetKind.vehicle;

  String get _resolvedBuyDate {
    if (_usesPurchaseDate) {
      final n = tryNormalizeToIso(_purchaseDate);
      if (n != null) return n;
      final t = _purchaseDate.trim();
      if (t.length >= 10) return t.substring(0, 10);
    }
    return _buyDate;
  }

  Future<void> _maybeSuggestBuyUsd() async {
    if (_buyUsdManual || !_showBuyField) return;
    final buy = double.tryParse(_buyCtrl.text.replaceAll(',', ''));
    if (buy == null || buy <= 0) return;
    final date = _resolvedBuyDate;
    if (date.isEmpty) return;

    final gen = ++_usdSuggestGen;
    final state = context.read<AppState>();
    final fallback = state.liveUsdt ?? state.settings.usdtTmnRate;
    if (mounted) setState(() => _usdSuggesting = true);
    try {
      final usd = await suggestBuyPriceUsd(
        buyPriceToman: buy,
        buyDateIso: date,
        liveUsdtFallback: fallback,
      );
      if (!mounted || gen != _usdSuggestGen || _buyUsdManual) return;
      if (usd != null && usd > 0) {
        _buyUsdCtrl.text = formatBuyUsdField(usd);
      }
    } finally {
      if (mounted && gen == _usdSuggestGen) {
        setState(() => _usdSuggesting = false);
      }
    }
  }

  void _onBuyTomanChanged(String _) {
    _buyUsdManual = false;
    _maybeSuggestBuyUsd();
  }

  void _onBuyUsdChanged(String _) {
    _buyUsdManual = true;
  }

  void _onBuyDateChanged(String iso) {
    setState(() {
      if (_usesPurchaseDate) {
        _purchaseDate = iso;
      } else {
        _buyDate = iso;
      }
    });
    _buyUsdManual = false;
    _maybeSuggestBuyUsd();
  }

  void _onKindChanged(AssetKind kind) {
    setState(() {
      _kind = kind;
      _error = null;
      if (_isEdit) return;
      if (_symbolCtrl.text.trim().isEmpty ||
          AssetKind.values
              .any((k) => k.defaultSymbol == _symbolCtrl.text.trim())) {
        _symbolCtrl.text = kind.defaultSymbol;
      }
      if (_qtyCtrl.text.trim().isEmpty ||
          _qtyCtrl.text.trim() == '0' ||
          _qtyCtrl.text.trim() == '1') {
        _qtyCtrl.text = _formatQty(kind.defaultQuantity);
      }
    });
  }

  AssetMeta _collectMeta() {
    double? parseD(String s) =>
        double.tryParse(s.trim().replaceAll(',', ''));
    int? parseI(String s) => int.tryParse(s.trim().replaceAll(',', ''));
    final usdRaw = parseD(_buyUsdCtrl.text);
    final usd = (usdRaw != null && usdRaw > 0) ? usdRaw : null;

    switch (_kind) {
      case AssetKind.property:
        return AssetMeta(
          address: _addressCtrl.text,
          areaM2: parseD(_areaCtrl.text),
          usage: _usage,
          deedNotes: _deedCtrl.text,
          purchaseDate: _purchaseDate,
          buyPriceUsd: usd,
        );
      case AssetKind.vehicle:
        return AssetMeta(
          brandModel: _brandCtrl.text,
          year: parseI(_yearCtrl.text),
          plate: _plateCtrl.text,
          mileageKm: parseD(_mileageCtrl.text),
          color: _colorCtrl.text,
          purchaseDate: _purchaseDate,
          buyPriceUsd: usd,
        );
      case AssetKind.gold:
        return AssetMeta(purity: _purityCtrl.text, buyPriceUsd: usd);
      case AssetKind.cash:
      case AssetKind.crypto:
      case AssetKind.other:
        return usd == null ? AssetMeta.empty : AssetMeta(buyPriceUsd: usd);
    }
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
    if (_isEdit && !_showQtyField) {
      qty = widget.edit!.quantity;
    } else {
      qty = double.tryParse(_qtyCtrl.text.replaceAll(',', '')) ?? 0;
      if (_kind.isUnitAsset && qty <= 0) qty = 1;
    }
    if (!_isEdit && qty > 0 && buy <= 0) {
      setState(
        () => _error =
            'برای موجودی اولیه، ${_kind.buyPriceLabel} را وارد کنید.',
      );
      return;
    }
    if (current < 0 || buy < 0 || qty < 0) {
      setState(() => _error = 'مقادیر منفی مجاز نیست.');
      return;
    }

    final notes = encodeAssetNotes(
      kind: _kind,
      meta: _collectMeta(),
      freeNotes: _notesCtrl.text,
    );

    Navigator.pop(
      context,
      _AssetEditorResult(
        name: name,
        symbol: symbol,
        quantity: qty,
        buyPrice: buy,
        currentPrice: current > 0 ? current : buy,
        notes: notes,
        buyDate: _resolvedBuyDate,
        updateBuyPrice: _isEdit && _showBuyField && buy > 0,
        updateQuantity: _isEdit && _showQtyField && qty > 0,
        updateBuyPriceUsd: _isEdit && _showBuyField,
        updateBuyDate: _isEdit && _showBuyField,
      ),
    );
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
      );

  Widget _field(
    TextEditingController c, {
    required String label,
    String? hint,
    TextInputType? keyboardType,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextField(
          controller: c,
          textAlign: TextAlign.right,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: _dec(label, hint: hint),
          onChanged: onChanged,
        ),
      );

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
            _field(
              _nameCtrl,
              label: _kind == AssetKind.vehicle ? 'نام / مدل' : 'نام',
              hint: _kind.nameHint,
            ),
            if (_kind == AssetKind.crypto ||
                _kind == AssetKind.cash ||
                _kind == AssetKind.other ||
                _kind == AssetKind.gold)
              _field(
                _symbolCtrl,
                label: _kind == AssetKind.cash ? 'ارز / نماد' : 'نماد',
                hint: _kind.symbolHint,
              ),
            ..._kindSpecificFields(context),
            if (_showQtyField)
              _field(
                _qtyCtrl,
                label: _kind.quantityLabel,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            if (_showBuyField) ...[
              if (!_usesPurchaseDate) _buyDateField(context),
              _field(
                _buyCtrl,
                label: _kind.buyPriceLabel,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: _onBuyTomanChanged,
              ),
              _field(
                _buyUsdCtrl,
                label: 'بهای دلاری خرید',
                hint: _usdSuggesting
                    ? 'در حال محاسبه از نرخ همان تاریخ…'
                    : 'خودکار از نرخ USDT تاریخ خرید — قابل ویرایش',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: _onBuyUsdChanged,
              ),
            ] else if (_isEdit) ...[
              const SizedBox(height: 8),
              Text(
                _lotsBlockBuyEdit
                    ? 'چند لات باز دارید؛ برای تغییر مقدار یا بهای خرید از تب «باز» استفاده کنید.'
                    : 'برای تغییر مقدار از تب «باز» استفاده کنید.',
                textAlign: TextAlign.right,
                style: const TextStyle(color: AppTheme.muted, fontSize: 11),
              ),
            ],
            _field(
              _currentCtrl,
              label: _kind.currentPriceLabel,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            _field(
              _notesCtrl,
              label: 'توضیح (اختیاری)',
              hint: 'یادداشت آزاد',
              maxLines: 2,
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

  List<Widget> _kindSpecificFields(BuildContext context) {
    switch (_kind) {
      case AssetKind.property:
        return [
          _field(_addressCtrl, label: 'آدرس', hint: 'مثل ونک، خیابان …'),
          _field(
            _areaCtrl,
            label: 'متراژ (م²)',
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 10),
          const Text(
            'کاربری',
            textAlign: TextAlign.right,
            style: TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.end,
            children: [
              _UsageChip(
                label: 'مسکونی',
                selected: _usage == 'residential',
                onTap: () => setState(() => _usage = 'residential'),
              ),
              _UsageChip(
                label: 'تجاری',
                selected: _usage == 'commercial',
                onTap: () => setState(() => _usage = 'commercial'),
              ),
            ],
          ),
          _field(
            _deedCtrl,
            label: 'سند / پلاک ثبتی',
            hint: 'شماره سند یا پلاک',
          ),
          _purchaseDateField(context),
        ];
      case AssetKind.vehicle:
        return [
          _field(_brandCtrl, label: 'برند / مدل', hint: 'مثل پژو ۲۰۷'),
          _field(
            _yearCtrl,
            label: 'سال ساخت',
            hint: 'مثل ۱۳۹۹',
            keyboardType: TextInputType.number,
          ),
          _field(_plateCtrl, label: 'پلاک', hint: 'مثل ۱۲ب۳۴۵ ایران ۱۱'),
          _field(
            _mileageCtrl,
            label: 'کارکرد (کیلومتر)',
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
          ),
          _field(_colorCtrl, label: 'رنگ'),
          _purchaseDateField(context),
        ];
      case AssetKind.gold:
        return [
          _field(
            _purityCtrl,
            label: 'عیار / خلوص',
            hint: 'مثل ۱۸ یا ۷۵۰',
          ),
        ];
      case AssetKind.cash:
      case AssetKind.crypto:
      case AssetKind.other:
        return const [];
    }
  }

  Widget _purchaseDateField(BuildContext context) {
    final calendar = context.watch<AppState>().settings.calendar;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: AppDateTile(
        label: 'تاریخ خرید',
        isoDate: _purchaseDate.isEmpty ? _buyDate : _purchaseDate,
        calendar: calendar,
        onChanged: _onBuyDateChanged,
      ),
    );
  }

  Widget _buyDateField(BuildContext context) {
    final calendar = context.watch<AppState>().settings.calendar;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: AppDateTile(
        label: 'تاریخ خرید',
        isoDate: _buyDate,
        calendar: calendar,
        onChanged: _onBuyDateChanged,
      ),
    );
  }
}

class _UsageChip extends StatelessWidget {
  const _UsageChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppTheme.accent.withValues(alpha: 0.18)
          : AppTheme.bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppTheme.title : AppTheme.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
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
