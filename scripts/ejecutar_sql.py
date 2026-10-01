"""
Ejecuta en orden los archivos .sql de la carpeta sql/.

Uso: python scripts/ejecutar_sql.py
"""
import os
from pathlib import Path

import psycopg2
from dotenv import load_dotenv

load_dotenv()

CARPETA_SQL = Path(__file__).parent.parent / "sql"

conexion = psycopg2.connect(
    dbname=os.getenv("DB_NAME"),
    user=os.getenv("DB_USER"),
    password=os.getenv("DB_PASSWORD"),
    host=os.getenv("DB_HOST"),
    port=os.getenv("DB_PORT"),
)

with conexion, conexion.cursor() as cursor:
    for archivo in sorted(CARPETA_SQL.glob("*.sql")):
        cursor.execute(archivo.read_text())
        print(f"{archivo.name}: ok")

conexion.close()
