-- RODAR NO SERVIDOR (banco painel_ateg). O script de cópia já roda este arquivo sozinho depois de copiar.
-- FRUTICULTURA PERENE: views com nomes próprios (vw_fruta_*), para não mexer nas views da bovinocultura.
-- Supervisor OFICIAL = public.ranking_tecnicos.ultimo_supervisor; se o técnico não estiver no ranking, usa o supervisor do SisATeG.
DROP VIEW IF EXISTS public.vw_fruta_tipo;
DROP VIEW IF EXISTS public.vw_fruta_mensal_fruta;
DROP VIEW IF EXISTS public.vw_fruta_despesa_subgrupo;
DROP VIEW IF EXISTS public.vw_fruta_mensal;
DROP VIEW IF EXISTS public.vw_fruta_propriedades CASCADE;
CREATE VIEW public.vw_fruta_propriedades AS
SELECT p.id_propriedade, p.propriedade, p.produtor, p.tecnico,
       COALESCE(k.ultimo_supervisor, p.supervisor_sisateg) AS supervisor, p.supervisor_sisateg,
       p.municipio, p.uf, p.area_total, p.area_produtiva,
       p.projeto, p.qtd_projetos, p.inicio_projeto, p.fim_projeto, p.status_vinculo, p.motivo_desativacao, p.ativa
FROM public.resumo_fruta_propriedades p
LEFT JOIN public.ranking_tecnicos k ON btrim(k.tecnico_responsavel, E' \t\r\n') = p.tecnico;

-- Mensal: o técnico e o supervisor são os da ÉPOCA (da visita do mês); se faltar, usa o da propriedade.
CREATE VIEW public.vw_fruta_mensal AS
SELECT v.id_propriedade, v.propriedade, v.produtor,
       COALESCE(m.tecnico, v.tecnico) AS tecnico,
       COALESCE(k2.ultimo_supervisor, v.supervisor) AS supervisor,
       v.supervisor_sisateg, v.municipio, v.uf, v.area_total, v.area_produtiva,
       v.projeto, v.qtd_projetos, v.inicio_projeto, v.fim_projeto, v.status_vinculo, v.motivo_desativacao, v.ativa,
       m.mes, m.id_visita, m.kg_vendidos, m.unidades_vendidas, m.venda_fruta_rs, m.venda_kg_rs, m.receita_bruta, m.despesa_direta,
       (m.receita_bruta - m.despesa_direta) AS margem_bruta
FROM public.vw_fruta_propriedades v
JOIN public.resumo_fruta_mensal m ON m.id_propriedade = v.id_propriedade
LEFT JOIN public.ranking_tecnicos k2 ON btrim(k2.tecnico_responsavel, E' \t\r\n') = COALESCE(m.tecnico, v.tecnico);

-- Mensal POR FRUTA: igual à vw_fruta_mensal, com a coluna fruta (1 linha por propriedade, mês e fruta).
-- Usada quando o filtro "Fruta" do painel está escolhido.
CREATE VIEW public.vw_fruta_mensal_fruta AS
SELECT v.id_propriedade, v.propriedade, v.produtor,
       COALESCE(m.tecnico, v.tecnico) AS tecnico,
       COALESCE(k2.ultimo_supervisor, v.supervisor) AS supervisor,
       v.supervisor_sisateg, v.municipio, v.uf, v.area_total, v.area_produtiva,
       v.projeto, v.qtd_projetos, v.inicio_projeto, v.fim_projeto, v.status_vinculo, v.motivo_desativacao, v.ativa,
       m.mes, m.fruta, m.safra_nome AS safra,
       ROUND(m.kg_vendidos::numeric, 1) AS kg_vendidos, ROUND(m.unidades_vendidas::numeric, 1) AS unidades_vendidas,
       ROUND(m.venda_fruta_rs::numeric, 2) AS venda_fruta_rs, ROUND(m.venda_kg_rs::numeric, 2) AS venda_kg_rs,
       ROUND(m.receita_bruta::numeric, 2) AS receita_bruta, ROUND(m.despesa_direta::numeric, 2) AS despesa_direta,
       ROUND((m.receita_bruta - m.despesa_direta)::numeric, 2) AS margem_bruta
FROM public.vw_fruta_propriedades v
JOIN public.resumo_fruta_mensal_fruta m ON m.id_propriedade = v.id_propriedade
LEFT JOIN public.ranking_tecnicos k2 ON btrim(k2.tecnico_responsavel, E' \t\r\n') = COALESCE(m.tecnico, v.tecnico);

-- Despesa direta por subgrupo: mesmas colunas de filtro da vw_fruta_mensal + subgrupo e valor.
CREATE VIEW public.vw_fruta_despesa_subgrupo AS
SELECT w.id_propriedade, w.propriedade, w.tecnico, w.supervisor, w.projeto, w.municipio, w.ativa, w.mes,
       d.fruta, d.safra_nome AS safra, d.subgrupo, d.valor
FROM public.vw_fruta_mensal w
JOIN public.resumo_fruta_despesa_subgrupo d ON d.id_propriedade = w.id_propriedade AND d.mes = w.mes;

-- Receitas e despesas por tipo (aba "Receitas e despesas").
CREATE VIEW public.vw_fruta_tipo AS
SELECT w.id_propriedade, w.propriedade, w.tecnico, w.supervisor, w.projeto, w.municipio, w.ativa, w.mes,
       d.fruta, d.safra_nome AS safra, d.grupo, d.classe, d.subgrupo, d.valor
FROM public.vw_fruta_mensal w
JOIN public.resumo_fruta_tipo d ON d.id_propriedade = w.id_propriedade AND d.mes = w.mes;

-- Permissão do usuário só de leitura (se ele já existir) depois que as views são recriadas.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'painel_leitura') THEN
    GRANT SELECT ON public.vw_fruta_propriedades, public.vw_fruta_mensal, public.vw_fruta_mensal_fruta, public.vw_fruta_despesa_subgrupo, public.vw_fruta_tipo TO painel_leitura;
  END IF;
END $$;
