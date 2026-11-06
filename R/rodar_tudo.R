# -*- coding: utf-8 -*-
# Roda os scripts em ordem. Cada um roda num ambiente próprio, para que os parâmetros de um
# (por exemplo, PASSO_MESES = 6 na distância e 1 na cointegração) não vazem para o outro.
# A base de preços é lida uma vez só e reaproveitada.
#
# Rodar com o diretório de trabalho na pasta R/ (a raiz desta versão):
#   Rscript rodar_tudo.R            (terminal)
#   source("rodar_tudo.R")          (console do RStudio)
#
# Dependências entre scripts:
#   distance:      pairs_formation → pairs_trading → pairs_trading_dinamico
#   cointegration: pairs_formation_coint → pairs_trading_coint → pairs_trading_coint_dinamico
#   nonparametric: valor_critico_np → pairs_formation_np_propria → pairs_trading_np
#                  (pairs_trading_np compara com cointegration/pairs_trading_coint)
#                  pairs_formation_np e diagnostico_wang_phillips são diagnóstico; o segundo
#                  usa o primeiro e os resultados da cointegração.

if (!file.exists("funcoes/comum.R"))
  stop("Defina o diretório de trabalho para a pasta R/ do repositório (setwd).")

RODAR_DISTANCIA       <- TRUE
RODAR_COINTEGRACAO    <- TRUE
RODAR_NP              <- TRUE    # ⏱️ ~1,5 h (quase tudo na formação própria)
RODAR_DIAGNOSTICOS_NP <- FALSE   # pairs_formation_np e diagnostico_wang_phillips; ⏱️ mais ~1 h

SCRIPTS <- c(
  if (RODAR_DISTANCIA) c("distance/pairs_formation.R",
                         "distance/pairs_trading.R",
                         "distance/pairs_trading_dinamico.R"),
  if (RODAR_COINTEGRACAO) c("cointegration/pairs_formation_coint.R",       # ⏱️ alguns minutos
                            "cointegration/pairs_trading_coint.R",
                            "cointegration/pairs_trading_coint_dinamico.R"),
  if (RODAR_NP) c("nonparametric/valor_critico_np.R",
                  "nonparametric/pairs_formation_np_propria.R",
                  if (RODAR_DIAGNOSTICOS_NP) "nonparametric/pairs_formation_np.R",
                  "nonparametric/pairs_trading_np.R",
                  if (RODAR_DIAGNOSTICOS_NP) "nonparametric/diagnostico_wang_phillips.R")
)

for (s in SCRIPTS) {
  cat("\n", strrep("#", 88), "\n#  ", s, "\n", strrep("#", 88), "\n\n", sep = "")
  t0 <- Sys.time()
  source(s, local = new.env(), encoding = "UTF-8")
  cat(sprintf("\n[%s concluído em %.0fs]\n", s, as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}
