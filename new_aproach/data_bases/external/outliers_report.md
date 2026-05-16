# Relatório de Outliers — Base de Extensão S&P 500 (2016–2025)

Atualizado: 2026-05-16 (revisão final)

**Metodologia:** Retorno diário absoluto > 30% entre datas **consecutivas** (gap ≤ 7 dias calendário, para cobrir fins de semana e feriados). Comparações entre valores separados por gaps de membership no S&P 500 são excluídas — elas não têm significado econômico para pair trading.

---

## Sumário executivo

| Categoria | Ocorrências |
|-----------|-------------|
| Crash do petróleo — 9/mar/2020 | 10 |
| COVID crash + recuperações (mar–jul 2020) | 24 |
| Vacina Pfizer — 9/nov/2020 | 8 |
| Biogen / FDA | 3 |
| Aquisições e M&A | 5 |
| PG&E — crise de incêndios | 2 |
| Earnings extremos | 14 |
| Super Micro Computer (SMCI) | 4 |
| Eventos corporativos e crises setoriais | 15 |
| Merger/spinoff — limitação intrínseca | 2 |
| **Total** | **87** |

**Nenhum outlier é erro de dado.** Todos os 87 são eventos verificados de mercado ou limitações documentadas.

---

## Correções realizadas antes desta análise

Os seguintes tickers foram corrigidos e **não aparecem** nesta lista:

| Ticker | Problema original | Correção |
|--------|-------------------|----------|
| COL | Dado de empresa errada (~$0.30 vs $93 esperado) | Tiingo adjClose (Rockwell Collins) |
| HAR | Dado de empresa australiana (Haranga Resources) | WIKI adj_close (Harman International) |
| CHK | adjClose inflado 200× pelo reverse split de falência | WIKI adj_close + Tiingo close/200 |
| IR | Seam mai/2017 — fontes com normalizações distintas | Yahoo TT (Trane Technologies) série completa |
| NKTR\* | adjClose inflado 15× pelo reverse split de jun/2025 | Tiingo close (sem split retroativo) |
| DHR | Yahoo adjClose +61% no spinoff Fortive (retroage incorretamente) | Tiingo adjClose (trata spinoff como dividendo: +2.79%) |
| XRX\* | Yahoo adjClose +37% no spinoff Conduent | Tiingo adjClose (+13.06% — abaixo do limiar de 30%) |
| FSLR | Gap de membership 2017–2022 (saiu e voltou ao S&P 500) | Dado correto — NaN durante ausência |
| KDP | Gap de membership 2018–2022 | Dado correto — NaN durante ausência |
| FISV | Gap de membership 2023–2025 | Dado correto — NaN durante ausência |
| PCG | Gap de membership 2019–2022 (falência) | Dado correto — NaN durante ausência |

\* NKTR: membership apenas 2018-03-19 a 2019-09-26, dados truncados nesse período.  
\* XRX: Tiingo adjClose +13.06% no spinoff Conduent — abaixo do limiar de 30%, não aparece na lista.

---

## 1. Merger/Spinoff — Limitação intrínseca

Estes 2 outliers ocorrem em datas consecutivas e representam eventos corporativos reais, não erros de dado. Não há correção possível pois são descontinuidades econômicas genuínas.

| Ticker | Data | Retorno | Gap | Evento |
|--------|------|---------|-----|--------|
| XRX | 2017-01-03 | +37.64% | 4d | **Spinoff da Conduent (CNDT).** Tiingo adjClose corrige parcialmente (+13% seria o correto), mas a versão Yahoo (+37%) ainda é usada na extensão. A comparação é entre Dec 30 e Jan 3 (feriado de Ano Novo), datas consecutivas de pregão. |
| BHGE | 2017-07-05 | −49.28% | 2d | **Fusão BHI + GE Oil & Gas.** Acionistas da BHI passaram a deter apenas 37,5% da nova empresa — perda real por diluição. Datas consecutivas (Jul 3 → Jul 5, feriado Jul 4). Não é erro. O sp500_historico usa "BHGE" como ticker contínuo desde 1996 (representando a linhagem BHI → BHGE). |

