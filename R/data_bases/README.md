# Dados

Coloque nesta pasta os dois arquivos que os scripts leem:

| Arquivo | Conteúdo | Usado em |
| --- | --- | --- |
| `base_unificada.csv` | Preços diários das ações do S&P 500, 1990–2025 (~55 MB) | Todos os scripts |
| `rf_diario.csv` | Taxa livre de risco diária | Só na comparação "bruto × líquido de renda fixa" |

O `rf_diario.csv` já vem no repositório. O `base_unificada.csv` não, por causa do tamanho (está
no `.gitignore`), e é enviado à parte. Os dois são cópias dos arquivos de
`new_aproach/data_bases/`, onde a base é gerada pelo notebook `pipeline_base.ipynb`.

Os nomes dos arquivos precisam ser exatamente esses. Para ler os dados de outra pasta, mude
`PASTA_DADOS` em `../config.R`.
