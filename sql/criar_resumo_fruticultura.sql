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


-- ---------------------------------------------------------------------
-- Fruta da safra: o nome da fruta vem escrito na safra ("COCO 2024", "Safra CAJU 25/26", "BANANA-2026" ...).
-- Safras genéricas ("safra 2025") e lançamentos sem safra ficam em 'Sem fruta informada'.
CREATE OR REPLACE FUNCTION public.fruta_da_safra(s text) RETURNS text
LANGUAGE sql IMMUTABLE AS $f$
  SELECT CASE
    WHEN t ~ 'ABACATE'   THEN 'Abacate'
    WHEN t ~ 'ABACAXI'   THEN 'Abacaxi'
    WHEN t ~ 'ACEROLA'   THEN 'Acerola'
    WHEN t ~ 'BANANA' OR t ~ 'BANABA' THEN 'Banana'
    WHEN t ~ 'CAJU'      THEN 'Caju'
    WHEN t ~ 'COCO'      THEN 'Coco'
    WHEN t ~ 'GOIABA'    THEN 'Goiaba'
    WHEN t ~ 'GRAVIOLA'  THEN 'Graviola'
    WHEN t ~ 'LARANJA'   THEN 'Laranja'
    WHEN t ~ 'LIMAO'     THEN 'Limão'
    WHEN t ~ 'MAMAO'     THEN 'Mamão'
    WHEN t ~ 'MANGA'     THEN 'Manga'
    WHEN t ~ 'MARACUJA'  THEN 'Maracujá'
    WHEN t ~ 'MORANGO'   THEN 'Morango'
    WHEN t ~ 'PITAIA'    THEN 'Pitaia'
    WHEN t ~ 'SAPOTI'    THEN 'Sapoti'
    WHEN t ~ 'TANGERINA' THEN 'Tangerina'
    WHEN t ~ '(^|[^A-Z])UVA($|[^A-Z])' THEN 'Uva'
    ELSE 'Sem fruta informada' END
  FROM (SELECT translate(upper(COALESCE(s, '')), 'ÁÀÂÃÉÊÍÓÔÕÚÇ', 'AAAAEEIOOOUC') AS t) x
$f$;


-- Nome da safra para o filtro: o texto da safra; as genéricas ("safra 2025") ganham o número para não misturar safras de frutas diferentes.
CREATE OR REPLACE FUNCTION public.safra_nome(s text, id_s text) RETURNS text
LANGUAGE sql IMMUTABLE AS $f$
  SELECT CASE WHEN s IS NULL OR btrim(s) = '' THEN 'Sem safra informada'
              WHEN public.fruta_da_safra(s) = 'Sem fruta informada' THEN btrim(s) || ' (nº ' || COALESCE(id_s, '?') || ')'
              ELSE btrim(s) END
$f$;

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
-- Itens da fruticultura com o MÊS CORRIGIDO: a data do item (dt_referencia) fica velha quando o técnico corrige a referência
-- da visita no SisATeG; a planilha usa a referência da visita. Regra (igual à Bovinocultura): usa a referência da visita
-- quando ela existe e está a até 366 dias da data do item; senão, a data do item.
DROP TABLE IF EXISTS public.resumo_fruta_rd;
CREATE TABLE public.resumo_fruta_rd AS
WITH vis AS (
  SELECT id_visita AS idv,
         MAX(CASE WHEN referencia_visita ~ '^[0-9]{4}-[0-9]{2}$' THEN to_date(referencia_visita || '-01', 'YYYY-MM-DD') END) AS ref,
         MAX(visita_valida) AS valida
  FROM public.acompanhamento_mensal_visitas
  GROUP BY id_visita
)
SELECT r.atividade, r.status_item, r.tipo_registro, r.id_propriedade, r.grupo, r.id_visita, r.id_item,
       r.subgrupo, r.item, r.safra, r.id_safra, r.tipo_valor, r.valor,
       CASE WHEN v.ref IS NOT NULL AND abs(r.dt_referencia::date - v.ref) <= 366
            THEN v.ref::timestamp ELSE r.dt_referencia END AS dt_referencia,
       v.valida AS visita_valida
FROM public.sisateg_receita_despesa r
LEFT JOIN vis v ON v.idv = r.id_visita
WHERE r.atividade = 'FRUTICULTURA PERENE' AND r.status_item = 'ATIVO' AND r.tipo_registro = 'PRINCIPAL'
  AND r.dt_referencia >= DATE '2024-01-01';
