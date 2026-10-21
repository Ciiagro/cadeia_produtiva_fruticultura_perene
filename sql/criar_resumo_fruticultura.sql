-- =====================================================================
-- FRUTICULTURA PERENE
-- RODAR NO BANCO LOCAL  api_sisateg   (F5 uma vez; leva alguns minutos)
-- Cria tabelas com nomes próprios (para não misturar com as outras cadeias no servidor):
--   public.resumo_fruta_propriedades        -> 1 linha por propriedade (ativas e inativas com lançamento): produtor, técnico,
--                                              supervisor (SisATeG), município, áreas, projeto e datas do vínculo.
--   public.resumo_fruta_mensal              -> 1 linha por propriedade e mês: kg vendidos, unidades vendidas, receita bruta e despesa direta.
--   public.resumo_fruta_despesa_subgrupo    -> despesa direta por subgrupo e mês (a soma dos subgrupos = despesa direta).
--   public.resumo_fruta_tipo                -> receitas e despesas por tipo/classe (aba "Receitas e despesas").
-- Regras da fruticultura (mesmo raciocínio da bovinocultura/ovino; CONFERIR com o relatório do SisATeG de um técnico):
--   valor do lançamento = QUANTIDADE x VALOR_UNITARIO (mesma visita e mesmo item)
--   venda_fruta_rs    = receita do subgrupo "Venda de Fruta" (kg e unidade; sem "Venda de Mudas" e "Venda de Subproduto")
--   kg_vendidos       = quantidade dos itens vendidos em Kg (inclui "Venda de Amêndoa Seca (cacau)")
--   unidades_vendidas = quantidade dos itens vendidos por Unidade
--   venda_kg_rs       = valor dos itens vendidos em Kg (base do preço médio por kg)
--   receita_bruta     = toda a receita, menos "Empréstimo - recebimento" e "Investimento - venda de bem"
--   despesa_direta    = despesas menos empréstimo, investimento, "Mão de obra familiar" e "Formação e Recuperação" (lavoura nova).
--                       "Plantio (COE)" CONTA. O grupo "Despesa - Ambiental" não entra.
-- =====================================================================

DROP TABLE IF EXISTS public.resumo_fruta_propriedades;
CREATE TABLE public.resumo_fruta_propriedades AS
WITH ativas AS (  -- propriedades ATIVAS que têm vínculo ATIVO de FRUTICULTURA PERENE
  SELECT id_propriedade, MAX(produtor) AS produtor, MAX(NULLIF(tecnico_atual,'')) AS tecnico_a,
         MAX(NULLIF(supervisor_atual,'')) AS supervisor_a
  FROM public.propriedades_ativas_na_ateg
  WHERE id_propriedade::text IN (
        SELECT id_propriedade::text FROM public.sisateg_vinculo_propriedade
        WHERE atividade ILIKE '%FRUTICULTURA%PERENE%' AND UPPER(status_vinculo) = 'ATIVO')
  GROUP BY 1
),
lanc_ids AS (  -- toda propriedade que já teve lançamento da fruticultura (ativa ou não) desde o início da base
  SELECT DISTINCT id_propriedade FROM public.sisateg_receita_despesa
  WHERE atividade = 'FRUTICULTURA PERENE' AND status_item = 'ATIVO' AND tipo_registro = 'PRINCIPAL'
    AND dt_referencia >= DATE '2024-06-01'
),
todas AS (  -- ativas + inativas que têm lançamento (ativa = TRUE/FALSE)
  SELECT id_propriedade, produtor, tecnico_a, supervisor_a, TRUE AS ativa FROM ativas
  UNION ALL
  SELECT l.id_propriedade, NULL, NULL, NULL, FALSE FROM lanc_ids l
  WHERE l.id_propriedade NOT IN (SELECT id_propriedade FROM ativas)
),
acomp AS (
  SELECT id_propriedade, MAX(tecnico_atual) AS tecnico_m, MAX(tecnico_responsavel) AS tecnico_r,
         MAX(supervisor_atual) AS supervisor_m, MAX(produtor) AS produtor_m, MAX(imovel) AS imovel_m
  FROM public.acompanhamento_mensal_visitas
  WHERE id_propriedade IN (SELECT id_propriedade FROM todas) GROUP BY 1
),
nome AS (
  SELECT id_propriedade, MAX(propriedade) AS propriedade
  FROM public.sisateg_rel_indicador_padrao_mensal
  WHERE propriedade IS NOT NULL AND id_propriedade IN (SELECT id_propriedade FROM todas) GROUP BY 1
),
area AS (  -- área produtiva: usa a do cadastro; se for 0/vazia, usa a do relatório de indicadores do SisATeG (a mesma da planilha oficial)
  SELECT d.id_propriedade, MAX(d.area_total) AS area_total,
         COALESCE(NULLIF(MAX(d.area_atividades_produtivas), 0), MAX(i.area_prod)) AS area_produtiva,
         MAX(d.municipio) AS municipio, MAX(d.uf) AS uf
  FROM public.dim_propriedade d
  LEFT JOIN (SELECT id_propriedade::text AS idp, MAX(NULLIF(area_produtiva::text, '')::numeric) AS area_prod
             FROM public.sisateg_rel_indicador_padrao_mensal GROUP BY 1) i ON i.idp = d.id_propriedade::text
  WHERE d.id_propriedade IN (SELECT id_propriedade FROM todas) GROUP BY 1
),
vinc AS (
  SELECT id_propriedade::text AS idp, id_projeto, projeto, status_vinculo, motivo_desativacao,
         dt_inicio::date AS ini, dt_fim::date AS fim
  FROM public.sisateg_vinculo_propriedade
  WHERE atividade ILIKE '%FRUTICULTURA%PERENE%' AND id_propriedade::text IN (SELECT id_propriedade::text FROM todas)
),
vu AS (  -- um vínculo por propriedade: o ATIVO (se houver) de início mais recente
  SELECT DISTINCT ON (idp) idp, id_projeto, projeto, ini, fim, status_vinculo, motivo_desativacao
  FROM vinc
  ORDER BY idp, (UPPER(status_vinculo) = 'ATIVO') DESC, ini DESC, fim DESC NULLS FIRST
),
nproj AS (SELECT idp, COUNT(DISTINCT id_projeto) AS qtd_projetos FROM vinc GROUP BY 1)
SELECT a.id_propriedade,
       COALESCE(n.propriedade, ac.imovel_m) AS propriedade,
       COALESCE(a.produtor, ac.produtor_m) AS produtor,
       btrim(COALESCE(a.tecnico_a, ac.tecnico_m, ac.tecnico_r), E' \t\r\n') AS tecnico,
       COALESCE(a.supervisor_a, ac.supervisor_m)         AS supervisor_sisateg,
       ar.municipio, ar.uf,
       ROUND(ar.area_total::numeric, 2)    AS area_total,
       ROUND(ar.area_produtiva::numeric, 2) AS area_produtiva,
       vu.projeto, np.qtd_projetos,
       vu.ini AS inicio_projeto, vu.fim AS fim_projeto,
       vu.status_vinculo, vu.motivo_desativacao, a.ativa