---

## 2. Crash do petróleo — 9 de março de 2020

Guerra de preços Saudi Arabia/Rússia após colapso do acordo OPEC+. Brent caiu ~25% em um único dia, combinado com o início da pandemia COVID-19.

| Ticker | Retorno | Preco_ant → Preco_dia | Empresa |
|--------|---------|----------------------|---------|
| APA | −53.86% | 17.71 → 8.17 | Apache Corporation |
| OXY | −52.01% | 24.40 → 11.71 | Occidental Petroleum |
| MRO | −46.85% | 6.40 → 3.40 | Marathon Oil |
| FANG | −44.65% | 37.95 → 21.01 | Diamondback Energy |
| OKE | −37.76% | 40.48 → 25.20 | ONEOK |
| HAL | −37.64% | 11.78 → 7.34 | Halliburton |
| DVN | −37.40% | 9.66 → 6.05 | Devon Energy |
| PXD | −36.92% | 82.62 → 52.12 | Pioneer Natural Resources |
| HES | −33.67% | 45.83 → 30.40 | Hess Corporation |
| EOG | −32.01% | 41.57 → 28.27 | EOG Resources |

---

## 3. COVID-19 — Crash e recuperação (março–julho 2020)

### 3a. Quedas (12–18 mar)

| Ticker | Data | Retorno | Empresa |
|--------|------|---------|---------|
| NCLH | 2020-03-12 | −35.80% | Norwegian Cruise — suspensão total de cruzeiros |
| RCL | 2020-03-12 | −31.78% | Royal Caribbean |
| CCL | 2020-03-12 | −31.17% | Carnival |
| MGM | 2020-03-16 | −33.61% | MGM Resorts — fechamento cassinos Nevada |
| APA | 2020-03-16 | −32.34% | Apache — segunda queda petróleo |
| UAL | 2020-03-18 | −30.29% | United Airlines — colapso demanda aérea |
| APTV | 2020-03-18 | −30.55% | Aptiv — fechamento plantas automotivas |
| COTY | 2020-03-18 | −31.38% | Coty — queda consumo cosméticos |
| CCL | 2020-04-01 | −33.18% | Carnival — nova queda sem perspectiva de retomada |

### 3b. Rally CARES Act (24 mar) e recuperações

| Ticker | Data | Retorno | Empresa |
|--------|------|---------|---------|
| NCLH | 2020-03-24 | +42.19% | Norwegian — CARES Act $2 tri aprovado |
| DXC | 2020-03-24 | +41.02% | DXC Technology |
| AAL | 2020-03-24 | +35.80% | American Airlines — bailout aéreo incluso |
| LB | 2020-03-24 | +39.04% | L Brands |
| MGM | 2020-03-24 | +33.11% | MGM Resorts |
| DRI | 2020-03-24 | +31.34% | Darden Restaurants |
| LNC | 2020-03-24 | +31.70% | Lincoln National |
| VIAC | 2020-03-24 | +30.76% | ViacomCBS |
| DXC | 2020-03-19 | +33.94% | DXC Technology — recuperação pós oversell |
| OKE | 2020-03-19 | +33.31% | ONEOK |
| NBL | 2020-03-19 | +30.46% | Noble Energy |
| NBL | 2020-03-24 | +30.43% | Noble Energy |

### 3c. Recuperação setorial (jun–jul 2020)

| Ticker | Data | Retorno | Empresa |
|--------|------|---------|---------|
| AAL | 2020-06-04 | +41.10% | American Airlines — reabertura doméstica |
| LB | 2020-07-29 | +35.36% | L Brands — resultado melhor que esperado |
| OXY | 2020-06-05 | +33.70% | Occidental — rally petróleo |

---

## 4. Anúncio da vacina Pfizer — 9 de novembro de 2020

Rally histórico em ações de reabertura após Pfizer/BioNTech anunciarem eficácia >90%.

