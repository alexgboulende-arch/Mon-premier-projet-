
/*
 * Alex Trading Lab — Moteur d'analyse technique
 * Version 1.0 — Mode analyse uniquement
 *
 * Aucune connexion au marché et aucun ordre automatique
 * dans cette version.
 */

(function () {
  "use strict";

  function ema(values, period) {
    if (!Array.isArray(values) || values.length < period) {
      return null;
    }

    const alpha = 2 / (period + 1);
    let result = values
      .slice(0, period)
      .reduce((sum, value) => sum + value, 0) / period;

    for (let i = period; i < values.length; i++) {
      result = values[i] * alpha + result * (1 - alpha);
    }

    return result;
  }

  function rsi(closes, period = 14) {
    if (!Array.isArray(closes) || closes.length <= period) {
      return null;
    }

    let gains = 0;
    let losses = 0;

    for (let i = 1; i <= period; i++) {
      const change = closes[i] - closes[i - 1];
      gains += Math.max(change, 0);
      losses += Math.max(-change, 0);
    }

    let averageGain = gains / period;
    let averageLoss = losses / period;

    for (let i = period + 1; i < closes.length; i++) {
      const change = closes[i] - closes[i - 1];
      averageGain =
        (averageGain * (period - 1) + Math.max(change, 0)) /
        period;
      averageLoss =
        (averageLoss * (period - 1) + Math.max(-change, 0)) /
        period;
    }

    if (averageLoss === 0) {
      return averageGain === 0 ? 50 : 100;
    }

    const relativeStrength = averageGain / averageLoss;
    return 100 - 100 / (1 + relativeStrength);
  }

  function atr(candles, period = 14) {
    if (!Array.isArray(candles) || candles.length < period) {
      return null;
    }

    const trueRanges = candles.map((candle, index) => {
      if (
        !Number.isFinite(candle.high) ||
        !Number.isFinite(candle.low) ||
        !Number.isFinite(candle.close)
      ) {
        return null;
      }

      if (candle.high < candle.low) {
        return null;
      }

      if (index === 0) {
        return candle.high - candle.low;
      }

      const previousClose = candles[index - 1].close;

      return Math.max(
        candle.high - candle.low,
        Math.abs(candle.high - previousClose),
        Math.abs(candle.low - previousClose)
      );
    });

    if (trueRanges.some(value => value === null)) {
      return null;
    }

    let result =
      trueRanges.slice(0, period).reduce((sum, value) => sum + value, 0) /
      period;

    for (let i = period; i < trueRanges.length; i++) {
      result =
        (result * (period - 1) + trueRanges[i]) / period;
    }

    return result;
  }

  function analyse(candles) {
    if (!Array.isArray(candles) || candles.length < 200) {
      return {
        statut: "DONNEES_INSUFFISANTES",
        message: "Il faut au moins 200 bougies pour cette analyse.",
        tendance: null,
        ema200: null,
        rsi14: null,
        atr14: null,
        signal: "AUCUN"
      };
    }

    const closes = candles.map(candle => candle.close);

    if (
      closes.some(value => !Number.isFinite(value)) ||
      candles.some(candle =>
        !Number.isFinite(candle.high) ||
        !Number.isFinite(candle.low) ||
        candle.high < candle.low
      )
    ) {
      return {
        statut: "DONNEES_INVALIDES",
        message: "Vérifie les prix transmis au moteur d'analyse.",
        signal: "AUCUN"
      };
    }

    const currentPrice = closes[closes.length - 1];
    const ema200 = ema(closes, 200);
    const rsi14 = rsi(closes, 14);
    const atr14 = atr(candles, 14);

    let tendance = "NEUTRE";

    if (currentPrice > ema200) {
      tendance = "HAUSSIERE";
    } else if (currentPrice < ema200) {
      tendance = "BAISSIERE";
    }

    let signal = "AUCUN";

    if (
      tendance === "HAUSSIERE" &&
      rsi14 !== null &&
      rsi14 >= 50 &&
      rsi14 < 70
    ) {
      signal = signal = "BUY_SETUP"; 
    } else if (
      tendance === "BAISSIERE" &&
      rsi14 !== null &&
      rsi14 <= 50 &&
      rsi14 > 30
    ) {
      signal = signal = "SELL_SETUP";
    }

    return {
      statut: "OK",
      prix: currentPrice,
      tendance: tendance,
      ema200: ema200,
      rsi14: rsi14,
      atr14: atr14,
      signal: signal,
      avertissement:
        "Indication technique uniquement. Ce résultat ne garantit pas un gain."
    };
  }

  window.AlexTradingLabAnalysis = {
    ema: ema,
    rsi: rsi,
    atr: atr,
    analyse: analyse
  };
})();
