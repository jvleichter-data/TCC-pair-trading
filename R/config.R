# -*- coding: utf-8 -*-
# Caminhos usados por todos os scripts.
#
# Os scripts devem ser rodados com o diretório de trabalho na pasta R/ do repositório
# (abrir TCC_pair_trading.Rproj no RStudio já faz isso; ou setwd(".../TCC-pair-trading/R")).
#
# Os dados ficam em data_bases/, dentro desta pasta (ver data_bases/README.md): a base de
# preços pronta (base_unificada.csv) e a taxa livre de risco (rf_diario.csv), usada só na
# comparação "bruto × líquido de renda fixa". A base não é gerada aqui.

PASTA_DADOS <- "data_bases"

ARQ_BASE <- file.path(PASTA_DADOS, "base_unificada.csv")   # preços diários 1990–2025
ARQ_RF   <- file.path(PASTA_DADOS, "rf_diario.csv")        # taxa livre de risco diária

# Saídas: cada método grava em <método>/output/ (pares, resultados, imagens), como em
# new_aproach/src. pasta_saida("distance", "pares") → "distance/output/pares" (e cria a pasta).
pasta_saida <- function(metodo, tipo) {
  p <- file.path(metodo, "output", tipo)
  dir.create(p, recursive = TRUE, showWarnings = FALSE)
  p
}
