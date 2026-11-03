import 'package:vyapari_core/vyapari_core.dart';

import 'messages.dart';

/// The client intent that asks the server for [a], or `null` for actions
/// only the server may issue (system actions, lobby joins).
ClientMessage? intentFor(GameAction a) => switch (a) {
      Roll() => const SimpleIntent('roll'),
      Buy() => const SimpleIntent('buy'),
      DeclineBuy() => const SimpleIntent('decline'),
      Bid() => BidMsg(a.amount),
      PayJailFine() => const SimpleIntent('pay_jail'),
      UseJailCard() => const SimpleIntent('use_card'),
      EndTurn() => const SimpleIntent('end_turn'),
      PayDebt() => const SimpleIntent('pay_debt'),
      DeclareBankruptcy() => const SimpleIntent('declare_bankruptcy'),
      Build() => TileMsg('build', a.tileIndex),
      SellBuilding() => TileMsg('sell_building', a.tileIndex),
      Mortgage() => TileMsg('mortgage', a.tileIndex),
      Unmortgage() => TileMsg('unmortgage', a.tileIndex),
      ProposeTrade() => TradeProposeMsg(to: a.to, give: a.give, get: a.get),
      AcceptTrade() => TradeAnswerMsg('trade_accept', a.tradeId),
      RejectTrade() => TradeAnswerMsg('trade_reject', a.tradeId),
      CancelTrade() => TradeAnswerMsg('trade_cancel', a.tradeId),
      CounterTrade() => TradeCounterMsg(a.tradeId, give: a.give, get: a.get),
      SetReady() => ReadyMsg(ready: a.ready),
      SetRules() => SetRulesMsg(a.rules),
      Kick() => PlayerTargetMsg('kick', a.targetId),
      StartGame() => const SimpleIntent('start'),
      LeaveGame() => const SimpleIntent('leave'),
      AddBot() => AddBotMsg(level: a.level),
      JoinGame() ||
      CloseAuction() ||
      SetConnected() ||
      ReplaceWithBot() ||
      EndGameByLimit() =>
        null,
    };
