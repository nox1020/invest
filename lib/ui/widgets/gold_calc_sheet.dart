import 'package:flutter/material.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/asset_meta.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/services/gold_calc.dart';
import 'package:invest/domain/services/gold_calc_prefs.dart';
import 'package:invest/domain/services/gold_fund_book.dart';
import 'package:invest/domain/services/trade_service.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/gold_number_input.dart';
import 'package:invest/domain/utils/gold_purity.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/gold/gold_format.dart';
import 'package:invest/ui/gold/gold_input.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/app_date_picker.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart';
import 'package:invest/ui/widgets/user_error.dart';
import 'package:provider/provider.dart';

/// «ماشین‌حساب طلا»: buy or sell, by amount or weight, آب‌شده/آنلاین or
/// زینتی. [calcOnly] hides recording (the «فقط محاسبه» entry).
Future<void> showGoldCalcSheet(
  BuildContext context, {
  GoldSide side = GoldSide.buy,
  bool calcOnly = false,
  GoldCalcPrefs? prefs,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: kSheetBg,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: GoldCalcSheet(initialSide: side, calcOnly: calcOnly, prefs: prefs),
    ),
  );
}

/// Target of a buy: an existing gold asset or a new one by name.
class _Target {
  const _Target.asset(this.asset) : newName = null;
  const _Target.create(this.newName) : asset = null;
  final Asset? asset;
  final String? newName;
  String get key => asset != null ? 'a${asset!.id}' : 'n$newName';
  String get label => asset?.name ?? newName!;
}

enum _PriceSource { live, manual, mazaneh }

class GoldCalcSheet extends StatefulWidget {
  const GoldCalcSheet({super.key, this.initialSide = GoldSide.buy, this.calcOnly = false, this.prefs});

  final GoldSide initialSide;
  final bool calcOnly;

  /// Preloaded prefs (tests); loaded from the device otherwise.
  final GoldCalcPrefs? prefs;

  @override
  State<GoldCalcSheet> createState() => _GoldCalcSheetState();
}

class _GoldCalcSheetState extends State<GoldCalcSheet> {
  late GoldSide _side = widget.initialSide;
  GoldCalcPrefs _prefs = const GoldCalcPrefs();
  bool _touched = false;
  late GoldProduct _product = _prefs.product;
  late GoldInputMode _buyMode = _prefs.buyMode;
  late GoldInputMode _sellMode = _prefs.sellMode;
  late GoldLotOrder _order = _prefs.lotOrder;
  _PriceSource _priceSource = _PriceSource.live;
  String? _targetKey;
  int? _sellAssetId;
  String _date = todayIso();
  bool _busy = false;
  String _progress = '';

  final _input = TextEditingController();
  final _price = TextEditingController();
  final _mazaneh = TextEditingController();
  final _note = TextEditingController();
  final _fee = TextEditingController();
  final _making = TextEditingController();
  final _profit = TextEditingController();
  final _vat = TextEditingController();
  final Map<int, TextEditingController> _manual = {};

  @override
  void initState() {
    super.initState();
    if (widget.prefs != null) {
      _applyPrefs(widget.prefs!);
    } else {
      _fillFees();
      GoldCalcPrefs.load().then((p) {
        if (!mounted || _touched) return;
        setState(() => _applyPrefs(p));
      }).catchError((_) {});
    }
  }

  void _applyPrefs(GoldCalcPrefs p) {
    _prefs = p;
    _product = p.product;
    _buyMode = p.buyMode;
    _sellMode = p.sellMode;
    _order = p.lotOrder;
    _fillFees();
  }

  void _fillFees() {
    final f = _prefs.feesFor(_product);
    _fee.text = gNumLatin(f.feePct);
    _making.text = gNumLatin(f.makingPct);
    _profit.text = gNumLatin(f.profitPct);
    _vat.text = gNumLatin(f.vatPct);
  }

