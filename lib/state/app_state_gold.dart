part of 'app_state.dart';

/// Outcome of recording a «صندوق طلا» buy or sell.
class GoldRecordResult {
  const GoldRecordResult({
    required this.opId,
    required this.total,
    this.done = 0,
    this.queued = 0,
    this.error,
  });

  final String opId;

  /// Trades the operation needs (1 for a buy, one per lot for a sale).
  final int total;

  /// Trades written (sent or queued).
  final int done;

  /// Of [done], how many wait in the offline queue.
  final int queued;

  /// First failure; the remaining lots were not touched.
  final Object? error;

  bool get complete => error == null && done == total;
  bool get partial => done > 0 && done < total;
  int get sent => done - queued;
}

/// «صندوق طلا»: the fund book, its cash entries and buy/sell recording.
extension AppStateGold on AppState {
  /// 18k quote with buy/sell sides (estimated when the feed lacks them).
  GoldQuote get goldQuote => GoldQuote.resolve(
        mid: liveGold ?? settings.goldTmnPerGram,
        bid: liveGoldBid,
        ask: liveGoldAsk,
        change24hPct: liveGoldChange24h,
      );

  GoldFundBook get goldFund => GoldFundBook.compute(
        assets: assets,
        openTrades: openTrades,
        closedTrades: closedTrades,
        ledger: settings.goldFundLedger,
        quote: goldQuote,
      );

  /// Fund cash; part of «ارزش پورتفو» (like open cheques), never of the
  /// daily holdings series.
  double get goldFundCash => goldFund.cash;

  Future<void> loadGoldPriceLog() async {
    try {
      goldPriceLog = await GoldPriceLog.load();
      notifyListeners();
    } catch (e, st) {
      logLocalFailure('gold-price-log', e, st);
    }
  }

  /// Logs today's 18k price (one point per day).
  Future<void> _recordGoldPrice() async {
    final q = goldQuote;
    if (!q.hasPrice) return;
    try {
      final next = await GoldPriceLog.record(
        today: todayIso(),
        mid: q.mid,
        bid: q.estimated ? null : q.bid,
        ask: q.estimated ? null : q.ask,
      );
      if (next != null) goldPriceLog = next;
    } catch (e, st) {
      logLocalFailure('gold-price-log', e, st);
    }
  }

  void _noteGoldSides(GoldLiveQuote? g) {
    if (g == null || g.price == null || g.price! <= 0) return;
    liveGoldBid = g.bid;
    liveGoldAsk = g.ask;
    liveGoldChange24h = g.change24h;
  }

  /// Adds a manual cash entry. [amount] is positive; for
  /// [GoldCashKind.adjust] it is the new balance (the entry stores the
  /// difference). A withdrawal may also be recorded on «نقدینگی».
  Future<GoldCashEntry> addGoldCashEntry({
    required String kind,
    required double amount,
    String? date,
    String note = '',
    bool mirrorWithdrawal = false,
    String opId = '',
  }) async {
    if (!GoldCashKind.all.contains(kind)) {
      throw ArgumentError('نوع ثبت نقد نامعتبر است.');
    }
    if (!amount.isFinite || amount < 0 || (kind != GoldCashKind.adjust && amount < 1)) {
      throw ArgumentError('مبلغ باید بزرگ‌تر از صفر باشد.');
    }
    final cash = goldFundCash;
    final double signed;
    switch (kind) {
      case GoldCashKind.withdraw:
        if (amount > cash + 0.5) {
          throw ArgumentError('مبلغ برداشت از نقد صندوق بیشتر است.');
        }
        signed = -roundToman(amount);
      case GoldCashKind.adjust:
        signed = roundToman(amount - cash);
        if (signed.abs() < 0.5) {
          throw ArgumentError('مانده همین است؛ تغییری ثبت نشد.');
        }
      default:
        signed = roundToman(amount);
    }
    final day = (date != null && date.length >= 10) ? date.substring(0, 10) : todayIso();
    final entry = GoldCashEntry(
      id: 'gc_${newGoldFundOpId()}',
      kind: kind,
      amount: signed,
      date: day,
      note: note.trim(),
      createdAt: nowIso(),
      opId: opId,
      withdrawalMirrored: mirrorWithdrawal && kind == GoldCashKind.withdraw,
    );
    await saveSettings(settings.copyWith(
      goldFundLedger: GoldCashLedger.add(settings.goldFundLedger, entry),
    ));
    if (entry.withdrawalMirrored) {
      await recordWithdrawal(
        amount: signed.abs(),
        note: note.trim().isEmpty ? 'برداشت از صندوق طلا' : 'صندوق طلا · ${note.trim()}',
        createdAt: day == todayIso() ? null : day,
      );
    }
    return entry;
  }