CREATE INDEX ON public.resumo_fruta_rd (id_propriedade);
CREATE INDEX ON public.resumo_fruta_rd (id_visita);
ANALYZE public.resumo_fruta_rd;   -- o banco precisa saber o tamanho da tabela nova para escolher um bom plano nos passos seguintes

-- Última visita de cada propriedade em cada mês: o SisATeG (planilha) conta só ela; visitas repetidas no mês não somam.
DROP TABLE IF EXISTS public.resumo_fruta_visita_ult;
CREATE TABLE public.resumo_fruta_visita_ult AS
SELECT DISTINCT ON (id_propriedade, date_trunc('month', dt_referencia)) id_propriedade,
       date_trunc('month', dt_referencia)::date AS mes, id_visita
FROM public.resumo_fruta_rd
WHERE dt_referencia >= DATE '2024-06-01'
ORDER BY id_propriedade, date_trunc('month', dt_referencia), (visita_valida = 'Valida') DESC NULLS LAST, id_visita DESC;
CREATE INDEX ON public.resumo_fruta_visita_ult (id_visita);
ANALYZE public.resumo_fruta_visita_ult;

DROP TABLE IF EXISTS public.resumo_fruta_mensal_fruta;
CREATE TABLE public.resumo_fruta_mensal_fruta AS
WITH param AS (
  SELECT DATE '2024-06-01' AS data_inicio, DATE '2026-12-31' AS data_fim
),
base AS (
  SELECT r.*
  FROM public.resumo_fruta_rd r, param p
  WHERE r.atividade = 'FRUTICULTURA PERENE'
    AND r.status_item = 'ATIVO'
    AND r.tipo_registro = 'PRINCIPAL'
    AND r.dt_referencia BETWEEN p.data_inicio AND p.data_fim
    AND r.id_propriedade IN (SELECT id_propriedade FROM public.resumo_fruta_propriedades)
    AND r.id_visita IN (SELECT id_visita FROM public.resumo_fruta_visita_ult)   -- só a última visita do mês (como a planilha do SisATeG)
),
q AS (
  SELECT id_propriedade, grupo, id_visita, id_item, dt_referencia, subgrupo, item,
         public.fruta_da_safra(safra) AS fruta, public.safra_nome(safra, id_safra::text) AS safra_nome, SUM(valor) AS qtd
  FROM base WHERE tipo_valor = 'QUANTIDADE' GROUP BY 1,2,3,4,5,6,7,8,9
),
pr AS (
  SELECT id_propriedade, grupo, id_visita, id_item, dt_referencia, AVG(valor) AS preco
  FROM base WHERE tipo_valor = 'VALOR_UNITARIO' GROUP BY 1,2,3,4,5
),
v AS (
  SELECT q.id_propriedade, date_trunc('month', q.dt_referencia)::date AS mes,
         q.fruta, q.safra_nome, q.grupo, q.subgrupo, q.item, q.qtd, q.qtd * pr.preco AS valor
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
  SELECT id_propriedade, mes, fruta, safra_nome,
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
         AND subgrupo NOT ILIKE 'Empr%' AND subgrupo NOT ILIKE 'Investimento%'
         AND subgrupo NOT ILIKE 'Plantio (COE)%' AND subgrupo NOT ILIKE 'Manejo de Sombra%') AS despesa_total,
    SUM(valor) FILTER (WHERE grupo = 'Despesa'
         AND subgrupo NOT ILIKE 'Empr%' AND subgrupo NOT ILIKE 'Investimento%'
         AND subgrupo NOT ILIKE 'Forma%o e Recupera%' AND subgrupo NOT ILIKE 'M_o de obra familiar'
         AND item NOT ILIKE 'M_o de obra familiar'
         AND subgrupo NOT ILIKE 'Plantio (COE)%' AND subgrupo NOT ILIKE 'Manejo de Sombra%') AS despesa_direta,
    SUM(valor) FILTER (WHERE grupo = 'Despesa' AND (item ILIKE 'M_o de obra familiar' OR subgrupo ILIKE 'M_o de obra familiar')) AS mao_obra_familiar,
    SUM(valor) FILTER (WHERE grupo = 'Despesa' AND subgrupo ILIKE 'Forma%o e Recupera%') AS despesa_formacao
  FROM v GROUP BY 1,2,3,4
)
SELECT f.id_propriedade,
       to_char(f.mes, 'YYYY-MM') AS mes,
       f.fruta,
       f.safra_nome,
       t.tecnico,
       f.kg_vendidos AS kg_vendidos,
       f.unidades_vendidas AS unidades_vendidas,
       f.venda_fruta_rs AS venda_fruta_rs,
       f.venda_kg_rs AS venda_kg_rs,
       f.receita_bruta AS receita_bruta,
       f.despesa_direta AS despesa_direta,
       f.mao_obra_familiar AS mao_obra_familiar,
       f.despesa_formacao AS despesa_formacao,
       f.despesa_total AS despesa_total
