# Prueba aprendiz - Vp. Estructuración 2027

Este repositorio tiene mi solución a la prueba de Analítica de Inversiones de Valores Bancolombia.

## Qué entendí de la prueba

Los gerentes comerciales tienen la información de sus clientes repartida en varios archivos y con códigos que no son fáciles de leer. La idea es construir una herramienta que les ordene esa información y les muestre el portafolio de cada cliente, tanto el local (en pesos) como el internacional (en dólares).

Para eso la prueba pide:

1. Crear una base de datos en Postgres y cargar los 5 archivos con Python.
2. Limpiar y unir la información con SQL.
3. Hacer una aplicación en Django para ver el portafolio de cada cliente.
4. Construir un modelo que aporte algo más sobre los clientes, usando datos de mercado.

## Exploración de los datos

Antes de tocar la base de datos revisé los archivos en un notebook (`notebooks/01_eda.ipynb`) para saber qué problemas traían. Lo principal que encontré:

- Cerca del 10% de las filas de los históricos están repetidas.
- Hay unas pocas filas con los valores corridos de columna. No las reparo, las separo.
- El código `10007` es en realidad Fiducuenta (`1007`) y PFCEMARGOS aparece en los datos como `1015`, no como `1115`.
- Varios IDs de cliente vienen en notación científica (`1.00114E+12`) y no se pueden recuperar.
- En el archivo internacional, la carga del 1 de marzo trae cada posición muchas veces, así que solo sirve la última carga de cada cliente.
- El portafolio internacional pesa mucho más que el local (cerca del 87% del total).

## Base de datos y carga

La base de datos corre en Postgres con Docker, así no hay que instalar nada más. El script `scripts/cargar_datos.py` recorre la carpeta `data/`, crea una tabla por cada archivo con el mismo nombre y carga los datos.

Todo lo cargo como texto, tal cual viene en los archivos, porque quiero que la limpieza quede hecha en SQL y no en Python.

## Limpieza en SQL

La limpieza está en la carpeta `sql/`, en archivos numerados que se corren en orden:

- `01_catalogos.sql`: quita los repetidos de los catálogos y corrige el código de PFCEMARGOS.
- `02_macroactivos.sql`: limpia el portafolio local. Quita duplicados, separa las filas con problemas en una tabla de rechazadas, corrige el código de Fiducuenta y arregla los valores que se duplican o pierden un dígito un solo día (comparando con el día anterior y el siguiente).
- `03_internacional.sql`: limpia el portafolio internacional y le pone a cada activo su tipo (bono, fondo, acción, etc.), porque el archivo no lo trae.
- `04_portafolios.sql`: crea las vistas con el portafolio de cada cliente a su última fecha, que es lo que usa la aplicación.

Las filas que no pude usar no las borro, quedan en las tablas `rechazadas_macroactivos` (51 filas) y `rechazadas_internacional` (3 filas) con el motivo.

Después de la limpieza quedan 29 clientes con portafolio local (unos 5.096 millones de pesos al 15 de mayo de 2024) y 12 de ellos también tienen portafolio internacional (unos 8,8 millones de dólares al 30 de mayo de 2024).

## Cómo correr el proyecto

1. Poner los 5 archivos `.csv` en una carpeta `data/`.
2. Copiar `.env.example` como `.env`.
3. Instalar las librerías: `pip install -r requirements.txt`
4. Levantar la base de datos: `docker compose up -d`
5. Cargar los datos: `python scripts/cargar_datos.py`
6. Correr la limpieza: `python scripts/ejecutar_sql.py`

## Avance

- [x] Exploración de los datos
- [x] Base de datos y carga
- [x] Limpieza en SQL
- [ ] Aplicación en Django
- [ ] Modelo

Los datos de la prueba no están en el repositorio.
