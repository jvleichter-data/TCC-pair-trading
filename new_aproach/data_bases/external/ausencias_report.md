# Ausências na Base de Extensão S&P 500 (2016–2025)

Atualizado: 2026-05-04

**Cobertura final da extensão: 99.7%+** (a recalcular — FRC recuperado via FRCB)

---

## 1. O que está faltando

### ❌ Irrecuperáveis — sem dados em nenhuma fonte gratuita (3 tickers)

| Ticker | Empresa | Período ausente | Motivo |
|--------|---------|-----------------|--------|
| **VIAC** | ViacomCBS | 2019/S2 → 2021/S2 (5 sem.) | Successor PARA foi privatizado em dez/2024 |
| **CDAY** | Ceridian HCM | 2021/S2 → 2023/S2 (5 sem.) | Renomeou para DAY em fev/2024; DAY não carrega histórico pré-2024 |

### ⚠️ Parciais — dados incompletos para o período de membership (2 tickers)

| Ticker | O que tem | O que falta |
|--------|-----------|-------------|
| **FOX** | 21CF via WIKI (2016-mar/2018) + Fox Corp (2019-03→atual) | 2018/S1 (abr-jun) e 2018/S2 — sem fonte gratuita |
| **FOXA** | Fox Corp (2019-03 → atual) | 21st Century Fox 2016/S1 → 2018/S2 (6 sem.) — WIKI não tem FOXA classe A |

### 🔵 Lacunas legítimas — empresa não existia no período (2 tickers)

| Ticker | Empresa | Período ausente | Motivo |
|--------|---------|-----------------|--------|
| **BHGE** | Baker Hughes GE | 2016/S1 → 2017/S1 | Empresa formada em jul/2017 |
| **DOW** | Dow Inc. | 2016/S1 → 2018/S2 | Spin-off da DowDuPont em mar/2019 |

---

## 2. O que foi recuperado (31 tickers)

| Ticker | Empresa original | Fonte | Ticker usado | Semesters |
|--------|-----------------|-------|--------------|-----------|
| KORS | Michael Kors | Tiingo | KORS | 4 sem. ✅ |
| MMC | Marsh & McLennan | Financial Data API | MMC | 20 sem. ✅ |
| APC | Anadarko Petroleum | Twelve Data | APC | 7 sem. ✅ |
| FBHS | Fortune Brands H&S | Twelve Data | FBHS | 13 sem. ✅ |
| RE | Everest Re Group | Yahoo Finance | EG (ticker atual) | 13 sem. ✅ |
| ANTM | Anthem Inc. | Yahoo Finance | ELV (ticker atual) | 12 sem. ✅ |
| TMK | Torchmark Corp. | Yahoo Finance | GL (ticker atual) | 7 sem. ✅ |
| PKI | PerkinElmer | Yahoo Finance | RVTY (ticker atual) | 14 sem. ✅ |
| PEAK | Healthpeak Properties | Yahoo Finance | DOC (ticker atual) | 9 sem. ✅ |
| WRK | WestRock | Yahoo Finance | SW (ticker atual) | 17 sem. ✅ |
| BLL | Ball Corporation | Yahoo Finance | BALL (ticker atual) | 12 sem. ✅ |
| FB | Facebook Inc. | Yahoo Finance | META (ticker atual) | 12 sem. ✅ |
| LB | L Brands | Yahoo Finance | BBWI (ticker atual) | 11 sem. ✅ |
| STI | SunTrust Banks | Yahoo Finance | TFC (ticker atual) | 7 sem. ✅ |
| ARNC | Arconic Inc. | Yahoo Finance | HWM (ticker atual) | 8 sem. ✅ |
| DISCA | Discovery Inc. | Yahoo Finance | WBD (ticker atual) | 12 sem. ✅ |
| SE | Spectra Energy | Yahoo Finance | ENB (ticker atual) | 2 sem. ✅ |
| HCP | HCP Inc. | Yahoo Finance | DOC (ticker atual) | 7 sem. ✅ |
| IR | Ingersoll-Rand | Yahoo Finance | TT (ticker atual) | 2 sem. ✅ |
| GPS | The Gap Inc. | Yahoo Finance | GAP (ticker atual) | 12 sem. ✅ |
| FRC | First Republic Bank | Yahoo Finance | FRCB (ticker pós-falência) | 8 sem. ✅ |
| MON | Monsanto | NASDAQ Data Link WIKI | MON | 4 sem. ✅ |
| CA | CA Technologies | NASDAQ Data Link WIKI | CA | 5 sem. ✅ |
| EMC | EMC Corporation | NASDAQ Data Link WIKI | EMC | 1 sem. ✅ |
| FTR | Frontier Communications | NASDAQ Data Link WIKI | FTR | 2 sem. ✅ |
| DO | Diamond Offshore | NASDAQ Data Link WIKI | DO | 1 sem. ✅ |
| TE | TECO Energy | NASDAQ Data Link WIKI | TE | 1 sem. ✅ |
| DNB | Dun & Bradstreet | NASDAQ Data Link WIKI | DNB | 2 sem. ✅ |
| MNK | Mallinckrodt | NASDAQ Data Link WIKI | MNK | 3 sem. ✅ |
| ENDP | Endo International | NASDAQ Data Link WIKI | ENDP | 2 sem. ✅ |
| CBS | CBS Corporation | NASDAQ Data Link WIKI | CBS | 5 de 7 sem. ✅* |

> \* CBS: WIKI cobre 2016-2018 (5 semestres). Os 2 semestres de 2018/S1-2019/S1 permanecem ausentes.

---

## 3. Fontes testadas

| Fonte | Resultado |
|-------|-----------|
| **Yahoo Finance** (yfinance API) | ✅ Principal fonte — funciona para tickers renomeados via ticker atual |
| **Tiingo** (free tier) | ✅ Parcial — recuperou KORS; maioria dos históricos indisponível |
| **Twelve Data** (free tier) | ✅ Parcial — APC, FBHS; maioria paywall |
| **Financial Data API** (financialdata.net) | ✅ Parcial — funcionou para MMC |
| **NASDAQ Data Link WIKI** (data.nasdaq.com) | ✅ 10 tickers — endpoint `datatables/WIKI/PRICES` |
| **Stooq** | ❌ Requer API key via captcha; histórico de delistados ausente |
| **Macrotrends** | ❌ Cloudflare 403 — bloqueia requisições automatizadas |
| **FMP** (Financial Modeling Prep) | ❌ Endpoint legacy bloqueado para contas novas |
| **Alpha Vantage** | ❌ outputsize=full requer plano pago |
| **EODHD** | ❌ Retornou vazio para todos os tickers testados |
| **NASDAQ Data Link** (datasets endpoint) | ❌ Endpoint descontinuado (403) |
