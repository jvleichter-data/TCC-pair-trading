Descrição dos Dados

Periods.csv

Coluna 1: número de dias por semestre, no período de 1990/2 até 2015/1.
Coluna 4: número de dias por ano, considerando janelas móveis de 12 meses.

Rm.csv (Market Return)

Retorno do mercado (retorno do índice S&P 500).

Rf (Risk-Free Rate)

Retorno do ativo livre de risco (aproximado pelo T-bill de 3 meses).
Veja melhor no artigo de minha autoria (Pairs Trading Based on Mixed Copulas).

Pt (Prices)

Preços de fechamento ajustados das ações que compuseram o índice ao longo do período.
Cada ativo aparece apenas nos intervalos em que efetivamente integrou o índice.

Rt (Returns)

Retornos dos preços Pt.

ticker

Lista de todas as ações que fizeram parte do índice em algum momento entre 1990/2 e 2015/1.

ticker_sem

Lista das ações que compunham o índice em cada semestre específico.