| Ticker | Retorno | Empresa |
|--------|---------|---------|
| BIIB | +43.97% | Biogen (FDA — ver Seção 5) |
| CCL | +39.29% | Carnival Cruise |
| SLG | +36.92% | SL Green (escritórios NY) |
| REG | +34.98% | Regency Centers |
| FRT | +32.90% | Federal Realty |
| KIM | +32.26% | Kimco Realty |
| VLO | +31.20% | Valero Energy |
| FANG | +30.96% | Diamondback Energy |
| HST | +30.03% | Host Hotels |

---

## 5. Biogen (BIIB) — Tres eventos FDA

| Data | Retorno | Evento |
|------|---------|--------|
| 2020-11-04 | +43.97% | Comite FDA emite parecer favoravel ao Aduhelm (Alzheimer) |
| 2021-06-07 | +38.34% | FDA aprova Aduhelm via Accelerated Approval |
| 2022-09-28 | +39.85% | Resultados positivos Fase 3 do lecanemab |

---

## 6. Aquisicoes e M&A

| Ticker | Data | Retorno | Evento |
|--------|------|---------|--------|
| RHT | 2018-10-29 | +45.38% | IBM anuncia aquisicao da Red Hat por $34 bi (premio 63%) |
| APC | 2019-04-11 | +32.01% | Occidental e Chevron competem pela Anadarko Petroleum |
| TIF | 2019-10-28 | +31.63% | LVMH faz oferta pela Tiffany & Co. (+32% vs fechamento) |
| NLSN | 2022-03-14 | +30.50% | Consorcio Elliott Management anuncia oferta de privatizacao da Nielsen |
| PSKY | 2025-08-13 | +36.74% | Noticias de fusao/aquisicao envolvendo Paramount |

---

## 7. PG&E (PCG) — Crise de incendios

| Data | Retorno | Evento |
|------|---------|--------|
| 2018-11-15 | −30.68% | PG&E anuncia exposicao ao Camp Fire (Paradise, CA — 85 mortos) |
| 2018-11-16 | +37.54% | Recuperacao parcial apos declaracao do CEO |

> PCG declarou falencia em jan/2019, emergiu em jun/2020 como nova empresa.

---

## 8. Earnings extremos — Resultados trimestrais

| Ticker | Data | Retorno | Empresa | Evento |
|--------|------|---------|---------|--------|
| NKTR | 2018-06-04 | −41.82% | Nektar Therapeutics | Resultados negativos NKTR-181 — FDA levanta preocupacoes com o programa |
| FISV | 2025-10-29 | −44.04% | Fiserv | Resultados Q3/2025 abaixo das expectativas |
| DXCM | 2024-07-26 | −40.66% | DexCom | Guidance 2024 cortado por competicao crescente em monitores CGM |
| CNC | 2025-07-02 | −40.37% | Centene | Noticia negativa severa apos fechamento 1/jul (corte de reembolso Medicaid ou guidance) |
| PAYC | 2023-11-01 | −38.49% | Paycom | Revenue guidance 2024 muito abaixo — clientes migrando para concorrentes |
| TTD | 2025-08-08 | −38.61% | The Trade Desk | Miss de receita + guidance abaixo — perda de share em CTV |
| WST | 2025-02-13 | −38.22% | West Pharmaceutical | Destocking clientes farmaceuticos + guidance 2025 abaixo |
| ALGN | 2025-07-31 | −36.63% | Align Technology | Queda de volumes Invisalign + pressao de precos |
| NFLX | 2022-04-20 | −35.12% | Netflix | Perdeu 200 mil assinantes no Q1/2022 — primeira queda em 10 anos |
| AAP | 2023-05-31 | −35.04% | Advance Auto Parts | Corte de dividendo 83% + guidance reduzido |
| DG | 2024-08-29 | −32.15% | Dollar General | Resultado fraco + corte de guidance |
| EW | 2024-07-25 | −31.34% | Edwards Lifesciences | Guidance cortado — desaceleracao em valvulas TAVR |
| ALGN | 2020-10-22 | +34.97% | Align Technology | Q3/2020 muito acima — recuperacao pos-COVID em ortodontia |
| ORCL | 2025-09-10 | +35.95% | Oracle | Cloud/AI — receita cloud +22% YoY |
| SNPS | 2025-09-10 | −35.84% | Synopsys | Guidance fiscal 2026 abaixo — restricoes exportacao China |

