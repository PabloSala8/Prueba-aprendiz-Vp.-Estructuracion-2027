"""
Descarga de Yahoo Finance los precios de los activos de los portafolios
y los guarda en la tabla precios_mercado.

La lista de tickers sale de la vista v_posiciones_riesgo (sql/05_modelo_riesgo.sql),
así que primero hay que correr scripts/ejecutar_sql.py.

Uso: python scripts/descargar_precios.py
"""
import os

import pandas as pd
import yfinance as yf
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

load_dotenv()

# Un año de precios hasta la última fecha de los portafolios
FECHA_INICIO = "2023-05-30"
FECHA_FIN = "2024-05-31"

url = (
    f"postgresql+psycopg2://{os.getenv('DB_USER')}:{os.getenv('DB_PASSWORD')}"
    f"@{os.getenv('DB_HOST')}:{os.getenv('DB_PORT')}/{os.getenv('DB_NAME')}"
)
conexion = create_engine(url)

tickers = pd.read_sql("SELECT DISTINCT ticker FROM v_posiciones_riesgo WHERE ticker IS NOT NULL", conexion)
tickers = sorted(tickers["ticker"])
print(f"Descargando {len(tickers)} tickers...")

precios = yf.download(tickers, start=FECHA_INICIO, end=FECHA_FIN, auto_adjust=True, progress=False)["Close"]

# Paso de una columna por ticker a una fila por fecha y ticker
tabla = precios.reset_index().melt(id_vars="Date", var_name="ticker", value_name="precio")
tabla = tabla.rename(columns={"Date": "fecha"}).dropna(subset=["precio"])

# Borro lo que había y cargo de nuevo (no reemplazo la tabla porque hay vistas que dependen de ella)
with conexion.begin() as c:
    c.execute(text("TRUNCATE precios_mercado"))
    tabla.to_sql("precios_mercado", c, if_exists="append", index=False)

print(f"{len(tabla)} precios guardados")

sin_precio = [t for t in tickers if t not in set(tabla["ticker"])]
if sin_precio:
    print("Tickers sin precio:", sin_precio)