FROM todas a
LEFT JOIN acomp ac ON ac.id_propriedade = a.id_propriedade
LEFT JOIN nome n   ON n.id_propriedade  = a.id_propriedade
LEFT JOIN area ar  ON ar.id_propriedade = a.id_propriedade
LEFT JOIN vu       ON vu.idp = a.id_propriedade::text
LEFT JOIN nproj np ON np.idp = a.id_propriedade::text;

CREATE INDEX ON public.resumo_fruta_propriedades (id_propriedade);
CREATE INDEX ON public.resumo_fruta_propriedades (tecnico);

-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS public.resumo_fruta_mensal;
CREATE TABLE public.resumo_fruta_mensal AS
WITH param AS (
  SELECT DATE '2024-06-01' AS data_inicio, DATE '2026-12-31' AS data_fim
),
base AS (
  SELECT r.*
  FROM public.sisateg_receita_despesa r, param p
  WHERE r.atividade = 'FRUTICULTURA PERENE'
    AND r.status_item = 'ATIVO'
    AND r.tipo_registro = 'PRINCIPAL'
    AND r.dt_referencia BETWEEN p.data_inicio AND p.data_fim
    AND r.id_propriedade IN (SELECT id_propriedade FROM public.resumo_fruta_propriedades)
),
q AS (
  SELECT id_propriedade, grupo, id_visita, id_item, dt_referencia, subgrupo, item, SUM(valor) AS qtd
  FROM base WHERE tipo_valor = 'QUANTIDADE' GROUP BY 1,2,3,4,5,6,7
),
pr AS (
  SELECT id_propriedade, grupo, id_visita, id_item, dt_referencia, AVG(valor) AS preco
  FROM base WHERE tipo_valor = 'VALOR_UNITARIO' GROUP BY 1,2,3,4,5
),
v AS (
  SELECT q.id_propriedade, date_trunc('month', q.dt_referencia)::date AS mes,
         q.grupo, q.subgrupo, q.item, q.qtd, q.qtd * pr.preco AS valor
  FROM q JOIN pr USING (id_propriedade, grupo, id_visita, id_item, dt_referencia)
),
tec_mes AS (  -- técnico responsável pela visita daquele mês (técnico da época)
  SELECT b.id_propriedade, date_trunc('month', b.dt_referencia)::date AS mes,
         MAX(btrim(av.tecnico_responsavel, E' \t\r\n')) AS tecnico
  FROM base b
  JOIN public.acompanhamento_mensal_visitas av ON av.id_visita::text = b.id_visita::text
  GROUP BY 1, 2
),
fin AS (
  SELECT id_propriedade, mes,
    SUM(qtd) FILTER (WHERE grupo = 'Receita' AND subgrupo ILIKE 'Venda de Fruta%'
         AND (item ILIKE '%(Kg)%' OR item ILIKE 'Venda de Am_ndoa Seca%')) AS kg_vendidos,
    SUM(qtd) FILTER (WHERE grupo = 'Receita' AND subgrupo ILIKE 'Venda de Fruta%' AND item ILIKE '%(Unidade)%') AS unidades_vendidas,
    SUM(valor) FILTER (WHERE grupo = 'Receita' AND subgrupo ILIKE 'Venda de Fruta%'
         AND (item ILIKE '%(Kg)%' OR item ILIKE 'Venda de Am_ndoa Seca%')) AS venda_kg_rs,
    SUM(valor) FILTER (WHERE grupo = 'Receita' AND subgrupo ILIKE 'Venda de Fruta%'
         AND item NOT ILIKE 'Venda de Mudas%' AND item NOT ILIKE 'Venda de Subproduto%') AS venda_fruta_rs,
    SUM(valor) FILTER (WHERE grupo = 'Receita'
         AND subgrupo NOT ILIKE 'Empr%' AND subgrupo NOT ILIKE 'Investimento%') AS receita_bruta,
    SUM(valor) FILTER (WHERE grupo = 'Despesa'
         AND subgrupo NOT ILIKE 'Empr%' AND subgrupo NOT ILIKE 'Investimento%') AS despesa_total,
    SUM(valor) FILTER (WHERE grupo = 'Despesa'
         AND subgrupo NOT ILIKE 'Empr%' AND subgrupo NOT ILIKE 'Investimento%'
         AND subgrupo NOT ILIKE 'Forma%o e Recupera%' AND subgrupo NOT ILIKE 'M_o de obra familiar'
         AND item NOT ILIKE 'M_o de obra familiar') AS despesa_direta,
    SUM(valor) FILTER (WHERE grupo = 'Despesa' AND (item ILIKE 'M_o de obra familiar' OR subgrupo ILIKE 'M_o de obra familiar')) AS mao_obra_familiar,
    SUM(valor) FILTER (WHERE grupo = 'Despesa' AND subgrupo ILIKE 'Forma%o e Recupera%') AS despesa_formacao
  FROM v GROUP BY 1,2
)
SELECT f.id_propriedade,
       to_char(f.mes, 'YYYY-MM') AS mes,
       t.tecnico,
       ROUND(f.kg_vendidos::numeric, 1)          AS kg_vendidos,
       ROUND(f.unidades_vendidas::numeric, 1)    AS unidades_vendidas,
       ROUND(f.venda_fruta_rs::numeric, 2)       AS venda_fruta_rs,
       ROUND(f.venda_kg_rs::numeric, 2)          AS venda_kg_rs,
       ROUND(f.receita_bruta::numeric, 2)        AS receita_bruta,
       ROUND(f.despesa_direta::numeric, 2)       AS despesa_direta,
       ROUND(f.mao_obra_familiar::numeric, 2)    AS mao_obra_familiar,
       ROUND(f.despesa_formacao::numeric, 2)     AS despesa_formacao,
       ROUND(f.despesa_total::numeric, 2)        AS despesa_total
