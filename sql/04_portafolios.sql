-- Vistas que usa la aplicación: el portafolio de cada cliente a su última fecha

-- Portafolio local (COP)
CREATE OR REPLACE VIEW v_portafolio_local AS
SELECT
    m.id_sistema_cliente,
    m.fecha,
    m.macroactivo,
    COALESCE(a.activo, 'No identificado') AS activo,
    m.aba,
    b.banca,
    p.perfil_riesgo
FROM limpio_macroactivos m
LEFT JOIN limpio_activos a ON a.cod_activo = m.cod_activo
LEFT JOIN limpio_banca b ON b.cod_banca = m.cod_banca
LEFT JOIN limpio_perfil_riesgo p ON p.cod_perfil_riesgo = m.cod_perfil_riesgo
WHERE m.fecha = (
    SELECT MAX(u.fecha)
    FROM limpio_macroactivos u
    WHERE u.id_sistema_cliente = m.id_sistema_cliente
);

-- Portafolio internacional (USD)
-- Solo uso la última carga de cada cliente, porque la del 1 de marzo trae
-- cada posición muchas veces y no se sabe de qué día es cada fila
CREATE OR REPLACE VIEW v_portafolio_internacional AS
SELECT
    i.id_sistema_cliente,
    i.fecha,
    i.tipo_activo,
    i.nombre_activo,
    i.simbol,
    i.isin,
    i.cantidad,
    i.valor_mercado,
    i.fecha_vencimiento,
    i.tasa_cupon
FROM limpio_internacional i
WHERE i.fecha = (
    SELECT MAX(u.fecha)
    FROM limpio_internacional u
    WHERE u.id_sistema_cliente = i.id_sistema_cliente
);

-- Lista de clientes con sus totales
CREATE OR REPLACE VIEW v_clientes AS
WITH local AS (
    SELECT id_sistema_cliente,
           MAX(fecha) AS fecha_local,
           SUM(aba) AS total_cop,
           -- si un cliente tiene más de un perfil o banca, dejo el de su posición más grande
           (ARRAY_AGG(banca ORDER BY aba DESC))[1] AS banca,
           (ARRAY_AGG(perfil_riesgo ORDER BY aba DESC))[1] AS perfil_riesgo
    FROM v_portafolio_local
    GROUP BY id_sistema_cliente
),
internacional AS (
    SELECT id_sistema_cliente,
           MAX(fecha) AS fecha_internacional,
           SUM(valor_mercado) AS total_usd
    FROM v_portafolio_internacional
    GROUP BY id_sistema_cliente
)
SELECT
    COALESCE(l.id_sistema_cliente, i.id_sistema_cliente) AS id_sistema_cliente,
    l.banca,
    COALESCE(l.perfil_riesgo, 'SIN DEFINIR') AS perfil_riesgo,
    l.fecha_local,
    COALESCE(l.total_cop, 0) AS total_cop,
    i.fecha_internacional,
    COALESCE(i.total_usd, 0) AS total_usd
FROM local l
FULL OUTER JOIN internacional i ON i.id_sistema_cliente = l.id_sistema_cliente;
