"""
validate_price_adjustment.py
============================
Verifica qual tipo de ajuste de preço a base do professor usa,
comparando com os dois tipos disponíveis no Yahoo Finance:

  - Adj Close (auto_adjust=False): ajusta splits + dividendos retroativamente
  - Close     (auto_adjust=True) : mesmo ajuste, coluna renomeada

Roda este script antes de juntar as bases.
"""

import pandas as pd
import numpy as np
import yfinance as yf
from pathlib import Path

BASE_DIR = Path(r"C:\Users\jvlei\Desktop\TCC-pair-trading\data_bases")
PATH_DB      = BASE_DIR / "Pt_formatted.csv"
PATH_PERIODS = BASE_DIR / "Periods.csv"

# ── 1. Reconstruir mapa linha → data aproximada ───────────────────────────────
# Usamos bdate_range como proxy (±1–3 dias vs calendário NYSE real)

periods_raw = pd.read_csv(PATH_PERIODS, header=None)
periods_raw.columns = ["dias_sem", "nan1", "nan2", "dias_ano"]

datas = []
for i, row in periods_raw.iterrows():
    n = int(row["dias_sem"])
    if i == 0:   ini = "1990-07-02"  # primeiro dia útil de jul/1990
    else:
        ano = 1990 + (i // 2)
        ini = f"{ano}-01-02" if i % 2 == 1 else f"{ano}-07-02"
    dias_uteis = pd.bdate_range(start=ini, periods=n)
    datas.extend(dias_uteis)

# Montar série de datas
db = pd.read_csv(PATH_DB)
n_linhas = min(len(db), len(datas))
# Truncate both to match lengths
db = db.iloc[:n_linhas]
db.index = pd.DatetimeIndex(datas[:n_linhas])

# ── 2. Escolher tickers e janela de comparação ────────────────────────────────
# Usamos os últimos 60 pregões da base do professor (~3 meses de 2005)
# São empresas estáveis com histórico longo no Yahoo

TICKERS_VALIDACAO = {
    "MSFT":  "Microsoft — muitos splits históricos, fácil de verificar",
    "KO":    "Coca-Cola  — alta pay dividendos, bom para testar ajuste",
    "JNJ":   "J&J        — splits em 96 e 99, dividendos estáveis",
    "XOM":   "ExxonMobil — poucos splits, bom controle",
    "GE":    "GE         — split em 2000, história complexa",
}

N_DIAS_COMP = 60   # quantos pregões comparar (janela no final da base)
TOLERANCIA  = 0.02 # diferença máxima aceitável (2%) entre professor e Yahoo

# ── 3. Baixar dados do Yahoo e comparar ──────────────────────────────────────

print("=" * 65)
print("VALIDAÇÃO DE AJUSTE DE PREÇOS")
print("Base do professor  ×  Yahoo Finance (Adj Close)")
print("=" * 65)

resultados = []

for ticker, descricao in TICKERS_VALIDACAO.items():
    if ticker not in db.columns:
        print(f"\n{ticker}: não encontrado na base do professor")
        continue

    # Série do professor (últimos N_DIAS_COMP valores não-nulos)
    serie_prof = db[ticker].dropna().tail(N_DIAS_COMP)
    if len(serie_prof) < 10:
        print(f"\n{ticker}: dados insuficientes na base do professor")
        continue

    data_inicio = serie_prof.index[0].strftime("%Y-%m-%d")
    data_fim    = serie_prof.index[-1].strftime("%Y-%m-%d")

    print(f"\n{'─'*65}")
    print(f"{ticker}  —  {descricao}")
    print(f"Janela: {data_inicio} → {data_fim}  ({len(serie_prof)} dias)")

    try:
        # Baixar do Yahoo com Adj Close (ajuste splits + dividendos)
        raw = yf.download(
            ticker,
            start=data_inicio,
            end=(pd.to_datetime(data_fim) + pd.Timedelta(days=5)).strftime("%Y-%m-%d"),
            auto_adjust=False,
            progress=False,
        )
        if hasattr(raw.columns, "levels"):
            raw.columns = raw.columns.get_level_values(0)

        if raw is None or len(raw) == 0:
            print(f"  Yahoo: sem dados")
            continue

        serie_yahoo_adj   = raw["Adj Close"]
        serie_yahoo_close = raw["Close"]

        # Alinhar pelos índices comuns
        idx_comum = serie_prof.index.intersection(serie_yahoo_adj.index)
        if len(idx_comum) < 5:
            print(f"  Apenas {len(idx_comum)} datas em comum — ajuste o período")
            continue

        prof  = serie_prof.loc[idx_comum]
        y_adj = serie_yahoo_adj.loc[idx_comum]
        y_raw = serie_yahoo_close.loc[idx_comum]

        # Calcular ratios e correlações
        ratio_adj   = (prof / y_adj).replace([np.inf, -np.inf], np.nan).dropna()
        ratio_raw   = (prof / y_raw).replace([np.inf, -np.inf], np.nan).dropna()
        corr_adj    = prof.corr(y_adj)
        corr_raw    = prof.corr(y_raw)

        print(f"  Datas em comum: {len(idx_comum)}")
        print()
        print(f"  Comparação com Adj Close (splits + dividendos):")
        print(f"    Ratio médio: {ratio_adj.mean():.4f}  (1.0000 = perfeito)")
        print(f"    Ratio std:   {ratio_adj.std():.4f}   (0 = perfeitamente proporcional)")
        print(f"    Correlação:  {corr_adj:.6f}")

        print(f"\n  Comparação com Close bruto (sem ajuste):")
        print(f"    Ratio médio: {ratio_raw.mean():.4f}")
        print(f"    Ratio std:   {ratio_raw.std():.4f}")
        print(f"    Correlação:  {corr_raw:.6f}")

        # Amostra dos valores
        print(f"\n  Amostra dos últimos 5 dias:")
        amostra = pd.DataFrame({
            "Professor": prof.tail(5).round(4),
            "Yahoo_AdjClose": y_adj.tail(5).round(4),
            "Ratio": (prof / y_adj).tail(5).round(4),
        })
        print(amostra.to_string())

        # Diagnóstico
        std_adj = ratio_adj.std()
        std_raw = ratio_raw.std()

        if std_adj < TOLERANCIA and corr_adj > 0.999:
            diagnostico = "✅ MATCH — base usa Adj Close (splits + dividendos)"
            tipo = "adj_close"
        elif std_raw < TOLERANCIA and corr_raw > 0.999:
            diagnostico = "✅ MATCH — base usa Close bruto (sem ajuste de dividendos)"
            tipo = "close_raw"
        elif corr_adj > corr_raw:
            diagnostico = f"⚠️  Mais próximo de Adj Close (ratio std={std_adj:.4f}) — possível CRSP"
            tipo = "approx_adj"
        else:
            diagnostico = f"⚠️  Mais próximo de Close raw (ratio std={std_raw:.4f})"
            tipo = "approx_raw"

        print(f"\n  {diagnostico}")

        resultados.append({
            "ticker":    ticker,
            "tipo":      tipo,
            "ratio_adj_mean": round(ratio_adj.mean(), 4),
            "ratio_adj_std":  round(ratio_adj.std(), 4),
            "corr_adj":  round(corr_adj, 6),
            "corr_raw":  round(corr_raw, 6),
            "n_dias":    len(idx_comum),
        })

    except Exception as e:
        print(f"  ERRO: {e}")

# ── 4. Conclusão geral ────────────────────────────────────────────────────────

print(f"\n{'='*65}")
print("CONCLUSÃO GERAL")
print(f"{'='*65}")

if resultados:
    df_res = pd.DataFrame(resultados)
    print()
    print(df_res[["ticker", "tipo", "ratio_adj_mean", "ratio_adj_std", "corr_adj"]].to_string(index=False))
    print()

    # Voto majoritário
    tipos = df_res["tipo"].value_counts()
    tipo_dominante = tipos.index[0]

    if "adj_close" in tipo_dominante or "approx_adj" in tipo_dominante:
        print("→ A base do professor usa preços AJUSTADOS por splits E dividendos")
        print("  (equivalente ao Adj Close do Yahoo Finance)")
        print()
        print("  ✅ Para a extensão (2015–2025), use yfinance com auto_adjust=True")
        print("     ou auto_adjust=False e a coluna 'Adj Close'")
        print("     Ambos produzem o mesmo resultado.")
    elif "close_raw" in tipo_dominante:
        print("→ A base do professor usa preços SEM ajuste de dividendos")
        print("  (apenas ajuste por splits)")
        print()
        print("  ✅ Para a extensão, use yfinance com auto_adjust=False")
        print("     e a coluna 'Close' (não 'Adj Close')")

print()
print("Nota: pequenas divergências (ratio ≠ 1.0000) são normais pois")
print("o Yahoo recalcula os fatores de ajuste retroativamente toda vez")
print("que ocorre um novo split ou dividendo.")
