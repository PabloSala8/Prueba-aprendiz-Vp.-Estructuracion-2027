-- Limpieza de los catálogos

-- Banca: la fila PR / Privada viene repetida
DROP TABLE IF EXISTS limpio_banca CASCADE;
CREATE TABLE limpio_banca AS
SELECT DISTINCT cod_banca, banca
FROM catalogo_banca;

-- Perfil de riesgo: viene bien, solo lo copio
DROP TABLE IF EXISTS limpio_perfil_riesgo CASCADE;
CREATE TABLE limpio_perfil_riesgo AS
SELECT cod_perfil_riesgo, perfil_riesgo
FROM cat_perfil_riesgo;

-- Activos:
--   CEMARGOS aparece con 1003 y 1013, pero en los datos solo se usa 1003
--   PFCEMARGOS dice 1115, pero en los datos aparece como 1015
DROP TABLE IF EXISTS limpio_activos CASCADE;
CREATE TABLE limpio_activos AS
SELECT
    CASE WHEN cod_activo = '1115' THEN '1015' ELSE cod_activo END AS cod_activo,
    activo
FROM catalogo_activos
WHERE cod_activo <> '1013';
