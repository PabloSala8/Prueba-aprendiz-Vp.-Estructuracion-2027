"""
Arma la descripción del portafolio y las oportunidades comerciales de un cliente.

Recibe los indicadores del cliente (una fila de la vista v_indicadores_cliente)
y aplica reglas sencillas. Los límites son supuestos y se pueden cambiar acá.
"""

LIQUIDEZ_ALTA = 30                  # % del portafolio en liquidez
LIQUIDEZ_MINIMA = 50_000_000        # pesos, para que valga la pena la alerta
CONCENTRACION_ALTA = 40             # % del portafolio en un solo activo
PATRIMONIO_ALTO = 1_000_000_000     # pesos, para revisar la banca de un cliente Personal
MINIMO_INTERNACIONAL = 500_000_000  # pesos, para ofrecer inversión en el exterior
PORTAFOLIO_PEQUENO = 5_000_000      # pesos


def pesos(valor):
    """Escribe un valor en pesos de forma corta: 8.707,1 millones de pesos."""
    valor = float(valor)
    if valor >= 1_000_000:
        texto = f"{valor / 1_000_000:,.1f}"
        texto = texto.replace(",", "X").replace(".", ",").replace("X", ".")
        return f"{texto} millones de pesos"
    return f"{valor:,.0f}".replace(",", ".") + " pesos"


def porcentaje(valor):
    """Escribe un porcentaje con coma decimal: 99,9%."""
    return f"{float(valor):.1f}".replace(".", ",") + "%"


def describir(ind):
    """Párrafo corto que resume el portafolio del cliente."""
    frases = [
        f"Cliente de Banca {ind['banca']} con un portafolio total de cerca de {pesos(ind['total_cop'])} "
        f"en {ind['posiciones']} {'posición' if ind['posiciones'] == 1 else 'posiciones'}."
    ]

    if ind["pct_internacional"] >= 99.5:
        frases.append("Casi todo está invertido en el exterior.")
    elif ind["pct_internacional"] > 0:
        frases.append(f"El {porcentaje(ind['pct_internacional'])} está invertido en el exterior y el resto en Colombia.")
    else:
        frases.append("Todo su portafolio está en Colombia.")

    if ind["activo_mayor"]:
        nombre = ind["activo_mayor"]
        if len(nombre) > 45:
            nombre = nombre[:45] + "..."
        frases.append(f"Su posición más grande es {nombre}, que pesa el {porcentaje(ind['pct_mayor'])} del total.")

    if ind["pct_liquidez"] > 0:
        frases.append(f"Tiene el {porcentaje(ind['pct_liquidez'])} en liquidez.")

    frases.append(
        f"Por los activos que tiene, su portafolio se comporta como uno {ind['perfil_calculado']} "
        f"(volatilidad de {porcentaje(ind['volatilidad'])} al año)."
    )
    return " ".join(frases)


