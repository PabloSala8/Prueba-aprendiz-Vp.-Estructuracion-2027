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
- Varios IDs de cliente vienen en notación científica (`1.00114E+12`) porque el archivo pasó por Excel y los últimos dígitos se perdieron. Solo pude recuperar uno, gracias a una fila que traía el ID completo. Los otros 10 quedan incompletos: lo correcto sería pedir el archivo de nuevo con el ID como texto.
- Uno de esos IDs incompletos (`1.00114E+12`) tiene dos perfiles de riesgo distintos, así que probablemente son dos clientes que quedaron con el mismo número. Lo dejo como uno solo porque no lo puedo comprobar.
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

## Aplicación en Django

La aplicación está en la carpeta `app/` y se conecta a la misma base de datos. Tiene estas páginas:

- **Consultas SQL:** muestra los archivos de la carpeta `sql/`, deja ver el SQL de cada uno y ejecutarlos con un botón. También muestra cuántas filas tiene cada tabla resultante y sus primeras filas.
- **Portafolio por cliente:** se elige un cliente y muestra su portafolio local en pesos y su portafolio internacional en dólares, cada uno con su fecha de corte, un gráfico de barras y una tabla con el detalle.
- **Riesgo vs perfil:** muestra el resultado del modelo (explicado más abajo).

Los gráficos están hechos con Chart.js, que es de código abierto. Las consultas que usa la página (totales y porcentajes) también están escritas en SQL.

## Modelo: riesgo del portafolio vs perfil del cliente

En la exploración vi que hay clientes con mucha plata invertida y con el perfil de riesgo sin definir, así que quise revisar si el riesgo que de verdad tiene cada portafolio va de acuerdo con el perfil que el cliente tiene registrado.

Cómo lo hice:

1. Descargué de Yahoo Finance un año de precios de los activos de los portafolios (`scripts/descargar_precios.py`), incluyendo las acciones colombianas.
2. Con esos precios calculé la volatilidad anual de cada activo. Para los activos que no tienen precio en bolsa (bonos, fondos, notas estructuradas) usé un ETF parecido.
3. El riesgo del portafolio es el promedio de esas volatilidades según el peso de cada posición, sumando lo local y lo internacional.
4. Menos de 5% lo tomo como conservador, entre 5% y 10% como moderado y más de 10% como agresivo, y eso lo comparo con el perfil registrado.

Todo el cálculo está en `sql/05_modelo_riesgo.sql` y el resultado se ve en la página "Riesgo vs perfil" de la aplicación.

Lo que encontré: de los 29 clientes, 15 no tienen perfil definido (el modelo les sugiere uno), 3 tienen más riesgo del que dice su perfil, 6 tienen menos y 5 están alineados.

Cosas a tener en cuenta:

- Los FICs y CDTs locales no tienen precio en bolsa, así que les puse una volatilidad baja como supuesto (2% y 1%).
- El promedio ponderado no tiene en cuenta que los activos se compensan entre sí (diversificación), entonces el riesgo queda un poco más alto de lo real.
- Los límites de 5% y 10% los escogí yo comparando con ETFs de bonos y de acciones. Se pueden cambiar en el SQL.

## Extra: resumen y oportunidades por cliente

Como la idea de la herramienta es ayudar a generar nuevos negocios, al final de la página de cada cliente agregué un resumen del portafolio y una lista de oportunidades. Salen de reglas sencillas sobre los datos (`sql/06_indicadores.sql` y `app/portafolios/recomendaciones.py`):

- Clientes sin perfil de riesgo: se les estima uno con el modelo, según los activos que tienen.
- Clientes con más o con menos riesgo del que dice su perfil.
- Posiciones internacionales que vencen en los 6 meses siguientes a la fecha de corte.
- Mucha plata en liquidez (en empresas se muestra como excedentes de tesorería).
- Portafolios concentrados en un solo activo.
- Clientes de Banca Personal con montos altos, que podrían atenderse en otra banca.
- Personas con portafolios grandes que no tienen nada en el exterior, y portafolios muy pequeños.

Los límites de cada regla (por ejemplo, desde qué porcentaje la liquidez es "alta") son supuestos míos y están al inicio de `recomendaciones.py`. Son ideas para la conversación con el cliente, no recomendaciones de inversión.

## Cómo correr el proyecto

1. Poner los 5 archivos `.csv` en una carpeta `data/`.
2. Copiar `.env.example` como `.env`.
3. Instalar las librerías: `pip install -r requirements.txt`
4. Levantar la base de datos: `docker compose up -d`
5. Cargar los datos: `python scripts/cargar_datos.py`
6. Correr la limpieza: `python scripts/ejecutar_sql.py`
7. Descargar los precios de mercado (necesita internet): `python scripts/descargar_precios.py`
8. Entrar a la carpeta de la aplicación: `cd app`
9. Crear las tablas que necesita Django: `python manage.py migrate`
10. Abrir la aplicación: `python manage.py runserver` y entrar a http://127.0.0.1:8000


Los datos de la prueba no están en el repositorio.
