-- Modelo: compara el riesgo del portafolio con el perfil de riesgo del cliente

-- Precios de mercado. Esta tabla la llena scripts/descargar_precios.py
CREATE TABLE IF NOT EXISTS precios_mercado (fecha date, ticker text, precio numeric);

-- Nombre en Yahoo Finance de cada acción local
DROP TABLE IF EXISTS tickers_locales CASCADE;
CREATE TABLE tickers_locales (activo text, ticker text);
INSERT INTO tickers_locales VALUES
    ('ECOPETROL', 'ECOPETROL.CL'),
    ('ISA', 'ISA.CL'),
    ('CEMARGOS', 'CEMARGOS.CL'),
    ('CELSIA', 'CELSIA.CL'),
    ('ETB', 'ETB.CL'),
    ('GRUBOLIVAR', 'GRUBOLIVAR.CL'),
    ('PFBCOLOM', 'PFCIBEST.CL'),      -- la preferencial de Bancolombia hoy se llama PFCIBEST
    ('PFCORFICOL', 'PFCORFICOL.CL'),
    ('PFGRUPSURA', 'PFGRUPSURA.CL');

-- Símbolos internacionales que en Yahoo Finance tienen otro nombre,
-- o ETFs europeos que no tienen buen precio y uso uno parecido de Estados Unidos
DROP TABLE IF EXISTS tickers_internacionales CASCADE;
CREATE TABLE tickers_internacionales (simbol text, ticker text, fuente text);
INSERT INTO tickers_internacionales VALUES
    ('BRK B', 'BRK-B', 'Precio del activo'),
    ('SQ', 'XYZ', 'Precio del activo'),       -- Block cambió su símbolo de SQ a XYZ
    ('ISVIF', 'IEF', 'Activo parecido'),      -- bonos del Tesoro de 7 a 10 años
    ('ISZXF', 'IEI', 'Activo parecido'),      -- bonos del Tesoro de 3 a 7 años
    ('ISVQF', 'IGSB', 'Activo parecido'),     -- bonos corporativos de corto plazo
    ('ISQWF', 'QUAL', 'Activo parecido'),     -- acciones de calidad
    ('ISVFF', 'XLV', 'Activo parecido');      -- acciones del sector salud

-- 1. Volatilidad y rendimiento de cada ticker en el año de precios descargado
--    Volatilidad: desviación estándar de los cambios diarios del precio, llevada a un año
--    Rendimiento: último precio contra el primero
CREATE OR REPLACE VIEW v_volatilidad_tickers AS
WITH cambios AS (
    SELECT ticker, fecha, precio,
           precio / LAG(precio) OVER (PARTITION BY ticker ORDER BY fecha) - 1 AS cambio_diario
    FROM precios_mercado
)
SELECT ticker,
       COUNT(cambio_diario) AS dias,
       STDDEV(cambio_diario) * SQRT(252) AS volatilidad,
       (ARRAY_AGG(precio ORDER BY fecha DESC))[1] / (ARRAY_AGG(precio ORDER BY fecha))[1] - 1 AS rendimiento
FROM cambios
GROUP BY ticker;

-- 2. Volatilidad y rendimiento de los FICs y CDTs locales
--    No tienen precio en bolsa, pero los saldos diarios de los clientes muestran cómo se mueve su valor,
--    así que uso la misma fórmula sobre esos saldos.
--    Los cambios de más de 1% en un día no los cuento: son aportes o retiros del cliente, no movimientos del activo.
--    Como entre viernes y lunes pasan tres días, la volatilidad queda un poco más alta de lo real.
CREATE OR REPLACE VIEW v_volatilidad_locales AS
WITH cambios AS (
    SELECT macroactivo, cod_activo,
           aba / NULLIF(LAG(aba) OVER (PARTITION BY id_sistema_cliente, macroactivo, cod_activo ORDER BY fecha), 0) - 1
               AS cambio_diario
    FROM limpio_macroactivos
    WHERE macroactivo IN ('FICs', 'Renta Fija')
)
SELECT macroactivo,
       cod_activo,
       COUNT(cambio_diario) AS dias,
       STDDEV(cambio_diario) * SQRT(252) AS volatilidad,
       AVG(cambio_diario) * 252 AS rendimiento
FROM cambios
WHERE ABS(cambio_diario) <= 0.01
GROUP BY macroactivo, cod_activo;

