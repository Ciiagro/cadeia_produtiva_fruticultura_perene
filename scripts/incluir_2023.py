"""Refaz o resumo da fruticultura de 2023-01 em diante e copia para o servidor. NÃO baixa nada do SisATeG.
Usa a tabela combinada local (sisateg_receita_despesa), que as rotinas da bovinocultura/apicultura/ovino já refazem desde 2023-01.
Uso (na pasta da Fruticultura):  python scripts/incluir_2023.py"""
import os, re, subprocess, sys, time
from pathlib import Path
import psycopg2
from dotenv import load_dotenv

RAIZ = Path(__file__).resolve().parent.parent
load_dotenv(RAIZ / ".env")
t0 = time.time()
con = psycopg2.connect(host=os.environ.get("LOCAL_DB_HOST", "localhost"), port=os.environ.get("LOCAL_DB_PORT", "5432"),
                       dbname=os.environ["LOCAL_DB_NAME"], user=os.environ.get("LOCAL_DB_USER", "postgres"), password=os.environ["LOCAL_DB_PASS"])
cur = con.cursor()
cur.execute("SELECT MIN(dt_referencia)::date, MAX(dt_referencia)::date, COUNT(*) FROM public.sisateg_receita_despesa WHERE atividade = 'FRUTICULTURA PERENE'")
mn, mx, n = cur.fetchone()
print(f"Tabela combinada (fruticultura): {n} linhas, de {mn} até {mx}")
if mn is None or mn > __import__('datetime').date(2023, 6, 30):
    sys.exit("A tabela combinada local ainda não tem 2023. Antes rode, na pasta da Bovinocultura:  python scripts/incluir_2023.py")
print("\n=== 1/2: recriando o resumo da fruticultura COMPLETO (leva alguns minutos) ===", flush=True)
sql = (RAIZ / "sql" / "criar_resumo_fruticultura.sql").read_text(encoding="utf-8")
for parte in re.split(r";[ \t]*(?:--[^\n]*)?\n", sql):
    corpo = "\n".join(l for l in parte.splitlines() if l.strip() and not l.strip().startswith("--")).strip()
    if not corpo:
        continue
    t1 = time.time()
    cur.execute(parte.replace("%", "%%"))
    print(f"  [{time.time() - t1:6.1f}s] {' '.join(corpo.split())[:70]}", flush=True)
con.commit()
con.close()
print("\n=== 2/2: copiando para o servidor e recriando as views ===", flush=True)
if subprocess.run([sys.executable, "scripts/transferir_resumo.py"], cwd=str(RAIZ)).returncode != 0:
    sys.exit("ERRO ao copiar para o servidor. O servidor continua com os dados anteriores.")
print(f"\nPronto em {int(time.time() - t0)} s. Reinicie o painel e dê Ctrl+F5.")