  Future<void> deleteGoldCashEntry(String id) async {
    final next = GoldCashLedger.remove(settings.goldFundLedger, id);
    if (next.length == settings.goldFundLedger.length) return;
    await saveSettings(settings.copyWith(goldFundLedger: next));
  }

  int get _queuedWrites => coreOutbox.length;

  /// Records a fund buy through the normal buy path, tagged `[gf:op]`.
  /// [gapDeposit] (> 0) is first saved as a deposit of the same operation.
  Future<GoldRecordResult> recordGoldBuy({
    int? assetId,
    String? newAssetName,
    required double grams,
    required double pricePerGram,
    required double fee,
    String? date,
    String note = '',
    double gapDeposit = 0,
  }) async {
    if (!(grams > 0) || !(pricePerGram > 0)) {
      throw ArgumentError('وزن و قیمت باید بزرگ‌تر از صفر باشند.');
    }
    if (assetId == null && (newAssetName == null || newAssetName.trim().isEmpty)) {
      throw ArgumentError('دارایی طلا را انتخاب کنید.');
    }
    final op = newGoldFundOpId();
    final day = (date != null && date.length >= 10) ? date.substring(0, 10) : todayIso();
    if (gapDeposit >= 1) {
      await addGoldCashEntry(
        kind: GoldCashKind.deposit,
        amount: gapDeposit,
        date: day,
        note: 'کسری خرید طلا',
        opId: op,
      );
    }
    final before = _queuedWrites;
    try {
      await tradeService.registerBuy(
        assetId: assetId,
        name: assetId == null ? newAssetName!.trim() : null,
        symbol: assetId == null ? 'GOLD' : '',
        quantity: grams,
        buyPrice: pricePerGram,
        buyFee: fee < 0 ? 0 : fee,
        buyDate: day,
        buyNote: withGoldFundTag(note, op),
        currentPrice: assetId == null ? pricePerGram : null,
      );
    } catch (e) {
      return GoldRecordResult(opId: op, total: 1, error: e);
    }
    final queued = _queuedWrites > before ? 1 : 0;
    await _refreshAfterGold();
    return GoldRecordResult(opId: op, total: 1, done: 1, queued: queued);
  }

  /// Closes each lot of [quote] in turn (same `[gf:op]` on every piece).
  /// Stops at the first failure; [onProgress] reports lots done.
  Future<GoldRecordResult> recordGoldSell({
    required GoldSellQuote quote,
    String? date,
    String note = '',
    void Function(int done, int total)? onProgress,
  }) async {
    if (!quote.canRecord) {
      throw ArgumentError('فروش قابل ثبت نیست؛ وزن و لات‌ها را بررسی کنید.');
    }
    final op = newGoldFundOpId();
    final day = (date != null && date.length >= 10) ? date.substring(0, 10) : todayIso();
    final total = quote.takes.length;
    var done = 0, queued = 0;
    final fx = liveUsdt ?? settings.usdtTmnRate;
    for (final t in quote.takes) {
      final before = _queuedWrites;
      try {
        await tradeService.closeTrade(
          tradeId: t.lot.id,
          sellPrice: quote.pricePerGram,
          sellFee: t.sellFeePart,
          quantity: t.closesWholeLot ? null : t.grams,
          sellDate: day,
          sellNote: withGoldFundTag(note, op),
          sellUsdTmn: fx,
        );
      } catch (e) {
        if (done > 0) await _refreshAfterGold();
        return GoldRecordResult(opId: op, total: total, done: done, queued: queued, error: e);
      }
      done++;
      if (_queuedWrites > before) queued++;
      onProgress?.call(done, total);
    }
    await _refreshAfterGold();
    return GoldRecordResult(opId: op, total: total, done: done, queued: queued);
  }

  Future<void> _refreshAfterGold() async {
    try {
      await refresh();
    } catch (_) {}
  }
}