-- 3. Todas las posiciones (locales e internacionales) en pesos, con su volatilidad y rendimiento
--    Si el activo tiene precio en bolsa uso ese precio.
--    Si no, uso un activo parecido (por ejemplo un ETF de bonos para un bono).
--    Para los FICs y CDTs locales uso los saldos históricos de los mismos datos.
CREATE OR REPLACE VIEW v_posiciones_riesgo AS
WITH posiciones AS (
    SELECT
        l.id_sistema_cliente,
        'Local' AS portafolio,
        l.activo AS nombre,
        l.macroactivo AS clase,
        l.aba AS valor_cop,
        CASE WHEN t.ticker IS NOT NULL THEN t.ticker
             WHEN l.macroactivo = 'Renta Variable' THEN 'ICOLCAP.CL'   -- acciones sin identificar: índice COLCAP
        END AS ticker,
        CASE WHEN t.ticker IS NOT NULL THEN 'Precio del activo'
             WHEN l.macroactivo = 'Renta Variable' THEN 'Activo parecido'
             ELSE 'Saldos históricos'
        END AS fuente,
        -- si un activo tiene muy pocos días de datos, uso el promedio de su macroactivo
        COALESCE(h.volatilidad, (SELECT AVG(x.volatilidad) FROM v_volatilidad_locales x
                                 WHERE x.macroactivo = l.macroactivo)) AS volatilidad_local,
        h.rendimiento AS rendimiento_local
    FROM v_portafolio_local l
    LEFT JOIN tickers_locales t ON t.activo = l.activo
    LEFT JOIN v_volatilidad_locales h ON h.macroactivo = l.macroactivo
                                     AND h.cod_activo IS NOT DISTINCT FROM l.cod_activo

    UNION ALL

    SELECT
        i.id_sistema_cliente,
        'Internacional' AS portafolio,
        i.nombre_activo AS nombre,
        i.tipo_activo AS clase,
        i.valor_mercado * 3867.02 AS valor_cop,   -- TRM del 30 de mayo de 2024 (datos.gov.co)
        CASE
            WHEN t.ticker IS NOT NULL THEN t.ticker
            WHEN i.tipo_activo IN ('Acción', 'ETF') THEN i.simbol
            WHEN i.tipo_activo = 'Liquidez' THEN 'BIL'                  -- letras del Tesoro de muy corto plazo
            WHEN i.tipo_activo = 'Bono del Tesoro EE.UU.' THEN 'SHY'    -- bonos del Tesoro de 1 a 3 años
            WHEN i.tipo_activo = 'Bono' THEN 'CEMB'                     -- bonos corporativos de emergentes en dólares
            WHEN i.tipo_activo = 'Nota estructurada' THEN 'SPY'         -- están atadas a índices de acciones de EE.UU.
            -- fondos mutuos: según el nombre son mixtos, de renta fija o de acciones
            WHEN i.nombre_activo LIKE '%MULTI%ASSET%' OR i.nombre_activo LIKE '%ALLOCATION%'
              OR i.nombre_activo LIKE '%MANAGED INDEX%' THEN 'AOR'
            WHEN i.nombre_activo LIKE '%INCOME%' OR i.nombre_activo LIKE '%BOND%' THEN 'AGG'
            ELSE 'ACWI'
        END AS ticker,
        CASE WHEN t.fuente IS NOT NULL THEN t.fuente
             WHEN i.tipo_activo IN ('Acción', 'ETF') THEN 'Precio del activo'
             ELSE 'Activo parecido'
        END AS fuente,
        NULL AS volatilidad_local,
        NULL AS rendimiento_local
    FROM v_portafolio_internacional i
    LEFT JOIN tickers_internacionales t ON t.simbol = i.simbol
)
SELECT
    p.id_sistema_cliente, p.portafolio, p.nombre, p.clase, p.valor_cop, p.ticker, p.fuente,
    COALESCE(v.volatilidad, p.volatilidad_local) AS volatilidad,
    COALESCE(v.rendimiento, p.rendimiento_local) AS rendimiento
FROM posiciones p
LEFT JOIN v_volatilidad_tickers v ON v.ticker = p.ticker;

-- 4. Riesgo de cada cliente y comparación con su perfil
--    El riesgo del portafolio es el promedio de las volatilidades, ponderado por el valor de cada posición.
--    Menos de 5% lo tomo como conservador, entre 5% y 10% moderado y más de 10% agresivo.
CREATE OR REPLACE VIEW v_modelo_riesgo AS
WITH riesgo AS (
    SELECT id_sistema_cliente,
           SUM(valor_cop) AS total_cop,
           SUM(valor_cop * volatilidad) / SUM(valor_cop) AS volatilidad
    FROM v_posiciones_riesgo
    GROUP BY id_sistema_cliente
),
clasificado AS (
    SELECT r.id_sistema_cliente,
           c.banca,
           c.perfil_riesgo AS perfil_declarado,
           r.total_cop,
           r.volatilidad,
           CASE WHEN r.volatilidad < 0.05 THEN 'CONSERVADOR'
                WHEN r.volatilidad < 0.10 THEN 'MODERADO'
                ELSE 'AGRESIVO'
           END AS perfil_calculado
    FROM riesgo r
    JOIN v_clientes c ON c.id_sistema_cliente = r.id_sistema_cliente
),
niveles (perfil, nivel) AS (
    VALUES ('CONSERVADOR', 1), ('MODERADO', 2), ('AGRESIVO', 3)
)
SELECT
    k.id_sistema_cliente,
    k.banca,
    k.perfil_declarado,
    k.perfil_calculado,
    k.total_cop,
    ROUND((k.volatilidad * 100)::numeric, 1) AS volatilidad,
    CASE
        WHEN d.nivel IS NULL THEN 'Sin perfil'
        WHEN c.nivel = d.nivel THEN 'Alineado'
        WHEN c.nivel > d.nivel THEN 'Más riesgo que su perfil'
        ELSE 'Menos riesgo que su perfil'
    END AS resultado
FROM clasificado k
JOIN niveles c ON c.perfil = k.perfil_calculado
LEFT JOIN niveles d ON d.perfil = k.perfil_declarado;