FROM fin f
LEFT JOIN tec_mes t ON t.id_propriedade = f.id_propriedade AND t.mes = f.mes;

CREATE INDEX ON public.resumo_fruta_mensal_fruta (id_propriedade, mes);
CREATE INDEX ON public.resumo_fruta_mensal_fruta (fruta);
CREATE INDEX ON public.resumo_fruta_mensal_fruta (safra_nome);


-- Mensal TOTAL (todas as frutas somadas): 1 linha por propriedade e mês, igual ao que o painel sempre usou.
DROP TABLE IF EXISTS public.resumo_fruta_mensal;
CREATE TABLE public.resumo_fruta_mensal AS
SELECT id_propriedade, mes, MAX(tecnico) AS tecnico,
       ROUND(SUM(kg_vendidos)::numeric, 1)       AS kg_vendidos,
       ROUND(SUM(unidades_vendidas)::numeric, 1) AS unidades_vendidas,
       ROUND(SUM(venda_fruta_rs)::numeric, 2)    AS venda_fruta_rs,
       ROUND(SUM(venda_kg_rs)::numeric, 2)       AS venda_kg_rs,
       ROUND(SUM(receita_bruta)::numeric, 2)     AS receita_bruta,
       ROUND(SUM(despesa_direta)::numeric, 2)    AS despesa_direta,
       ROUND(SUM(mao_obra_familiar)::numeric, 2) AS mao_obra_familiar,
       ROUND(SUM(despesa_formacao)::numeric, 2)  AS despesa_formacao,
       ROUND(SUM(despesa_total)::numeric, 2)     AS despesa_total
FROM public.resumo_fruta_mensal_fruta
GROUP BY id_propriedade, mes;

CREATE INDEX ON public.resumo_fruta_mensal (id_propriedade);
CREATE INDEX ON public.resumo_fruta_mensal (tecnico);
CREATE INDEX ON public.resumo_fruta_mensal (mes);
-- ---------------------------------------------------------------------
-- Despesa direta por SUBGRUPO e mês (mesma regra da despesa_direta acima; a soma dos subgrupos = despesa_direta)
DROP TABLE IF EXISTS public.resumo_fruta_despesa_subgrupo;
CREATE TABLE public.resumo_fruta_despesa_subgrupo AS
WITH base AS (
  SELECT r.* FROM public.resumo_fruta_rd r
  WHERE r.atividade = 'FRUTICULTURA PERENE' AND r.status_item = 'ATIVO' AND r.tipo_registro = 'PRINCIPAL'
    AND r.dt_referencia BETWEEN DATE '2024-06-01' AND DATE '2026-12-31'
    AND r.grupo = 'Despesa'
    AND r.id_propriedade IN (SELECT id_propriedade FROM public.resumo_fruta_propriedades)
    AND r.id_visita IN (SELECT id_visita FROM public.resumo_fruta_visita_ult)   -- só a última visita do mês (como a planilha do SisATeG)
),
q AS (
  SELECT id_propriedade, id_visita, id_item, dt_referencia, subgrupo, item,
         public.fruta_da_safra(safra) AS fruta, public.safra_nome(safra, id_safra::text) AS safra_nome, SUM(valor) AS qtd
  FROM base WHERE tipo_valor = 'QUANTIDADE' GROUP BY 1,2,3,4,5,6,7,8
),
pr AS (
  SELECT id_propriedade, id_visita, id_item, dt_referencia, AVG(valor) AS preco
  FROM base WHERE tipo_valor = 'VALOR_UNITARIO' GROUP BY 1,2,3,4
)
SELECT q.id_propriedade, to_char(date_trunc('month', q.dt_referencia), 'YYYY-MM') AS mes, q.fruta, q.safra_nome, q.subgrupo,
       ROUND(SUM(q.qtd * pr.preco)::numeric, 2) AS valor
FROM q JOIN pr USING (id_propriedade, id_visita, id_item, dt_referencia)
WHERE q.subgrupo NOT ILIKE 'Empr%' AND q.subgrupo NOT ILIKE 'Investimento%'
  AND q.subgrupo NOT ILIKE 'Forma%o e Recupera%' AND q.subgrupo NOT ILIKE 'M_o de obra familiar'
  AND q.item NOT ILIKE 'M_o de obra familiar'
  AND q.subgrupo NOT ILIKE 'Plantio (COE)%' AND q.subgrupo NOT ILIKE 'Manejo de Sombra%'   -- o Total Despesas do SisATeG não conta esses tipos