FROM fin f
LEFT JOIN tec_mes t ON t.id_propriedade = f.id_propriedade AND t.mes = f.mes;

CREATE INDEX ON public.resumo_fruta_mensal (id_propriedade);
CREATE INDEX ON public.resumo_fruta_mensal (tecnico);
CREATE INDEX ON public.resumo_fruta_mensal (mes);
-- ---------------------------------------------------------------------
-- Despesa direta por SUBGRUPO e mês (mesma regra da despesa_direta acima; a soma dos subgrupos = despesa_direta)
DROP TABLE IF EXISTS public.resumo_fruta_despesa_subgrupo;
CREATE TABLE public.resumo_fruta_despesa_subgrupo AS
WITH base AS (
  SELECT r.* FROM public.sisateg_receita_despesa r
  WHERE r.atividade = 'FRUTICULTURA PERENE' AND r.status_item = 'ATIVO' AND r.tipo_registro = 'PRINCIPAL'
    AND r.dt_referencia BETWEEN DATE '2024-06-01' AND DATE '2026-12-31'
    AND r.grupo = 'Despesa'
    AND r.id_propriedade IN (SELECT id_propriedade FROM public.resumo_fruta_propriedades)
),
q AS (
  SELECT id_propriedade, id_visita, id_item, dt_referencia, subgrupo, item, SUM(valor) AS qtd
  FROM base WHERE tipo_valor = 'QUANTIDADE' GROUP BY 1,2,3,4,5,6
),
pr AS (
  SELECT id_propriedade, id_visita, id_item, dt_referencia, AVG(valor) AS preco
  FROM base WHERE tipo_valor = 'VALOR_UNITARIO' GROUP BY 1,2,3,4
)
SELECT q.id_propriedade, to_char(date_trunc('month', q.dt_referencia), 'YYYY-MM') AS mes, q.subgrupo,
       ROUND(SUM(q.qtd * pr.preco)::numeric, 2) AS valor
