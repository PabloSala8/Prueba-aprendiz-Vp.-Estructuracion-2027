-- Evolución en el tiempo: cómo se movieron los activos de cada cliente en el periodo analizado

-- 1. Cambio diario de cada serie
CREATE OR REPLACE VIEW v_cambios_diarios AS
-- activos con precio en Yahoo Finance
SELECT ticker AS serie,
       'Yahoo Finance' AS origen,
       fecha,
       precio / LAG(precio) OVER (PARTITION BY ticker ORDER BY fecha) - 1 AS cambio
FROM precios_mercado

UNION ALL

-- FICs y CDTs locales: promedio del cambio diario del saldo de los clientes que tienen el activo
-- (sin los cambios de más de 1%, que son aportes o retiros)
SELECT serie,
       'Saldos de la prueba' AS origen,
       fecha,
       AVG(cambio) AS cambio
FROM (
    SELECT macroactivo || '|' || COALESCE(cod_activo, '') AS serie,
           fecha,
           aba / NULLIF(LAG(aba) OVER (PARTITION BY id_sistema_cliente, macroactivo, cod_activo ORDER BY fecha), 0) - 1
               AS cambio
    FROM limpio_macroactivos
    WHERE macroactivo IN ('FICs', 'Renta Fija')
) saldos
WHERE ABS(cambio) <= 0.01
GROUP BY serie, fecha;

-- 2. Para cada cliente, cuánto valdrían hoy 100 invertidos al inicio del periodo
--    en las posiciones que tiene, con los pesos actuales de su portafolio.
--    Se calcula aparte para los activos con precio de mercado y para los FICs y CDTs,
--    porque sus datos cubren fechas distintas.
CREATE OR REPLACE VIEW v_evolucion_cliente AS
WITH pesos AS (
    SELECT id_sistema_cliente,
           serie,
           CASE WHEN ticker IS NOT NULL THEN 'Yahoo Finance' ELSE 'Saldos de la prueba' END AS origen,
           SUM(valor_cop) AS valor
    FROM v_posiciones_riesgo
    GROUP BY 1, 2, 3
),
con_peso AS (
    SELECT *, valor / SUM(valor) OVER (PARTITION BY id_sistema_cliente, origen) AS peso
    FROM pesos
),
diario AS (
    -- cambio de cada día: promedio de los cambios de sus activos según el peso de cada uno
    SELECT p.id_sistema_cliente, p.origen, c.fecha,
           SUM(p.peso * c.cambio) AS cambio
    FROM con_peso p
    JOIN v_cambios_diarios c ON c.serie = p.serie
    WHERE c.cambio IS NOT NULL
    GROUP BY 1, 2, 3
)
SELECT id_sistema_cliente,
       origen,
       fecha,
       -- se acumulan los cambios diarios empezando en 100
       100 * EXP(SUM(LN(1 + cambio)) OVER (PARTITION BY id_sistema_cliente, origen ORDER BY fecha)) AS indice
FROM diario;
