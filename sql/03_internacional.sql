-- Limpieza del portafolio internacional (historico_aba_usd_internacional)

-- 1. Quito espacios de los nombres, quito duplicados exactos y reviso el formato
DROP TABLE IF EXISTS usd_revisada CASCADE;
CREATE TABLE usd_revisada AS
SELECT
    *,
    CASE
        WHEN id_sistema_cliente !~ '^[0-9]+$' THEN 'id del cliente'
        WHEN valor_mercado !~ '^-?[0-9]+(\.[0-9]+)?$' THEN 'valor de mercado'
        WHEN fecha_vencimiento !~ '^[0-9]{1,2}/[0-9]{2}/[0-9]{4}$' THEN 'fecha de vencimiento'
    END AS problema
FROM (
    SELECT DISTINCT
        ingestion_year, ingestion_month, ingestion_day, id_sistema_cliente,
        simbol, cusip, isin, TRIM(nombre_activo) AS nombre_activo,
        cantidad, valor_mercado, fecha_vencimiento, tasa_cupon
    FROM historico_aba_usd_internacional
) sin_duplicados;

-- 2. Filas con problemas, aparte
DROP TABLE IF EXISTS rechazadas_internacional CASCADE;
CREATE TABLE rechazadas_internacional AS
SELECT *
FROM usd_revisada
WHERE problema IS NOT NULL;

-- 3. Tabla limpia
DROP TABLE IF EXISTS limpio_internacional CASCADE;
CREATE TABLE limpio_internacional AS
SELECT
    make_date(ingestion_year::int, ingestion_month::int, ingestion_day::int) AS fecha,
    id_sistema_cliente,
    -- 'None' y 'nan' vienen como texto, los dejo vacíos
    NULLIF(NULLIF(simbol, 'None'), 'nan') AS simbol,
    cusip,
    NULLIF(isin, 'Liquidez') AS isin,
    nombre_activo,
    cantidad::numeric AS cantidad,
    valor_mercado::numeric AS valor_mercado,
    -- 1/01/1900 significa que el activo no tiene vencimiento
    CASE WHEN fecha_vencimiento <> '1/01/1900'
         THEN to_date(fecha_vencimiento, 'MM/DD/YYYY') END AS fecha_vencimiento,
    tasa_cupon::numeric AS tasa_cupon,
    -- el archivo no trae la clase de activo, la saco del nombre, el isin y el vencimiento
    CASE
        WHEN isin = 'Liquidez' OR nombre_activo = 'CASH' THEN 'Liquidez'
        WHEN UPPER(nombre_activo) LIKE '%LKD%' OR UPPER(nombre_activo) LIKE '%LNKD%' THEN 'Nota estructurada'
        WHEN fecha_vencimiento <> '1/01/1900' AND UPPER(nombre_activo) LIKE '%TREAS%' THEN 'Bono del Tesoro EE.UU.'
        WHEN fecha_vencimiento <> '1/01/1900' THEN 'Bono'
        -- ' ETF' con espacio antes, porque NETFLIX también contiene las letras ETF
        WHEN UPPER(nombre_activo) LIKE '% ETF%' OR UPPER(nombre_activo) LIKE '%ISHARES%'
          OR UPPER(nombre_activo) LIKE '%SPDR%' OR UPPER(nombre_activo) LIKE '%VANGUARD%' THEN 'ETF'
        WHEN isin LIKE 'LU%' OR isin LIKE 'IE%' THEN 'Fondo mutuo'
        ELSE 'Acción'
    END AS tipo_activo
FROM usd_revisada
WHERE problema IS NULL;
