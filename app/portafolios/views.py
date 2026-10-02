from django.conf import settings
from django.db import connection
from django.shortcuts import redirect, render

from .recomendaciones import describir, oportunidades

# Los archivos .sql están en la raíz del repositorio
CARPETA_SQL = settings.BASE_DIR.parent / "sql"

# Tablas y vistas que crean los archivos .sql y que se pueden revisar desde la página
TABLAS = [
    "limpio_banca",
    "limpio_perfil_riesgo",
    "limpio_activos",
    "limpio_macroactivos",
    "rechazadas_macroactivos",
    "limpio_internacional",
    "rechazadas_internacional",
    "v_portafolio_local",
    "v_portafolio_internacional",
    "v_clientes",
    "precios_mercado",
    "v_volatilidad_tickers",
    "v_volatilidad_locales",
    "v_posiciones_riesgo",
    "v_modelo_riesgo",
    "v_indicadores_cliente",
    "v_cambios_diarios",
    "v_evolucion_cliente",
]


def consultar(sql, parametros=None):
    """Ejecuta un SELECT y devuelve las filas como una lista de diccionarios."""
    with connection.cursor() as cursor:
        cursor.execute(sql, parametros)
        columnas = [columna[0] for columna in cursor.description]
        return [dict(zip(columnas, fila)) for fila in cursor.fetchall()]


def inicio(request):
    return redirect("portafolio")


def consultas(request):
    """Página para ver y ejecutar los archivos .sql de la limpieza."""
    archivos = sorted(CARPETA_SQL.glob("*.sql"))
    mensaje = None
    error = None

    # Si se oprimió un botón, ejecuto el archivo elegido (o todos en orden)
    if request.method == "POST":
        elegido = request.POST.get("archivo")
        if elegido == "todos":
            por_ejecutar = archivos
        else:
            por_ejecutar = [a for a in archivos if a.name == elegido]

        try:
            with connection.cursor() as cursor:
                for archivo in por_ejecutar:
                    cursor.execute(archivo.read_text())
            mensaje = "Se ejecutó: " + ", ".join(a.name for a in por_ejecutar)
        except Exception as e:
            error = str(e)

    # Lista de archivos con su descripción (la primera línea del archivo) y su contenido
    lista_archivos = []
    for archivo in archivos:
        contenido = archivo.read_text()
        descripcion = contenido.splitlines()[0].replace("--", "").strip()
        lista_archivos.append({"nombre": archivo.name, "descripcion": descripcion, "contenido": contenido})

    # Cuántas filas tiene cada tabla o vista (si ya existe)
    existentes = consultar("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'")
    existentes = [fila["table_name"] for fila in existentes]
    lista_tablas = []
    for tabla in TABLAS:
        filas = None
        if tabla in existentes:
            filas = consultar(f"SELECT COUNT(*) AS filas FROM {tabla}")[0]["filas"]
        lista_tablas.append({"nombre": tabla, "filas": filas})

    # Vista previa de una tabla (solo se permiten las de la lista TABLAS)
    tabla_elegida = request.GET.get("tabla")
    vista_previa = None
    if tabla_elegida in TABLAS and tabla_elegida in existentes:
        vista_previa = consultar(f"SELECT * FROM {tabla_elegida} LIMIT 20")

    return render(request, "portafolios/consultas.html", {
        "archivos": lista_archivos,
        "tablas": lista_tablas,
        "tabla_elegida": tabla_elegida,
        "vista_previa": vista_previa,
        "mensaje": mensaje,
        "error": error,
    })