GROUP BY 1,2,3,4,5;
CREATE INDEX ON public.resumo_fruta_despesa_subgrupo (id_propriedade, mes);

-- Receitas e despesas por TIPO (subgrupo) e classe: alimenta a aba "Receitas e despesas".
--   classe: Receita bruta | Fora da receita bruta (empréstimo/investimento)
--           Despesa direta | Outras despesas (formação e recuperação da lavoura, mão de obra familiar)
--           | Fora das despesas (empréstimo/investimento)
--   total de despesas da aba = Despesa direta + Outras despesas + Fora das despesas (= Total Despesas do SisATeG; a aba calcula a soma)
DROP TABLE IF EXISTS public.resumo_fruta_tipo;
CREATE TABLE public.resumo_fruta_tipo AS
WITH base AS (
  SELECT r.* FROM public.resumo_fruta_rd r
  WHERE r.atividade = 'FRUTICULTURA PERENE' AND r.status_item = 'ATIVO' AND r.tipo_registro = 'PRINCIPAL'
    AND r.dt_referencia BETWEEN DATE '2024-06-01' AND DATE '2026-12-31'
    AND r.grupo IN ('Receita','Despesa')
    AND r.id_propriedade IN (SELECT id_propriedade FROM public.resumo_fruta_propriedades)
    AND r.id_visita IN (SELECT id_visita FROM public.resumo_fruta_visita_ult)   -- só a última visita do mês (como a planilha do SisATeG)
),
q AS (
  SELECT id_propriedade, id_visita, id_item, dt_referencia, grupo, subgrupo, item,
         public.fruta_da_safra(safra) AS fruta, public.safra_nome(safra, id_safra::text) AS safra_nome, SUM(valor) AS qtd
  FROM base WHERE tipo_valor = 'QUANTIDADE' GROUP BY 1,2,3,4,5,6,7,8,9
),
pr AS (
  SELECT id_propriedade, id_visita, id_item, dt_referencia, AVG(valor) AS preco
  FROM base WHERE tipo_valor = 'VALOR_UNITARIO' GROUP BY 1,2,3,4
),
v AS (
  SELECT q.id_propriedade, to_char(date_trunc('month', q.dt_referencia), 'YYYY-MM') AS mes, q.fruta, q.safra_nome, q.grupo, q.subgrupo,
         CASE WHEN q.grupo = 'Despesa' AND (q.subgrupo ILIKE 'Plantio (COE)%' OR q.subgrupo ILIKE 'Manejo de Sombra%') THEN 'Fora do total (planilha)'   -- gasto real, mas o Total Despesas do SisATeG não conta
              WHEN q.subgrupo ILIKE 'Empr%' OR q.subgrupo ILIKE 'Investimento%' THEN
                CASE WHEN q.grupo = 'Receita' THEN 'Fora da receita bruta' ELSE 'Fora das despesas' END
              WHEN q.grupo = 'Receita' THEN 'Receita bruta'
              WHEN q.subgrupo ILIKE 'Forma%o e Recupera%' OR q.subgrupo ILIKE 'M_o de obra familiar'
                   OR q.item ILIKE 'M_o de obra familiar' THEN 'Outras despesas'
              ELSE 'Despesa direta' END AS classe,
         q.qtd * pr.preco AS valor
  FROM q JOIN pr USING (id_propriedade, id_visita, id_item, dt_referencia)
)
SELECT id_propriedade, mes, fruta, safra_nome, grupo, classe, subgrupo, ROUND(SUM(valor)::numeric, 2) AS valor
FROM v GROUP BY 1,2,3,4,5,6,7;
CREATE INDEX ON public.resumo_fruta_tipo (id_propriedade, mes);

ANALYZE public.resumo_fruta_propriedades;
ANALYZE public.resumo_fruta_mensal;
ANALYZE public.resumo_fruta_mensal_fruta;

-- Conferência: propriedades e quantas têm lançamento de fruticultura
SELECT (SELECT COUNT(*) FROM public.resumo_fruta_propriedades) AS propriedades,
       (SELECT COUNT(DISTINCT id_propriedade) FROM public.resumo_fruta_mensal) AS com_lancamento,
       (SELECT COUNT(*) FROM public.resumo_fruta_mensal) AS linhas_mensais,
       (SELECT MAX(mes) FROM public.resumo_fruta_mensal) AS ultimo_mes;