FROM q JOIN pr USING (id_propriedade, id_visita, id_item, dt_referencia)
WHERE q.subgrupo NOT ILIKE 'Empr%' AND q.subgrupo NOT ILIKE 'Investimento%'
  AND q.subgrupo NOT ILIKE 'Forma%o e Recupera%' AND q.subgrupo NOT ILIKE 'M_o de obra familiar'
  AND q.item NOT ILIKE 'M_o de obra familiar'
GROUP BY 1,2,3;
CREATE INDEX ON public.resumo_fruta_despesa_subgrupo (id_propriedade, mes);

-- Receitas e despesas por TIPO (subgrupo) e classe: alimenta a aba "Receitas e despesas".
--   classe: Receita bruta | Fora da receita bruta (empréstimo/investimento)
--           Despesa direta | Outras despesas (formação e recuperação da lavoura, mão de obra familiar)
--           | Fora das despesas (empréstimo/investimento)
--   total de despesas da aba = Despesa direta + Outras despesas + Fora das despesas (= Total Despesas do SisATeG; a aba calcula a soma)
DROP TABLE IF EXISTS public.resumo_fruta_tipo;
CREATE TABLE public.resumo_fruta_tipo AS
WITH base AS (
  SELECT r.* FROM public.sisateg_receita_despesa r
  WHERE r.atividade = 'FRUTICULTURA PERENE' AND r.status_item = 'ATIVO' AND r.tipo_registro = 'PRINCIPAL'
    AND r.dt_referencia BETWEEN DATE '2024-06-01' AND DATE '2026-12-31'
    AND r.grupo IN ('Receita','Despesa')
    AND r.id_propriedade IN (SELECT id_propriedade FROM public.resumo_fruta_propriedades)
),
q AS (
  SELECT id_propriedade, id_visita, id_item, dt_referencia, grupo, subgrupo, item, SUM(valor) AS qtd
  FROM base WHERE tipo_valor = 'QUANTIDADE' GROUP BY 1,2,3,4,5,6,7
),
pr AS (
  SELECT id_propriedade, id_visita, id_item, dt_referencia, AVG(valor) AS preco
  FROM base WHERE tipo_valor = 'VALOR_UNITARIO' GROUP BY 1,2,3,4
),
v AS (
  SELECT q.id_propriedade, to_char(date_trunc('month', q.dt_referencia), 'YYYY-MM') AS mes, q.grupo, q.subgrupo,
         CASE WHEN q.subgrupo ILIKE 'Empr%' OR q.subgrupo ILIKE 'Investimento%' THEN
                CASE WHEN q.grupo = 'Receita' THEN 'Fora da receita bruta' ELSE 'Fora das despesas' END
              WHEN q.grupo = 'Receita' THEN 'Receita bruta'
              WHEN q.subgrupo ILIKE 'Forma%o e Recupera%' OR q.subgrupo ILIKE 'M_o de obra familiar'
                   OR q.item ILIKE 'M_o de obra familiar' THEN 'Outras despesas'
              ELSE 'Despesa direta' END AS classe,
         q.qtd * pr.preco AS valor
  FROM q JOIN pr USING (id_propriedade, id_visita, id_item, dt_referencia)
)
SELECT id_propriedade, mes, grupo, classe, subgrupo, ROUND(SUM(valor)::numeric, 2) AS valor
FROM v GROUP BY 1,2,3,4,5;
CREATE INDEX ON public.resumo_fruta_tipo (id_propriedade, mes);

ANALYZE public.resumo_fruta_propriedades;
ANALYZE public.resumo_fruta_mensal;

-- Conferência: propriedades e quantas têm lançamento de fruticultura
SELECT (SELECT COUNT(*) FROM public.resumo_fruta_propriedades) AS propriedades,
       (SELECT COUNT(DISTINCT id_propriedade) FROM public.resumo_fruta_mensal) AS com_lancamento,
       (SELECT COUNT(*) FROM public.resumo_fruta_mensal) AS linhas_mensais,
       (SELECT MAX(mes) FROM public.resumo_fruta_mensal) AS ultimo_mes;