def portafolio(request):
    """Página para elegir un cliente y ver su portafolio local e internacional."""
    # Los IDs en notación científica (con E+) vienen incompletos desde el archivo original
    clientes = consultar("""
        SELECT *, id_sistema_cliente LIKE '%E+%' AS id_incompleto
        FROM v_clientes
        ORDER BY total_usd DESC, total_cop DESC
    """)
    # Todos los clientes tienen portafolio local, y algunos tienen además internacional
    con_internacional = [c for c in clientes if c["total_usd"] > 0]
    solo_local = [c for c in clientes if c["total_usd"] == 0]
    grupos = [
        ("Con portafolio local e internacional", con_internacional),
        ("Solo portafolio local", solo_local),
    ]
    id_cliente = request.GET.get("cliente")

    cliente = None
    local = []
    internacional = []
    internacional_por_tipo = []
    indicadores = None
    descripcion = None
    lista_oportunidades = []
    riesgo_posiciones = []
    evolucion = []

    if id_cliente:
        encontrados = consultar("SELECT * FROM v_clientes WHERE id_sistema_cliente = %s", [id_cliente])
        if encontrados:
            cliente = encontrados[0]

        local = consultar("""
            SELECT activo, macroactivo, aba,
                   ROUND(100 * aba / SUM(aba) OVER (), 1) AS porcentaje
            FROM v_portafolio_local
            WHERE id_sistema_cliente = %s
            ORDER BY aba DESC
        """, [id_cliente])

        internacional = consultar("""
            SELECT tipo_activo, nombre_activo, valor_mercado, fecha_vencimiento,
                   ROUND(100 * valor_mercado / SUM(valor_mercado) OVER (), 1) AS porcentaje
            FROM v_portafolio_internacional
            WHERE id_sistema_cliente = %s
            ORDER BY valor_mercado DESC
        """, [id_cliente])

        internacional_por_tipo = consultar("""
            SELECT tipo_activo, SUM(valor_mercado) AS valor
            FROM v_portafolio_internacional
            WHERE id_sistema_cliente = %s
            GROUP BY tipo_activo
            ORDER BY valor DESC
        """, [id_cliente])

        # Descripción y oportunidades (necesitan los precios de mercado del modelo)
        hay_precios = consultar("SELECT COUNT(*) AS filas FROM precios_mercado")[0]["filas"] > 0
        if cliente and hay_precios:
            indicadores = consultar(
                "SELECT * FROM v_indicadores_cliente WHERE id_sistema_cliente = %s", [id_cliente]
            )[0]
            descripcion = describir(indicadores)
            lista_oportunidades = oportunidades(indicadores)

            # Volatilidad y rendimiento de cada posición, con el periodo y la fuente de los datos
            riesgo_posiciones = consultar("""
                SELECT nombre, ticker, fuente, desde, hasta,
                       ROUND(100 * valor_cop / SUM(valor_cop) OVER (), 1) AS peso,
                       ROUND((volatilidad * 100)::numeric, 1) AS volatilidad,
                       ROUND((rendimiento * 100)::numeric, 1) AS rendimiento
                FROM v_posiciones_riesgo
                WHERE id_sistema_cliente = %s
                ORDER BY valor_cop DESC
            """, [id_cliente])

            # Evolución en el tiempo: una serie para los activos con precio en Yahoo Finance
            # y otra para los FICs y CDTs locales (que salen de los saldos de la prueba)
            for origen in ["Yahoo Finance", "Saldos de la prueba"]:
                puntos = consultar("""
                    SELECT fecha, ROUND(indice::numeric, 2) AS indice
                    FROM v_evolucion_cliente
                    WHERE id_sistema_cliente = %s AND origen = %s
                    ORDER BY fecha
                """, [id_cliente, origen])
                if not puntos:
                    continue

                # posiciones del cliente que entran en esta serie
                if origen == "Yahoo Finance":
                    posiciones = [p for p in riesgo_posiciones if p["ticker"]]
                else:
                    posiciones = [p for p in riesgo_posiciones if not p["ticker"]]
                desde = min(p["desde"] for p in posiciones)

                evolucion.append({
                    "origen": origen,
                    "id_canvas": "grafico-evolucion-" + str(len(evolucion) + 1),
                    "desde": desde,
                    "hasta": puntos[-1]["fecha"],
                    "valor_final": puntos[-1]["indice"],
                    "cobertura": sum(p["peso"] for p in posiciones),
                    # el primer punto es 100 en la fecha de inicio
                    "etiquetas": [f"{desde:%d/%m/%Y}"] + [f"{p['fecha']:%d/%m/%Y}" for p in puntos],
                    "valores": [100.0] + [float(p["indice"]) for p in puntos],
                })

    # Datos para los gráficos (Chart.js los lee desde la plantilla)
    graficos = {
        "local": {
            "etiquetas": [fila["activo"] for fila in local],
            "valores": [float(fila["aba"]) for fila in local],
        },
        "internacional": {
            "etiquetas": [fila["tipo_activo"] for fila in internacional_por_tipo],
            "valores": [float(fila["valor"]) for fila in internacional_por_tipo],
        },
        "evolucion": [
            {"id_canvas": e["id_canvas"], "etiquetas": e["etiquetas"], "valores": e["valores"]}
            for e in evolucion
        ],
    }

    return render(request, "portafolios/portafolio.html", {
        "grupos": grupos,
        "id_cliente": id_cliente,
        "cliente": cliente,
        "local": local,
        "internacional": internacional,
        "graficos": graficos,
        "indicadores": indicadores,
        "descripcion": descripcion,
        "oportunidades": lista_oportunidades,
        "riesgo_posiciones": riesgo_posiciones,
        "evolucion": evolucion,
        # alto de cada gráfico según el número de barras
        "alto_local": 70 + 38 * len(local),
        "alto_internacional": 70 + 38 * len(internacional_por_tipo),
    })


def riesgo(request):
    """Página del modelo: riesgo de cada portafolio comparado con el perfil del cliente."""
    hay_precios = consultar("SELECT COUNT(*) AS filas FROM precios_mercado")[0]["filas"] > 0

    clientes = []
    resumen = []
    detalle = []
    id_cliente = request.GET.get("cliente")

    if hay_precios:
        clientes = consultar("SELECT * FROM v_modelo_riesgo ORDER BY volatilidad DESC")

        resumen = consultar("""
            SELECT resultado, COUNT(*) AS clientes
            FROM v_modelo_riesgo
            GROUP BY resultado
            ORDER BY clientes DESC
        """)

        # Detalle de un cliente: cada posición con su peso y la volatilidad que se le asignó
        if id_cliente:
            detalle = consultar("""
                SELECT portafolio, nombre, clase, ticker, fuente,
                       ROUND(100 * valor_cop / SUM(valor_cop) OVER (), 1) AS peso,
                       ROUND((volatilidad * 100)::numeric, 1) AS volatilidad,
                       ROUND((rendimiento * 100)::numeric, 1) AS rendimiento
                FROM v_posiciones_riesgo
                WHERE id_sistema_cliente = %s
                ORDER BY valor_cop DESC
            """, [id_cliente])

    grafico = {
        "etiquetas": [fila["id_sistema_cliente"] for fila in clientes],
        "valores": [float(fila["volatilidad"]) for fila in clientes],
    }

    return render(request, "portafolios/riesgo.html", {
        "hay_precios": hay_precios,
        "clientes": clientes,
        "resumen": resumen,
        "id_cliente": id_cliente,
        "detalle": detalle,
        "grafico": grafico,
        "alto_grafico": 70 + 22 * len(clientes),
    })
