"""
Carga los archivos .csv de la carpeta data/ a Postgres.

Por cada archivo crea una tabla con el mismo nombre y le mete los datos.
Todo se carga como texto, tal cual viene. La limpieza se hace después en SQL.

Uso: python scripts/cargar_datos.py
"""
import os
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine

load_dotenv()

CARPETA_DATOS = Path(__file__).parent.parent / "data"

url = (
    f"postgresql+psycopg2://{os.getenv('DB_USER')}:{os.getenv('DB_PASSWORD')}"
    f"@{os.getenv('DB_HOST')}:{os.getenv('DB_PORT')}/{os.getenv('DB_NAME')}"
)
conexion = create_engine(url)

for archivo in sorted(CARPETA_DATOS.glob("*.csv")):
    tabla = archivo.stem  # nombre del archivo sin el .csv

    # dtype=str y keep_default_na=False para que pandas no cambie ningún valor
    datos = pd.read_csv(archivo, dtype=str, keep_default_na=False)

    # si la tabla ya existe la reemplaza, así el script se puede correr varias veces
    datos.to_sql(tabla, conexion, if_exists="replace", index=False)

    print(f"{tabla}: {len(datos)} filas cargadas")
