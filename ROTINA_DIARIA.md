# Rotina do painel de fruticultura de corte

Depende da rotina da bovinocultura: os passos 1 a 3 (carga de receita/despesa, tabelas auxiliares e
refazer `sisateg_receita_despesa`) são os MESMOS e já atualizam o corte. Depois:

## 1) pgAdmin, banco `api_sisateg`
Rodar o arquivo inteiro `sql/criar_resumo_fruticultura.sql`.
Conferir a última linha: propriedades, com_lancamento, linhas_mensais, ultimo_mes.

## 2) Git Bash: copiar para o servidor
```
cd "/c/CIIAGRO2/painel_cadeias/Fruticultura"
python scripts/transferir_resumo.py
```
Depois abrir o painel na Vercel e atualizar com Ctrl+F5.

Se um passo der erro, as tabelas ficam como estavam (as trocas são "tudo ou nada"). Não siga para o passo seguinte.
