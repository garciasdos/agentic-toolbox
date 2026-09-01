---
name: gauntlet-audit
description: Audita la red de verificación de un repo al estilo del gauntlet de Uncle Bob y responde "¿puedo confiar en código escrito por agentes sin leerlo?". Mide 9 campos (mutation testing, mutación de la spec, aceptación, CRAP, cobertura, DRY, arquitectura, calidad de tests, spec-first) con madurez 0-4, score global y roadmap. Úsala cuando quieras auditar el gauntlet, medir la madurez de verificación de un repo, saber si puedes dejar de leer el código de tus agentes, o cuando se mencione "gauntlet audit" o "red de verificación".
---

# gauntlet-audit

Auditas el repo actual y entregas un **scorecard de verificación**: para cada uno de los 9 campos del gauntlet, un nivel de madurez 0-4 con evidencia, un score global sobre 36, y un roadmap priorizado para subir niveles.

La pregunta que respondes es: **"¿cómo de fuerte es la red que permitiría no leer el código que escriben los agentes?"**. La confianza debe salir de gates deterministas, no de la lectura.

Es **solo diagnóstico**: no instalas, no modificas configs, no tocas el repo. Solo reportas.

## Reglas

- Haz el análisis **sin preguntar al usuario**. Todo lo que necesites está en el repo.
- **Detección + evidencia, nunca ejecución pesada.** Lee configs, dependencias, CI, hooks, informes commiteados y manifiestos. No corras mutation testing ni suites completas. Comandos read-only baratos (`git log`, `gh run list`, `ls`) sí valen.
- **Nada es N/A.** Un campo sin herramienta o que el repo no practica puntúa 0. El score mide la distancia al gauntlet completo, no al gauntlet cómodo para ese repo.
- Puntúa contra la escalera de `reference/fields.md`, no de memoria. Un nivel se concede solo con evidencia citable (fichero:línea, workflow, informe).

## Cómo trabajar

1. **Detecta el stack.** Lenguajes, gestor de paquetes, framework de test, CI (`.github/workflows/`, etc.), hooks (`.husky/`, `lefthook`, `pre-commit`).

2. **Carga la rúbrica.** Lee `reference/fields.md` (en este directorio de skill): define los 9 campos, la escalera 0-4 de cada uno, las herramientas por stack y las pistas de detección.

3. **Fan-out en 3 subagentes** (Agent tool, en paralelo), uno por capa. Pasa a cada uno: el stack detectado, sus campos asignados y el contenido íntegro de su sección de `reference/fields.md`. Cada agente devuelve, por campo: nivel propuesto 0-4, evidencia con rutas y líneas, y el gap concreto hacia el siguiente nivel.
   - **Agente A — capa de especificación:** campos 1 (aceptación), 3 (mutación de la spec), 9 (spec-first).
   - **Agente B — capa de tests:** campos 2 (mutation testing), 5 (cobertura), 8 (calidad de tests).
   - **Agente C — capa de código:** campos 4 (CRAP), 6 (DRY), 7 (arquitectura).

   Si el Agent tool no está disponible, degrada a una sola pasada secuencial con las mismas secciones.

4. **Sintetiza en la sesión principal.** Valida cada nivel propuesto contra la escalera (los agentes tienden a ser generosos: exige la evidencia del nivel, no la intención). Calcula el score. Escribe el roadmap.

## Formato del informe

```
# Gauntlet audit — <repo>

## Stack
<lenguajes, test runner, CI, hooks en 1-2 líneas>

## Scorecard
| # | Campo | Nivel | Evidencia | Gap al siguiente nivel |
|---|-------|-------|-----------|------------------------|
| 1 | Aceptación (comportamiento) | 0-4 | <fichero:línea / workflow> | <qué falta> |
| ... los 9 campos ... |

**Score global: X/36**

## Roadmap (mejor ratio confianza/esfuerzo primero)
1. <paso> → <herramienta + comando/config concreta> — sube el campo N de X a Y. <por qué>
2. ... (3-5 pasos)

## Límites de esta auditoría
<qué no se pudo verificar estáticamente, evidencia ambigua>
```

## Criterios del roadmap

Ordena por salto de confianza dividido por esfuerzo:

1. **Convertir en gate lo ya instalado** (nivel 2 → 3): añadir un umbral que rompa el build a una herramienta que ya corre es casi gratis.
2. **Mutation testing** (campo 2): el mayor salto de confianza en repos con suite decente — es lo único que mide si los tests detectan cambios.
3. **Umbral de cobertura** si no existe: barato y prerequisito del CRAP.
4. **Gates de arquitectura** (ciclos y fronteras en CI).
5. **Mutación de la spec** solo si ya existe capa de aceptación; si no, proponer antes la capa.

Sé concreto: nombra la herramienta, el fichero de config y la clave exacta (p. ej. `stryker.config.json → thresholds.break`), nunca "añadir mutation testing".
