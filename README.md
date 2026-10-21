# Painel de acompanhamento mensal: Fruticultura perene

Mesmo painel da bovinocultura (FastAPI + Chart.js na Vercel), adaptado à fruticultura perene.
Lê as views `vw_fruta_mensal`, `vw_fruta_propriedades` e `vw_fruta_despesa_subgrupo` do banco `painel_ateg`.
Não mexe nas views da bovinocultura (nomes próprios).

## O que o painel mostra
Receita bruta, despesa direta, venda de kg de fruta, preço médio por animal, kg de fruta vendidos (cabeças),
margem bruta da atividade, margem da venda de kg de fruta e kg de fruta vendidos por produtor.
Abas: Gráficos, Destaques do mês, Causas (entradas/saídas, preço por animal, despesa por subgrupo) e Tabela mensal (+ Excel).

## Regras do corte (conferir com o SisATeG de um técnico)
- Valor do lançamento = QUANTIDADE x VALOR_UNITARIO. Atividade FRUTICULTURA PERENE, status ATIVO, tipo PRINCIPAL.
- Venda de kg de fruta = subgrupos "Venda de Animal Vivo" + "Venda de Animal Abate". Animais vendidos = quantidade desses subgrupos.
- Receita bruta = tudo da receita menos empréstimo e investimento (venda de bem).
- Despesa direta = despesas menos empréstimo, investimento, aleitamento artificial, formação de forrageiras perene,
  mão de obra familiar e compra de kg de fruta lançada como investimento / animal de serviço.
  A compra de kg de fruta para recria/terminação (COE) CONTA como despesa direta. (hipótese a validar)
- Entradas/saídas de propriedades: pelo primeiro/último mês com lançamento (a venda de corte é irregular, não dá para usar só a venda).
- O painel começa em jun/2024 (`MES_INICIO` no SQL e no app; o corte tem dados desde 2020).

## Rotina
1. Rodar a rotina da bovinocultura (passos 1 a 3 do ROTINA_DIARIA.md): a tabela `sisateg_receita_despesa` é a mesma.
2. Rodar `sql/criar_resumo_fruticultura.sql` no banco local `api_sisateg` (pgAdmin).
3. `python scripts/transferir_resumo.py` (copia as 3 tabelas resumo_fruta_* e recria as views vw_fruta_*).
4. Abrir o painel e apertar Ctrl+F5.

## Primeira publicação (uma vez)
- Copiar o `.env` da bovinocultura para esta pasta (sem TABLE_NAME; veja .env.example).
- Rodar `sql/usuario_leitura.sql` só se o usuário `painel_leitura` ainda não existir (ele já existe). O script de cópia já reaplica o GRANT.
- Criar o repositório novo no GitHub e o projeto novo na Vercel apontando para esta pasta.
