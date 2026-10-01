-- Limpieza del portafolio local (historico_aba_macroactivos)

-- 1. Quito las filas duplicadas exactas y reviso el formato de cada columna
DROP TABLE IF EXISTS macro_revisada CASCADE;
CREATE TABLE macro_revisada AS
SELECT
    *,
    CASE
        WHEN ingestion_month !~ '^[0-9]{1,2}$' OR ingestion_day !~ '^[0-9]{1,2}$' THEN 'fecha'
        WHEN year NOT IN ('2023', '2024') OR month <> ingestion_month THEN 'año o mes'
        WHEN id_sistema_cliente !~ '^[0-9]{10,13}$'
             AND id_sistema_cliente !~ '^[0-9]\.[0-9]+E\+[0-9]+$' THEN 'id del cliente'
        WHEN macroactivo NOT IN ('Renta Variable', 'Renta Fija', 'FICs') THEN 'macroactivo'
        WHEN cod_activo !~ '^[0-9]+$' AND cod_activo <> 'None' THEN 'código del activo'
        WHEN aba !~ '^[0-9]+(\.[0-9]+)?$' THEN 'aba'
        WHEN cod_perfil_riesgo NOT IN ('1466', '1467', '1468', '1469', 'None') THEN 'perfil de riesgo'
        WHEN cod_banca NOT IN ('PN', 'PR', 'PF', 'PY', 'EG') THEN 'banca'
    END AS problema
FROM (SELECT DISTINCT * FROM historico_aba_macroactivos) sin_duplicados;

-- 2. Las filas con problemas quedan en una tabla aparte (no las reparo)
DROP TABLE IF EXISTS rechazadas_macroactivos CASCADE;
CREATE TABLE rechazadas_macroactivos AS
SELECT *
FROM macro_revisada
WHERE problema IS NOT NULL;

-- 3. Tabla limpia
DROP TABLE IF EXISTS limpio_macroactivos CASCADE;
CREATE TABLE limpio_macroactivos AS
WITH con_tipos AS (
    -- paso los textos a fechas y números y corrijo los códigos
    SELECT
        make_date(ingestion_year::int, ingestion_month::int, ingestion_day::int) AS fecha,
        -- este ID viene con un cero menos una sola vez
        CASE WHEN id_sistema_cliente = '1002203023' THEN '10020203023'
             ELSE id_sistema_cliente END AS id_sistema_cliente,
        macroactivo,
        -- 10007 es Fiducuenta (1007) con un cero de más
        CASE WHEN cod_activo = '10007' THEN '1007'
             ELSE NULLIF(cod_activo, 'None') END AS cod_activo,
        aba::numeric AS aba,
        -- el perfil None lo dejo como SIN DEFINIR (1466)
        CASE WHEN cod_perfil_riesgo = 'None' THEN '1466'
             ELSE cod_perfil_riesgo END AS cod_perfil_riesgo,
        cod_banca
    FROM macro_revisada
    WHERE problema IS NULL
),
medianas AS (
    SELECT id_sistema_cliente, macroactivo, cod_activo,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY aba) AS mediana
    FROM con_tipos
    GROUP BY id_sistema_cliente, macroactivo, cod_activo
),
numeradas AS (
    -- si un cliente tiene el mismo activo dos veces el mismo día,
    -- me quedo con el valor que más se parece al resto de la serie
    SELECT c.*,
           ROW_NUMBER() OVER (
               PARTITION BY c.id_sistema_cliente, c.macroactivo, c.cod_activo, c.fecha
               ORDER BY ABS(c.aba - m.mediana)
           ) AS numero
    FROM con_tipos c
    JOIN medianas m
      ON m.id_sistema_cliente = c.id_sistema_cliente
     AND m.macroactivo = c.macroactivo
     AND m.cod_activo IS NOT DISTINCT FROM c.cod_activo
),
con_vecinos AS (
    -- traigo el valor del día anterior y del día siguiente
    SELECT *,
           LAG(aba)  OVER (PARTITION BY id_sistema_cliente, macroactivo, cod_activo ORDER BY fecha) AS aba_ayer,
           LEAD(aba) OVER (PARTITION BY id_sistema_cliente, macroactivo, cod_activo ORDER BY fecha) AS aba_manana
    FROM numeradas
    WHERE numero = 1
)
SELECT
    fecha,
    id_sistema_cliente,
    macroactivo,
    cod_activo,
    CASE
        -- el valor se duplica un solo día: lo divido por 2
        WHEN aba / NULLIF(aba_ayer, 0) BETWEEN 1.8 AND 2.2
         AND aba / NULLIF(aba_manana, 0) BETWEEN 1.8 AND 2.2 THEN aba / 2
        -- al valor le falta un dígito un solo día: uso el del día anterior
        WHEN aba * 10 / NULLIF(aba_ayer, 0) BETWEEN 0.95 AND 1.05
         AND aba * 10 / NULLIF(aba_manana, 0) BETWEEN 0.95 AND 1.05 THEN aba_ayer
        -- al valor le faltan dos dígitos un solo día
        WHEN aba * 100 / NULLIF(aba_ayer, 0) BETWEEN 0.95 AND 1.05
         AND aba * 100 / NULLIF(aba_manana, 0) BETWEEN 0.95 AND 1.05 THEN aba_ayer
        ELSE aba
    END AS aba,
    aba AS aba_original,
    cod_perfil_riesgo,
    cod_banca
FROM con_vecinos;