def oportunidades(ind):
    """Lista de oportunidades comerciales del cliente. Cada una tiene un título y un texto."""
    lista = []
    total = float(ind["total_cop"])
    es_empresa = ind["banca"] in ("Empresas", "Pymes")

    # 1. Perfil de riesgo
    if ind["resultado"] == "Sin perfil":
        lista.append({
            "titulo": "Definir el perfil de riesgo",
            "texto": f"El cliente no tiene perfil de riesgo registrado. Por los activos que tiene hoy se estima "
                     f"un perfil {ind['perfil_calculado']}. Sirve como punto de partida para hacerle el perfilamiento.",
        })
    elif ind["resultado"] == "Más riesgo que su perfil":
        lista.append({
            "titulo": "Portafolio más riesgoso que su perfil",
            "texto": f"Su perfil es {ind['perfil_declarado']} pero su portafolio se comporta como {ind['perfil_calculado']}. "
                     f"Vale la pena revisarlo con el cliente: actualizar el perfil o bajar el riesgo con renta fija "
                     f"o fondos conservadores.",
        })
    elif ind["resultado"] == "Menos riesgo que su perfil" and total >= PORTAFOLIO_PEQUENO:
        lista.append({
            "titulo": "Tiene espacio para tomar más riesgo",
            "texto": f"Su perfil es {ind['perfil_declarado']} pero su portafolio se comporta como {ind['perfil_calculado']}. "
                     f"Se le pueden mostrar alternativas con mayor rentabilidad esperada, como fondos de renta variable "
                     f"o notas estructuradas.",
        })

    # 2. Vencimientos cercanos en el portafolio internacional
    if ind["vencimientos"] > 0:
        valor = f"{float(ind['vence_usd']):,.0f}".replace(",", ".")
        if ind["vencimientos"] == 1:
            cuantas = "le vence 1 posición"
        else:
            cuantas = f"le vencen {ind['vencimientos']} posiciones"
        lista.append({
            "titulo": "Vencimientos cercanos",
            "texto": f"En los 6 meses siguientes a la fecha de corte {cuantas} por "
                     f"USD {valor}. La primera vence el {ind['proximo_vencimiento']:%d/%m/%Y}, a "
                     f"{ind['dias_para_vencer']} días. Es el momento de proponerle en qué reinvertir.",
        })

    # 3. Mucha plata en liquidez
    if ind["pct_liquidez"] >= LIQUIDEZ_ALTA and ind["liquidez_cop"] >= LIQUIDEZ_MINIMA:
        if es_empresa:
            lista.append({
                "titulo": "Excedentes de tesorería",
                "texto": f"Tiene {pesos(ind['liquidez_cop'])} en liquidez ({porcentaje(ind['pct_liquidez'])} del portafolio). "
                         f"En una empresa suele ser la caja del negocio, pero si una parte no la necesita pronto "
                         f"se le pueden ofrecer CDTs o fondos a plazo.",
            })
        else:
            lista.append({
                "titulo": "Liquidez alta",
                "texto": f"Tiene {pesos(ind['liquidez_cop'])} en liquidez ({porcentaje(ind['pct_liquidez'])} del portafolio). "
                         f"Es plata que está rentando poco: se le puede ofrecer un CDT, un fondo de renta fija "
                         f"o una nota estructurada según su perfil.",
            })

    # 4. Portafolio concentrado en un solo activo
    if ind["activo_mayor"] and ind["pct_mayor"] >= CONCENTRACION_ALTA:
        lista.append({
            "titulo": "Portafolio concentrado",
            "texto": f"El {porcentaje(ind['pct_mayor'])} está en un solo activo ({ind['activo_mayor']}). "
                     f"Se le puede proponer diversificar con fondos o ETFs.",
        })

    # 5. Cliente de Banca Personal con un patrimonio alto
    if ind["banca"] == "Personal" and total >= PATRIMONIO_ALTO:
        lista.append({
            "titulo": "Revisar la banca del cliente",
            "texto": f"Está en Banca Personal pero tiene cerca de {pesos(total)} invertidos. "
                     f"Por el tamaño podría atenderse en Preferencial o Privada.",
        })

    # 6. Persona con un portafolio grande que no tiene nada en el exterior
    if ind["pct_internacional"] == 0 and total >= MINIMO_INTERNACIONAL and not es_empresa:
        lista.append({
            "titulo": "Diversificación internacional",
            "texto": "Todo su portafolio está en Colombia. Con este monto se le puede ofrecer "
                     "una cuenta de inversión en el exterior.",
        })

    # 7. Portafolio muy pequeño
    if total < PORTAFOLIO_PEQUENO:
        lista.append({
            "titulo": "Portafolio pequeño",
            "texto": "Tiene menos de 5 millones de pesos invertidos. Se puede buscar que traiga más recursos, "
                     "por ejemplo con un plan de ahorro periódico en un fondo.",
        })

    return lista
