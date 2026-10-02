-- Indicadores por cliente para la descripción y las oportunidades que muestra la aplicación

CREATE OR REPLACE VIEW v_indicadores_cliente AS
WITH posiciones AS (
    -- marco qué posiciones son liquidez: el efectivo internacional y los fondos a la vista locales
    SELECT *,
           (clase = 'Liquidez' OR nombre IN ('Fiducuenta', 'Renta Liquidez')) AS es_liquidez
    FROM v_posiciones_riesgo
),
totales AS (
    SELECT id_sistema_cliente,
           COUNT(*) AS posiciones,
           SUM(valor_cop) AS total_cop,
           COALESCE(SUM(valor_cop) FILTER (WHERE portafolio = 'Internacional'), 0) AS internacional_cop,
           COALESCE(SUM(valor_cop) FILTER (WHERE es_liquidez), 0) AS liquidez_cop
    FROM posiciones
    GROUP BY id_sistema_cliente
),
mayores AS (
    -- la posición más grande de cada cliente, sin contar la liquidez
    SELECT id_sistema_cliente, nombre, valor_cop,
           ROW_NUMBER() OVER (PARTITION BY id_sistema_cliente ORDER BY valor_cop DESC) AS numero
    FROM posiciones
    WHERE NOT es_liquidez
),
vencimientos AS (
    -- posiciones internacionales que vencen en los 6 meses siguientes a la fecha de corte
    SELECT id_sistema_cliente,
           COUNT(*) AS vencimientos,
           SUM(valor_mercado) AS vence_usd,
           MIN(fecha_vencimiento) AS proximo_vencimiento,
           MIN(fecha_vencimiento - fecha) AS dias_para_vencer
    FROM v_portafolio_internacional
    WHERE fecha_vencimiento BETWEEN fecha AND fecha + 180
    GROUP BY id_sistema_cliente
)
SELECT
    t.id_sistema_cliente,
    r.banca,
    r.perfil_declarado,
    r.perfil_calculado,
    r.volatilidad,
    r.resultado,
    t.posiciones,
    t.total_cop,
    ROUND(100 * t.internacional_cop / t.total_cop, 1) AS pct_internacional,
    t.liquidez_cop,
    ROUND(100 * t.liquidez_cop / t.total_cop, 1) AS pct_liquidez,
    m.nombre AS activo_mayor,
    ROUND(100 * m.valor_cop / t.total_cop, 1) AS pct_mayor,
    COALESCE(v.vencimientos, 0) AS vencimientos,
    v.vence_usd,
    v.proximo_vencimiento,
    v.dias_para_vencer
FROM totales t
JOIN v_modelo_riesgo r ON r.id_sistema_cliente = t.id_sistema_cliente
LEFT JOIN mayores m ON m.id_sistema_cliente = t.id_sistema_cliente AND m.numero = 1
LEFT JOIN vencimientos v ON v.id_sistema_cliente = t.id_sistema_cliente;