  @override
  void dispose() {
    for (final c in [_input, _price, _mazaneh, _note, _fee, _making, _profit, _vat, ..._manual.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _touch(VoidCallback f) {
    _touched = true;
    setState(f);
  }

  double _pct(TextEditingController c) {
    final v = parseGoldDecimal(c.text);
    return v == null || !v.isFinite || v < 0 ? 0 : v;
  }

  GoldFees get _fees => GoldFees(
        feePct: _pct(_fee),
        makingPct: _product == GoldProduct.jewelry ? _pct(_making) : 0,
        profitPct: _product == GoldProduct.jewelry ? _pct(_profit) : 0,
        vatPct: _product == GoldProduct.jewelry ? _pct(_vat) : 0,
      );

  void _savePrefs() {
    final f = _fees;
    final full = _product == GoldProduct.online
        ? _prefs.onlineFees.copyWith(feePct: f.feePct)
        : GoldFees(feePct: f.feePct, makingPct: f.makingPct, profitPct: f.profitPct, vatPct: f.vatPct);
    _prefs = _prefs.copyWith(
      product: _product,
      onlineFees: _product == GoldProduct.online ? full : null,
      jewelryFees: _product == GoldProduct.jewelry ? full : null,
      buyMode: _buyMode,
      sellMode: _sellMode,
      lotOrder: _order,
    );
    _prefs.save().catchError((_) {});
  }

  void _setProduct(GoldProduct p) {
    if (p == _product) return;
    _savePrefs();
    _touch(() {
      _product = p;
      _fillFees();
    });
    _savePrefs();
  }

  static double _purityOf(Asset a) => parseGoldPurityFraction(parseAssetNotes(a.notes).meta.purity) ?? k18GoldPurity;

  List<_Target> _targets(AppState s, GoldFundBook book) {
    final gold = [
      for (final a in s.assets)
        if (a.id != null && TradeService.isGoldAsset(a.name, a.symbol, a.notes)) a,
    ]..sort((a, b) {
        final ga = book.holdingFor(a.id!)?.grams18 ?? 0, gb = book.holdingFor(b.id!)?.grams18 ?? 0;
        return gb.compareTo(ga);
      });
    final out = [for (final a in gold) _Target.asset(a)];
    for (final n in const ['طلای آب‌شده', 'طلای زینتی']) {
      if (!gold.any((a) => a.name.trim() == n)) out.add(_Target.create(n));
    }
    return out;
  }

  _Target _target(List<_Target> all) {
    final byKey = {for (final t in all) t.key: t};
    if (_targetKey != null && byKey.containsKey(_targetKey)) return byKey[_targetKey]!;
    // Default: the asset matching the product. Jewelry otherwise goes to a
    // new «طلای زینتی» (kept apart from melted gold); online gold to the
    // biggest existing holding.
    final jewelry = _product == GoldProduct.jewelry;
    final want = jewelry ? 'زینتی' : 'آب‌شده';
    _Target? pick(bool Function(_Target) f) {
      for (final t in all) {
        if (f(t)) return t;
      }
      return null;
    }

    return pick((t) => t.asset != null && t.label.contains(want)) ??
        (jewelry ? pick((t) => t.asset == null && t.label.contains(want)) : null) ??
        pick((t) => t.asset != null) ??
        pick((t) => t.label.contains(want)) ??
        all.first;
  }

  GoldHolding? _sellHolding(GoldFundBook book) {
    if (book.holdings.isEmpty) return null;
    return book.holdingFor(_sellAssetId ?? -1) ?? book.mainHolding;
  }

  /// 18k price per gram for the side, from the live quote, a typed price or
  /// a typed مظنه.
  double _base18(GoldQuote q) {
    switch (_priceSource) {
      case _PriceSource.live:
        return _side == GoldSide.buy ? q.ask : q.bid;
      case _PriceSource.manual:
        return parseGoldToman(_price.text) ?? 0;
      case _PriceSource.mazaneh:
        return gram18FromMazaneh(parseGoldToman(_mazaneh.text) ?? 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final book = state.goldFund;
    final q = book.quote;
    final buy = _side == GoldSide.buy;
    final targets = _targets(state, book);
    final target = _target(targets);
    final sellH = _sellHolding(book);
    final purity =
        buy ? (target.asset != null ? _purityOf(target.asset!) : k18GoldPurity) : (sellH?.purity ?? k18GoldPurity);
    final karat = gNum(purity * 24, decimals: 1);
    final base18 = _base18(q);
    final price = convertGoldPrice(base18, k18GoldPurity, purity);
    final mode = buy ? _buyMode : _sellMode;
    final input = _parseInput(mode);
    final fees = _fees;
    final bid = convertGoldPrice(q.bid, k18GoldPurity, purity);
    final mid = convertGoldPrice(q.mid, k18GoldPurity, purity);
    final cash = book.cash;

    GoldBuyQuote? bq;
    GoldSellQuote? sq;
    if (buy) {
      final h = target.asset == null ? null : book.holdingFor(target.asset!.id!);
      bq = GoldCalc.buy(
        product: _product,
        mode: mode,
        input: input,
        pricePerGram: price,
        fees: fees,
        midPerGram: mid > 0 ? mid : null,
        exitPerGram: bid > 0 ? bid : null,
        exitFeePct: _prefs.onlineFees.feePct,
        cashBefore: cash,
        holdingBefore: h?.grams ?? 0,
        costBefore: h?.cost ?? 0,
      );
    } else if (sellH != null) {
      sq = GoldCalc.sell(
        mode: mode,
        input: input,
        pricePerGram: price,
        feePct: fees.feePct,
        lots: sellH.calcLots,
        order: _order,
        manualGrams: {
          for (final e in _manual.entries)
            if ((parseGoldDecimal(e.value.text) ?? 0) > 0) e.key: parseGoldDecimal(e.value.text)!,
        },
        cashBefore: cash,
        holdingBefore: sellH.grams,
        costBefore: sellH.cost,
      );
    }

    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Flexible(
            child: SingleChildScrollView(
              key: const ValueKey('gc-scroll'),
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _header(buy, cash, sellH),
                const SizedBox(height: 8),
                _sideToggle(),
                const SizedBox(height: 8),
                _modeRow(buy, mode),
                const SizedBox(height: 8),
                if (!(!buy && _order == GoldLotOrder.manual)) ...[
                  _inputField(buy, mode, purity, karat),
                  const SizedBox(height: 6),
                  _chips(buy, mode, cash, sellH),
                  const SizedBox(height: 8),
                ],
                _priceBox(buy, q, base18, price, purity, karat),
                const SizedBox(height: 8),
                _feeRow(buy, karat, targets, target, book),
                const SizedBox(height: 8),
                if (!buy && _order == GoldLotOrder.manual && sellH != null) ...[
                  _manualLots(sellH),
                  const SizedBox(height: 8),
                ],
                if (buy) ..._buyResults(bq!, q) else if (sq != null) ..._sellResults(sq, sellH!),
                if (!widget.calcOnly && state.canMutate) ...[
                  const SizedBox(height: 4),
                  _dateNote(state.settings.calendar),
                ],
              ]),
            ),
          ),
          _footer(state, buy, bq, sq, target, sellH),
        ]),
      ),
    );
  }

  Widget _header(bool buy, double cash, GoldHolding? sellH) {
    final chip = buy || sellH == null ? 'نقد صندوق ${gToman(cash)}' : 'موجودی ${gGrams(sellH.grams)}';
    return Row(children: [
      const Expanded(
        child: Text('ماشین‌حساب طلا',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppTheme.title, fontSize: 15, fontWeight: FontWeight.w900)),
      ),
      Flexible(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border),
          ),
          child: GFit(chip,
              key: const ValueKey('gc-header-chip'),
              style: TextStyle(color: buy ? AppTheme.text : kGold, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ),
    ]);
  }

  Widget _seg<T>(Key key, List<(T, String)> items, T value, ValueChanged<T> onChanged, {Color? selected}) {
    return SegmentedButton<T>(
      key: key,
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        selectedBackgroundColor: (selected ?? const Color(0xFF24382E)),
        selectedForegroundColor: Colors.white,
        foregroundColor: AppTheme.muted,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      segments: [
        for (final (v, l) in items)
          ButtonSegment<T>(value: v, label: FittedBox(fit: BoxFit.scaleDown, child: Text(l, maxLines: 1))),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }

  Widget _sideToggle() => SizedBox(
        width: double.infinity,
        child: _seg<GoldSide>(
          const ValueKey('gc-side'),
          const [(GoldSide.buy, 'خرید'), (GoldSide.sell, 'فروش')],
          _side,
          (v) => _touch(() {
            _side = v;
            _input.clear();
            _priceSource = _PriceSource.live;
          }),
          selected: _side == GoldSide.buy ? AppTheme.positive.withValues(alpha: 0.35) : kGold.withValues(alpha: 0.35),
        ),
      );

  Widget _modeRow(bool buy, GoldInputMode mode) {
    final product = _seg<GoldProduct>(
      const ValueKey('gc-product'),
      const [(GoldProduct.online, 'آب‌شده / آنلاین'), (GoldProduct.jewelry, 'زینتی')],
      _product,
      _setProduct,
    );
    final inputMode = _seg<GoldInputMode>(
      const ValueKey('gc-mode'),
      const [(GoldInputMode.amount, 'با مبلغ'), (GoldInputMode.weight, 'با وزن')],
      mode,
      (v) {
        _touch(() {
          if (buy) {
            _buyMode = v;
          } else {
            _sellMode = v;
          }
          _input.clear();
        });
        _savePrefs();
      },
    );
    return LayoutBuilder(builder: (ctx, c) {
      if (c.maxWidth < 360) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          product,
          if (!(!buy && _order == GoldLotOrder.manual)) ...[const SizedBox(height: 6), inputMode],
        ]);
      }
      return Row(children: [
        Expanded(flex: 6, child: product),
        if (!(!buy && _order == GoldLotOrder.manual)) ...[
          const SizedBox(width: 8),
          Expanded(flex: 5, child: inputMode),
        ],
      ]);
    });
  }

  /// Toman (grouped) in amount mode, a decimal weight otherwise.
  double _parseInput(GoldInputMode mode) =>
      (mode == GoldInputMode.amount ? parseGoldToman(_input.text) : parseGoldDecimal(_input.text)) ?? 0;

  Widget _inputField(bool buy, GoldInputMode mode, double purity, String karat) {
    final v = _parseInput(mode);
    final String label;
    final String hint;
    if (mode == GoldInputMode.amount) {
      label = buy ? 'مبلغ پرداختی (تومان)' : 'نقد موردنیاز از فروش (تومان)';
      hint = v > 0 ? gCompact(v) : '';
    } else {
      label = buy ? 'وزن (گرم $karat عیار)' : 'وزن فروش (گرم $karat عیار)';
      final g18 = convertGoldGrams(v, purity, k18GoldPurity);
      hint = v > 0 ? '≈ ${gNum(gramsToMithqal(g18), decimals: 3)} مثقال' : '';
    }
    return TextField(
      key: const ValueKey('gc-input'),
      controller: _input,
      keyboardType: TextInputType.numberWithOptions(decimal: mode == GoldInputMode.weight),
      inputFormatters: [if (mode == GoldInputMode.amount) const GoldTomanFormatter() else goldDecimalFormatter],
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
      style: const TextStyle(color: AppTheme.title, fontSize: 18, fontWeight: FontWeight.w900),
      decoration: InputDecoration(labelText: label, helperText: hint.isEmpty ? null : hint, isDense: true),
      onChanged: (_) => _touch(() {}),
    );
  }

  Widget _chips(bool buy, GoldInputMode mode, double cash, GoldHolding? sellH) {
    final chips = <(String, double)>[];
    if (mode == GoldInputMode.amount) {
      chips.addAll([('۵۰ م', 50e6), ('۱۰۰ م', 100e6)]);
      if (buy && cash > 0) chips.addAll([('نصف نقد', (cash / 2).floorToDouble()), ('همهٔ نقد', cash.floorToDouble())]);
    } else if (buy) {
      chips.addAll([('۱ گرم', 1), ('۵ گرم', 5), ('۱۰ گرم', 10)]);
    } else {
      chips.addAll([('۵ گرم', 5), ('۱۰ گرم', 10)]);
      if (sellH != null && sellH.grams > 0) {
        chips.add(('نصف', roundGrams(sellH.grams / 2)));
        chips.add(('همه ${gNum(sellH.grams)}', roundGrams(sellH.grams)));
      }
    }
    final cur = _input.text.trim().isEmpty ? null : _parseInput(mode);
    return Wrap(spacing: 6, runSpacing: 4, children: [
      for (final (l, v) in chips)
        ChoiceChip(
          label: Text(l, style: const TextStyle(fontSize: 11.5)),
          selected: cur != null && (cur - v).abs() < 1e-6,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => _touch(() => _input.text = mode == GoldInputMode.amount ? goldTomanText(v) : _latin(v)),
        ),
    ]);
  }

  static String _latin(double v) {
    if ((v - v.roundToDouble()).abs() < 1e-9) return v.round().toString();
    var s = v.toStringAsFixed(3);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
  }

  Widget _priceBox(bool buy, GoldQuote q, double base18, double price, double purity, String karat) {
    final live = _priceSource == _PriceSource.live;
    final title = [
      buy ? 'قیمت خرید هر گرم ۱۸' : 'قیمت فروش هر گرم ۱۸',
      switch (_priceSource) {
        _PriceSource.live => q.estimated ? 'زنده · سمت خرید/فروش تخمینی' : 'زنده والگلد',
        _PriceSource.manual => 'دستی',
        _PriceSource.mazaneh => 'از مظنه ÷ ${gNum(mazanehDivisor, decimals: 4)}',
      },
    ].join(' · ');
    Widget pill(String l, _PriceSource s, Key key) => Padding(
          padding: const EdgeInsetsDirectional.only(start: 4),
          child: ChoiceChip(
            key: key,
            label: Text(l, style: const TextStyle(fontSize: 11)),
            selected: _priceSource == s,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => _touch(() {
              _priceSource = _priceSource == s ? _PriceSource.live : s;
              if (_priceSource == _PriceSource.manual && _price.text.isEmpty && base18 > 0) {
                _price.text = goldTomanText(base18);
              }
              if (_priceSource == _PriceSource.mazaneh && _mazaneh.text.isEmpty && q.hasPrice) {
                _mazaneh.text = goldTomanText(mazanehFromGram18(_side == GoldSide.buy ? q.ask : q.bid));
              }
            }),
          ),
        );
    return Container(
      key: const ValueKey('gc-price'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: mutedStyle(10)),
              GFit(base18 > 0 ? gToman(base18) : '—',
                  key: const ValueKey('gc-price-value'),
                  style: const TextStyle(color: AppTheme.title, fontSize: 15, fontWeight: FontWeight.w900)),
            ]),
          ),
          pill('ویرایش', _PriceSource.manual, const ValueKey('gc-price-edit')),
          pill('مظنه', _PriceSource.mazaneh, const ValueKey('gc-price-mazaneh')),
        ]),
        if (_priceSource == _PriceSource.manual)
          TextField(
            key: const ValueKey('gc-price-input'),
            controller: _price,
            keyboardType: TextInputType.number,
            inputFormatters: const [GoldTomanFormatter()],
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.right,
            decoration: const InputDecoration(labelText: 'قیمت هر گرم ۱۸ عیار (تومان)', isDense: true),
            onChanged: (_) => _touch(() {}),
          ),
        if (_priceSource == _PriceSource.mazaneh)
          TextField(
            key: const ValueKey('gc-mazaneh-input'),
            controller: _mazaneh,
            keyboardType: TextInputType.number,
            inputFormatters: const [GoldTomanFormatter()],
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.right,
            decoration: const InputDecoration(labelText: 'مظنه (مثقال ۱۷، تومان)', isDense: true),
            onChanged: (_) => _touch(() {}),
          ),
        if ((purity - k18GoldPurity).abs() > 1e-6 && price > 0)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text('برای $karat عیار: هر گرم ${gToman(price)}', style: mutedStyle(10)),
          ),
        if (!live && q.hasPrice && base18 > 0)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              'نسبت به قیمت زنده ${gPct((base18 / (buy ? q.ask : q.bid) - 1) * 100, decimals: 2)}',
              style: mutedStyle(10),
            ),
          ),
      ]),
    );
  }

  Widget _pctField(String label, TextEditingController c, Key key) => TextField(
        key: key,
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [goldDecimalFormatter],
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.right,
        style: const TextStyle(color: AppTheme.title, fontSize: 13, fontWeight: FontWeight.w800),
        decoration: InputDecoration(labelText: label, suffixText: '٪', isDense: true),
        onChanged: (_) {
          _touch(() {});
          _savePrefs();
        },
      );

  Widget _feeRow(bool buy, String karat, List<_Target> targets, _Target target, GoldFundBook book) {
    final children = <Widget>[];
    if (buy && _product == GoldProduct.jewelry) {
      children.addAll([
        Expanded(child: _pctField('اجرت ساخت', _making, const ValueKey('gc-making'))),
        const SizedBox(width: 6),
        Expanded(child: _pctField('سود فروشنده', _profit, const ValueKey('gc-profit'))),
        const SizedBox(width: 6),
        Expanded(child: _pctField('مالیات', _vat, const ValueKey('gc-vat'))),
      ]);
    } else {
      children.add(Expanded(child: _pctField(buy ? 'کارمزد' : 'کارمزد / کسر', _fee, const ValueKey('gc-fee'))));
    }
    final second = <Widget>[];
    if (buy) {
      second.add(Expanded(
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'به دارایی', isDense: true),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: const ValueKey('gc-target'),
              isDense: true,
              isExpanded: true,
              value: target.key,
              items: [
                for (final t in targets)
                  DropdownMenuItem(
                    value: t.key,
                    child: Text(
                      t.asset == null ? '${t.label} (جدید)' : t.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
              ],
              onChanged: (v) => _touch(() => _targetKey = v),
            ),
          ),
        ),
      ));
    } else {
      if (book.holdings.length > 1) {
        final cur = _sellHolding(book);
        second.add(Expanded(
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'از دارایی', isDense: true),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                key: const ValueKey('gc-sell-asset'),
                isDense: true,
                isExpanded: true,
                value: cur?.asset.id,
                items: [
                  for (final h in book.holdings)
                    DropdownMenuItem(
                      value: h.asset.id,
                      child: Text('${h.asset.name} · ${gGrams(h.grams)}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                    ),
                ],
                onChanged: (v) => _touch(() {
                  _sellAssetId = v;
                  _manual.clear();
                }),
              ),
            ),
          ),
        ));
        second.add(const SizedBox(width: 6));
      }
      second.add(Expanded(
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'ترتیب لات‌ها', isDense: true),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<GoldLotOrder>(
              key: const ValueKey('gc-order'),
              isDense: true,
              isExpanded: true,
              value: _order,
              items: [
                for (final o in GoldLotOrder.values)
                  DropdownMenuItem(
                    value: o,
                    child: Text(o.label,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                  ),
              ],
              onChanged: (v) {
                if (v == null) return;
                _touch(() => _order = v);
                _savePrefs();
              },
            ),
          ),
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      const SizedBox(height: 6),
      Row(children: second),
      if (buy)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text('عیار: $karat', style: mutedStyle(10)),
        ),
    ]);
  }

  Widget _manualLots(GoldHolding h) {
    final lots = GoldCalc.sortLots(h.calcLots, GoldLotOrder.fifo);
    final cal = context.read<AppState>().settings.calendar;
    return Container(
      key: const ValueKey('gc-manual'),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('وزن فروش از هر لات',
            style: TextStyle(color: AppTheme.title, fontSize: 11.5, fontWeight: FontWeight.w800)),
        for (final l in lots)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              Expanded(
                flex: 3,
                child: Text(
                  '${gGrams(l.grams)} · ${formatDisplayDate(l.buyDate, cal)} · خرید ${gToman(l.buyPrice)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: mutedStyle(10.5),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: TextField(
                  key: ValueKey('gc-manual-${l.id}'),
                  controller: _manual.putIfAbsent(l.id, TextEditingController.new),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [goldDecimalFormatter],
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '0',
                    suffixIcon: IconButton(
                      tooltip: 'همهٔ این لات',
                      icon: const Icon(Icons.select_all, size: 18),
                      onPressed: () => _touch(() => _manual[l.id]!.text = _latin(l.grams)),
                    ),
                  ),
                  onChanged: (_) => _touch(() {}),
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _resBox(
      {required bool cashTone,
      required String k,
      required String big,
      String? small,
      required List<Widget> kvs,
      Key? key}) {
    final c = cashTone ? AppTheme.positive : kGold;
    return Container(
      key: key,
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.withValues(alpha: 0.35)),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topEnd,
          end: AlignmentDirectional.bottomStart,
          colors: [cashTone ? const Color(0xFF103A24) : const Color(0xFF3A3010), const Color(0xFF18261D)],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(k,
            style: TextStyle(
                color: cashTone ? const Color(0xFFBFE9CF) : kGoldText, fontSize: 11, fontWeight: FontWeight.w700)),
        GFit(small == null ? big : '$big  $small',
            key: const ValueKey('gc-result-big'),
            style: TextStyle(color: c, fontSize: 23, fontWeight: FontWeight.w900, height: 1.3)),
        ...kvs,
      ]),
    );
  }

  Widget _changeBox(String title, List<(String, String?, String, Color?)> rows) => Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: AppTheme.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(color: AppTheme.title, fontSize: 11.5, fontWeight: FontWeight.w800)),
          for (final (k, before, after, c) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(child: Text(k, maxLines: 1, overflow: TextOverflow.ellipsis, style: mutedStyle(11))),
                if (before != null)
                  Flexible(
                    child: GFit(before,
                        align: AlignmentDirectional.centerEnd,
                        style: const TextStyle(
                            color: AppTheme.muted, fontSize: 10.5, decoration: TextDecoration.lineThrough)),
                  ),
                const SizedBox(width: 6),
                Flexible(
                  flex: 2,
                  child: GFit(after,
                      align: AlignmentDirectional.centerEnd,
                      style: TextStyle(color: c ?? AppTheme.title, fontSize: 12, fontWeight: FontWeight.w800)),
                ),
              ]),
            ),
        ]),
      );

  List<Widget> _buyResults(GoldBuyQuote r, GoldQuote q) {
    if (r.pricePerGram <= 0) {
      return const [GNote('قیمت طلا در دسترس نیست؛ قیمت را دستی وارد کنید.', color: kWarn, icon: Icons.info_outline)];
    }
    if (r.isEmpty) {
      final hint = _buyMode == GoldInputMode.amount && r.leftover > 0
          ? 'این مبلغ برای کمترین وزن (۰٫۰۰۱ گرم) کافی نیست.'
          : 'مبلغ یا وزن را وارد کنید.';
      return [GNote(hint, color: AppTheme.muted, icon: Icons.edit_outlined)];
    }
    final jewelry = r.product == GoldProduct.jewelry;
    final amountMode = _buyMode == GoldInputMode.amount;
    final kvs = <Widget>[
      GKv(jewelry ? 'طلای خالص' : 'ارزش طلا', gToman(r.goldValue)),
      if (!jewelry) GKv('کارمزد ${gNum(_fees.feePct, decimals: 2)}٪', gToman(r.commission)),
      if (jewelry) ...[
        if (r.commission > 0) GKv('کارمزد ${gNum(_fees.feePct, decimals: 2)}٪', gToman(r.commission)),
        GKv('اجرت ساخت ${gNum(_fees.makingPct, decimals: 2)}٪', gToman(r.making)),
        GKv('سود فروشنده ${gNum(_fees.profitPct, decimals: 2)}٪', gToman(r.profit)),
        GKv('مالیات ${gNum(_fees.vatPct, decimals: 2)}٪ (روی اجرت و سود)', gToman(r.vat)),
      ],
      if (amountMode || jewelry) GKv(amountMode ? 'جمع پرداختی' : 'مبلغ فاکتور', gToman(r.total), bold: true),
      if (amountMode && r.leftover > 0)
        GKv('باقی‌ماندهٔ مبلغ (کمتر از ۰٫۰۰۱ گرم)', gToman(r.leftover), color: AppTheme.muted),
      GKv('قیمت تمام‌شده هر گرم', gToman(r.effectivePerGram), valueKey: const ValueKey('gc-effective')),
      if (r.premiumPct != null)
        GKv('نسبت به قیمت میانهٔ بازار', gPct(r.premiumPct!, decimals: 2), color: AppTheme.muted),
    ];
    final big = amountMode && !jewelry
        ? _resBox(
            key: const ValueKey('gc-result'),
            cashTone: false,
            k: 'طلایی که می‌گیرید',
            big: gGrams(r.grams),
            small: '≈ ${gNum(gramsToMithqal(r.grams), decimals: 3)} مثقال',
            kvs: kvs)
        : _resBox(
            key: const ValueKey('gc-result'),
            cashTone: false,
            k: jewelry ? 'مبلغ فاکتور' : 'مبلغ پرداختی',
            big: '${gToman(r.total)} تومان',
            small: amountMode ? gGrams(r.grams) : null,
            kvs: kvs);
    final cashAfter = r.cashAfter;
    final out = <Widget>[
      big,
      const SizedBox(height: 8),
      _changeBox('بعد از این خرید', [
        ('موجودی طلا', gNum(r.holdingBefore), gGrams(r.holdingAfter), null),
        ('میانگین خرید هر گرم', r.holdingBefore > 0 ? gToman(r.avgBefore) : null, gToman(r.avgAfter), null),
        if (cashAfter != null)
          ('نقد صندوق', gToman(r.cashBefore!), gToman(cashAfter), cashAfter < 0 ? AppTheme.negative : null),
        if (r.breakEvenSellPrice > 0)
          (
            'سربه‌سر این خرید (فروش)',
            null,
            r.breakEvenOverExitPct == null
                ? gToman(r.breakEvenSellPrice)
                : '${gToman(r.breakEvenSellPrice)}  ${gPct(r.breakEvenOverExitPct!)}',
            null
          ),
      ]),
      const SizedBox(height: 8),
    ];
    if (jewelry || r.nonRecoverablePct >= 3) {
      final loss = r.exitResult;
      out.add(GNote(
        '',
        color: kWarn,
        icon: Icons.warning_amber_rounded,
        child: Text(
          '${gToman(r.nonRecoverable)} تومان (${gNum(r.nonRecoverablePct, decimals: 1)}٪ روی ارزش طلا) هزینهٔ غیرقابل برگشت است.'
          '${loss == null ? '' : ' اگر فردا به‌صورت آب‌شده بفروشید حدود ${gSigned(loss)} ${loss < 0 ? 'ضرر' : 'سود'}'}'
          '${r.breakEvenSellPrice > 0 ? '؛ سربه‌سر وقتی قیمت فروش به ${gToman(r.breakEvenSellPrice)} برسد${r.breakEvenOverExitPct == null ? '' : ' (${gPct(r.breakEvenOverExitPct!)})'}.' : '.'}',
          key: const ValueKey('gc-warn-cost'),
          style: const TextStyle(color: Color(0xFFFFD5A0), fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.6),
        ),
      ));
      out.add(const SizedBox(height: 8));
    }
    if (q.hasPrice && q.estimated && _priceSource == _PriceSource.live) {
      out.add(const GNote(
        'قیمت خرید بازار تخمینی است (میانه + ۰٫۵٪). قبل از ثبت، با «ویرایش» قیمت واقعی را وارد کنید.',
        color: AppTheme.muted,
        icon: Icons.info_outline,
      ));
      out.add(const SizedBox(height: 8));
    }
    if (cashAfter != null) {
      if (r.shortfall > 0) {
        out.add(GNote(
          'نقد صندوق ${gToman(r.shortfall)} تومان کم است.${widget.calcOnly ? '' : ' «واریز کسری و ثبت خرید» مابه‌التفاوت را اول به‌عنوان واریز ثبت می‌کند.'}',
          key: const ValueKey('gc-shortfall'),
          color: AppTheme.negative,
          icon: Icons.close_rounded,
        ));
      } else {
        out.add(const GNote('نقد صندوق کافی است',
            key: ValueKey('gc-enough'), color: AppTheme.positive, icon: Icons.check_rounded));
      }
    }
    return out;
  }

  List<Widget> _sellResults(GoldSellQuote r, GoldHolding h) {
    if (r.pricePerGram <= 0) {
      return const [GNote('قیمت طلا در دسترس نیست؛ قیمت را دستی وارد کنید.', color: kWarn, icon: Icons.info_outline)];
    }
    if (r.isEmpty) {
      return [
        GNote(_order == GoldLotOrder.manual ? 'وزن فروش هر لات را وارد کنید.' : 'وزن یا مبلغ فروش را وارد کنید.',
            color: AppTheme.muted, icon: Icons.edit_outlined),
      ];
    }
    final cal = context.read<AppState>().settings.calendar;
    final out = <Widget>[
      _resBox(
        key: const ValueKey('gc-result'),
        cashTone: true,
        k: 'نقدی که می‌گیرید',
        big: '${gToman(r.net)} تومان',
        small: _sellMode == GoldInputMode.amount ? gGrams(r.grams) : null,
        kvs: [
          GKv('ارزش فروش', gToman(r.gross)),
          GKv('کارمزد ${gNum(_fees.feePct, decimals: 2)}٪', gSigned(-r.fee), color: AppTheme.negative),
          if (r.hasLots)
            GKv('سود قطعی', '${gSigned(r.realized)}  (${gPct(r.realizedPct)})',
                color: toneOf(r.realized), valueKey: const ValueKey('gc-realized')),
        ],
      ),
      const SizedBox(height: 8),
    ];
    if (r.exceedsHolding) {
      out.add(GNote(
        'موجودی این دارایی ${gGrams(r.available)} است؛ بیش از موجودی نمی‌شود فروخت.',
        key: const ValueKey('gc-exceeds'),
        color: AppTheme.negative,
        icon: Icons.close_rounded,
      ));
      out.add(const SizedBox(height: 8));
    }
    if (r.hasLots) {
      out.add(Container(
        key: const ValueKey('gc-takes'),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: AppTheme.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(fa('لات‌هایی که فروخته می‌شوند (${r.takes.length})'),
              style: const TextStyle(color: AppTheme.title, fontSize: 11.5, fontWeight: FontWeight.w800)),
          for (final t in r.takes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(
                  child: Text(
                    '${t.closesWholeLot ? gGrams(t.grams) : '${gNum(t.grams)} از ${gGrams(t.lot.grams)}'}'
                    ' · ${formatDisplayDate(t.lot.buyDate, cal)} · خرید ${gToman(t.lot.buyPrice)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: mutedStyle(10.5),
                  ),
                ),
                const SizedBox(width: 6),
                Text(gSigned(t.realized),
                    style: TextStyle(color: toneOf(t.realized), fontSize: 11, fontWeight: FontWeight.w800)),
              ]),
            ),
        ]),
      ));
      out.add(const SizedBox(height: 8));
    }
    final early = widget.calcOnly ? null : goldSellDateConflict(r, _date);
    if (early != null) {
      out.add(GNote(
        'تاریخ فروش قبل از تاریخ خرید یکی از لات‌ها (${formatDisplayDate(early, cal)}) است؛ تاریخ را درست کنید.',
        key: const ValueKey('gc-date-early'),
        color: AppTheme.negative,
        icon: Icons.event_busy_rounded,
      ));
      out.add(const SizedBox(height: 8));
    }
    if (r.picksMismatch && !r.exceedsHolding) {
      out.add(const GNote('وزن انتخاب‌شده از لات‌ها با وزن فروش یکی نیست.',
          color: kWarn, icon: Icons.warning_amber_rounded));
      out.add(const SizedBox(height: 8));
    }
    final cashAfter = r.cashAfter;
    out.add(_changeBox('بعد از این فروش', [
      ('موجودی طلا', gNum(r.holdingBefore), gGrams(r.holdingAfter), null),
      (
        'میانگین خرید هر گرم',
        r.holdingBefore > 0 ? gToman(r.avgBefore) : null,
        r.holdingAfter > 0 ? gToman(r.avgAfter) : '—',
        null
      ),
      if (cashAfter != null) ('نقد صندوق', gToman(r.cashBefore!), gToman(cashAfter), AppTheme.positive),
    ]));
    if (r.takes.length > 1 && !widget.calcOnly) {
      out.add(const SizedBox(height: 8));
      out.add(GNote(
        fa('این فروش ${r.takes.length} لات را جدا جدا می‌بندد. اگر اتصال قطع باشد، در صف همگام‌سازی می‌ماند و وضعیتش بعد از ثبت نشان داده می‌شود.'),
        color: AppTheme.muted,
        icon: Icons.sync_rounded,
      ));
    }
    if (h.lots.any((t) => (t.id ?? 0) < 0)) {
      out.add(const SizedBox(height: 8));
      out.add(const GNote('بعضی لات‌ها هنوز همگام نشده‌اند؛ فروششان هم در صف می‌ماند.',
          color: kAmber, icon: Icons.cloud_off_rounded));
    }
    return out;
  }

  Widget _dateNote(String calendar) => Row(children: [
        Expanded(
          child: InkWell(
            key: const ValueKey('gc-date'),
            onTap: () async {
              final iso = await pickAppDate(context, calendar: calendar, initialIso: _date, helpText: 'تاریخ معامله');
              if (iso != null) _touch(() => _date = iso);
            },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'تاریخ', isDense: true),
              child: Text(formatDisplayDate(_date, calendar), maxLines: 1, style: const TextStyle(fontSize: 13)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            key: const ValueKey('gc-note'),
            controller: _note,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'یادداشت', isDense: true, counterText: ''),
          ),
        ),
      ]);

  Widget _footer(AppState state, bool buy, GoldBuyQuote? bq, GoldSellQuote? sq, _Target target, GoldHolding? sellH) {
    final record = !widget.calcOnly && state.canMutate;
    String label = buy ? 'ثبت خرید' : 'ثبت فروش';
    VoidCallback? onRecord;
    Color color = buy ? AppTheme.positive : kGold;
    if (buy && bq != null && !bq.isEmpty) {
      if (bq.shortfall > 0) {
        label = 'واریز کسری و ثبت خرید';
      } else {
        label = 'ثبت خرید ${gGrams(bq.grams)}';
      }
      onRecord = () => _recordBuy(state, bq, target);
    } else if (!buy && sq != null && sq.canRecord && goldSellDateConflict(sq, _date) == null) {
      label = 'ثبت فروش ${gGrams(sq.grams)}';
      onRecord = () => _recordSell(state, sq, sellH!);
    }
    if (_busy) onRecord = null;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      decoration: const BoxDecoration(
        color: kSheetBg,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_busy && _progress.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(_progress, key: const ValueKey('gc-progress'), style: mutedStyle(11)),
          ),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              key: const ValueKey('gc-close'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                foregroundColor: AppTheme.text,
                side: const BorderSide(color: AppTheme.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
              child: FittedBox(fit: BoxFit.scaleDown, child: Text(record ? 'فقط محاسبه' : 'بستن', maxLines: 1)),
            ),
          ),
          if (record) ...[
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton(
                key: const ValueKey('gc-record'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  backgroundColor: color,
                  foregroundColor: AppTheme.bg,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: onRecord,
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
              ),
            ),
          ],
        ]),
      ]),
    );
  }

  Future<bool> _confirm(String title, List<String> lines) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(lines.join('\n'), style: const TextStyle(height: 1.7))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(
                key: const ValueKey('gc-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('ثبت')),
          ],
        ),
      ),
    );
    return ok == true;
  }

  Future<void> _recordBuy(AppState state, GoldBuyQuote r, _Target target) async {
    final cal = state.settings.calendar;
    final ok = await _confirm('ثبت خرید طلا', [
      '${gGrams(r.grams)} ${target.label}${target.asset == null ? ' (دارایی جدید)' : ''}',
      'قیمت هر گرم ${gToman(r.pricePerGram)} · هزینه‌ها ${gToman(r.recordFee)}',
      'جمع ${gToman(r.total)} تومان از نقد صندوق',
      if (r.shortfall > 0) 'اول ${gToman(r.shortfall)} تومان به‌عنوان «واریز نقد» ثبت می‌شود.',
      'تاریخ ${formatDisplayDate(_date, cal)}',
    ]);
    if (!ok || !mounted) return;
    _savePrefs();
    setState(() {
      _busy = true;
      _progress = 'در حال ثبت…';
    });
    try {
      final res = await state.recordGoldBuy(
        assetId: target.asset?.id,
        newAssetName: target.newName,
        grams: r.grams,
        pricePerGram: r.pricePerGram,
        fee: r.recordFee,
        date: _date,
        note: _note.text,
        gapDeposit: r.shortfall,
      );
      if (!mounted) return;
      _finish(res, 'خرید ${gGrams(r.grams)} طلا');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showUserError(context, e);
      }
    }
  }

  Future<void> _recordSell(AppState state, GoldSellQuote r, GoldHolding h) async {
    final cal = state.settings.calendar;
    final ok = await _confirm('ثبت فروش طلا', [
      '${gGrams(r.grams)} از ${h.asset.name} · ${fa('${r.takes.length}')} لات',
      'قیمت هر گرم ${gToman(r.pricePerGram)} · کارمزد ${gToman(r.fee)}',
      'خالص ${gToman(r.net)} تومان به نقد صندوق',
      'سود قطعی ${gSigned(r.realized)}',
      'تاریخ ${formatDisplayDate(_date, cal)}',
    ]);
    if (!ok || !mounted) return;
    _savePrefs();
    setState(() {
      _busy = true;
      _progress = fa('در حال ثبت ۰ از ${r.takes.length} لات…');
    });
    try {
      final res = await state.recordGoldSell(
        quote: r,
        date: _date,
        note: _note.text,
        onProgress: (d, t) {
          if (mounted) setState(() => _progress = fa('در حال ثبت $d از $t لات…'));
        },
      );
      if (!mounted) return;
      _finish(res, 'فروش ${gGrams(r.grams)} طلا');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showUserError(context, e);
      }
    }
  }

  void _finish(GoldRecordResult res, String what) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (res.complete) {
      Navigator.of(context).maybePop();
      messenger?.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(res.queued == 0
            ? '$what ثبت شد.'
            : res.queued == res.total
                ? '$what در صف همگام‌سازی است و با اتصال ارسال می‌شود.'
                : fa('$what ثبت شد؛ ${res.queued} از ${res.total} لات در صف همگام‌سازی است.')),
      ));
      return;
    }
    setState(() => _busy = false);
    showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(res.done == 0 ? 'ثبت نشد' : 'ثبت ناقص ماند'),
          content: Text(
            [
              if (res.done > 0) fa('${res.done} از ${res.total} لات ثبت شد (${res.sent} ارسال، ${res.queued} در صف).'),
              if (res.done > 0) 'بقیه ثبت نشد؛ موجودی را بررسی و دوباره محاسبه کنید.',
              formatUserError(res.error ?? 'خطای ناشناخته'),
            ].join('\n'),
            style: const TextStyle(height: 1.7),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (res.done > 0) Navigator.of(context).maybePop();
              },
              child: const Text('باشه'),
            ),
          ],
        ),
      ),
    );
  }
}

/// `0.5` / `15` (Latin; for editable fields).
String gNumLatin(double v) {
  if (!v.isFinite) return '0';
  if ((v - v.roundToDouble()).abs() < 1e-9) return v.round().toString();
  var s = v.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s;
}