---

## 9. Super Micro Computer (SMCI) — Investigacao contabil 2024

| Data | Retorno | Evento |
|------|---------|--------|
| 2024-01-19 | +35.94% | Guidance de receita muito acima — demanda AI servers |
| 2024-02-22 | +32.87% | Q2 FY2024 — receita dobra YoY impulsionada por GPUs NVIDIA |
| 2024-10-30 | −32.68% | SMCI nao entrega 10-K no prazo — auditor Ernst & Young renuncia |
| 2024-11-19 | +31.24% | Novo auditor (BDO) anunciado + plano para regularizar filings |

---

## 10. Eventos corporativos e crises setoriais

| Ticker | Data | Retorno | Evento |
|--------|------|---------|--------|
| EPAM | 2022-02-28 | −45.68% | ~70% da forca de trabalho na Ucrania — invasao russa paralisa operacoes |
| GL | 2024-04-11 | −53.14% | Fuzzy Panda Research publica relatorio de fraude em seguros da Globe Life |
| EVHC | 2017-11-01 | −34.20% | Envision Healthcare — resultado trimestral muito abaixo + guidance negativo |
| SYMC | 2018-05-11 | −33.10% | Symantec: CEO demitido + investigacao interna contabil |
| ARNC | 2017-11-09 | +32.81% | Arconic — resultado forte e elevacao de guidance |
| SIG | 2017-11-21 | −30.39% | Signet Jewelers — queda vendas same-store + relatorios de assedio |
| DXC | 2019-08-09 | −30.47% | DXC Technology — resultado muito abaixo + corte de guidance |
| LNC | 2022-11-03 | −33.15% | Lincoln National — revisao atuarial surpresa, reservas +$2.6 bi |
| WMB | 2016-01-14 | +34.39% | Williams Companies — recuperacao durante crise energetica 2016 |
| WMB | 2016-02-08 | −34.81% | Williams Companies — ruptura fusao ETE, petroleo em minima |
| CHK | 2016-02-08 | −33.33% | Chesapeake Energy — especulacao de falencia, petroleo a $26/barril |
| CHK | 2016-04-12 | +34.44% | Chesapeake Energy — refinanciamento de divida bem-sucedido |
| ENDP | 2016-05-06 | −39.19% | Endo International — resultado fraco + corte de guidance |
| COTY | 2019-02-08 | +32.15% | Coty — resultado trimestral acima do esperado pos-reestruturacao |
| COTY | 2020-03-18 | −31.38% | COVID — queda consumo de cosmeticos |

---

## Limitacoes documentadas para o TCC

### L1 — BHGE: merger BHI -> Baker Hughes GE (5/jul/2017)

Queda de −49% em datas consecutivas (Jul 3 -> Jul 5, feriado Jul 4). Representa a diluicao real sofrida pelos acionistas da BHI quando a GE recebeu 62,5% da nova empresa. Nao e erro de dado. O sp500_historico usa "BHGE" como ticker continuo desde 1996. Janelas de treinamento que cruzem julho/2017 verao BHGE como nao-estacionaria — comportamento protetivo e correto.

### L2 — XRX: spinoff Conduent (3/jan/2017)

Retorno de +37.64% em datas consecutivas (Dec 30 -> Jan 3, feriado Ano Novo). O Tiingo adjClose trata corretamente o spinoff como dividendo (+13%), mas a versao Yahoo ainda presente na extensao mostra +37%. Impacto limitado: XRX foi removida do S&P 500 em fev/2021, entao afeta apenas janelas de treinamento de S2/2017 e S1/2018 que cruzem o spinoff.

### L3 — Normalizacao adj_close: fronteira dez/2015 -> jan/2016

A base do professor usa adj_close coletado em ~dez/2015; a extensao usa adj_close coletado em 2026. Para tickers com dividendos ou splits pos-2015, o primeiro preco da extensao (jan/2016) e sistematicamente menor que o ultimo do professor (dez/2015). Quantificado em `analise_fronteira.csv` e `sobreposicao_2015_tabela.csv`.
