# Rúbrica del gauntlet — 9 campos de verificación

Origen: el "gauntlet" de Uncle Bob Martin (jul 2026) — la red de constraints que sustituye la
lectura del código escrito por agentes. Sus herramientas de referencia (crap4clj, clj-mutate,
mutate4java, dry4go, scrap, deintroverter4clj, dependency-checker, Acceptance-Pipeline-Specification,
swarm-forge) viven en github.com/unclebob.

## La escalera de madurez (común a todos los campos)

| Nivel | Significado | Evidencia exigida |
|-------|-------------|-------------------|
| 0 | Nada. El campo no se mide | — |
| 1 | Herramienta instalada | dependencia declarada o script presente |
| 2 | Configurada con umbral/reglas reales | fichero de config con umbral no-trivial |
| 3 | Gate: rompe el build | corre en CI o hook pre-push y falla con exit code |
| 4 | Gate + evidencia de ejecución reciente | run de CI verde <30 días, informe/manifiesto commiteado reciente |

Reglas de puntuación:

- Cada nivel requiere los anteriores. Una herramienta con umbral que no corre en ningún gate es 2, no 3.
- "Corre en CI" sin bloquear (continue-on-error, allow_failure, informe-only) es 2.
- Nada es N/A: sin herramienta ni práctica → 0, aunque el repo "no la necesite".
- Cita siempre la evidencia: fichero:línea, nombre del workflow, fecha del run.

Score global = suma de los 9 niveles, sobre 36.

---

## Agente A — capa de especificación

### Campo 1 — Comportamiento funcional (aceptación)

**Pregunta:** ¿el comportamiento está especificado fuera del código y verificado contra la app real?

| Stack | Herramientas | Pistas de detección |
|-------|--------------|---------------------|
| TS/JS | Cucumber.js, Playwright/Detox/Maestro con escenarios trazables | `*.feature`, `features/`, `e2e/`, `.maestro/`, `@cucumber/cucumber` en deps |
| Ruby | Cucumber, Turnip, RSpec feature specs (Capybara) | gem `cucumber`/`turnip`; `spec/features/`, `features/` |
| Genérico | Gherkin + runner del lenguaje; harness propio tipo Acceptance-Pipeline-Specification | ficheros `.feature`; generadores de tests desde spec |

Matices de nivel: 2 exige escenarios reales que cubran historias de usuario (no 3 ejemplos de humo);
4 admite como evidencia informes de e2e en CI o manifiestos de aceptación commiteados.

### Campo 3 — Mutación de la especificación

**Pregunta:** si muto un valor de la spec (una celda de `Examples`, un dato del criterio), ¿algún test falla?
Detecta criterios decorativos: la spec dice 20 y el test pasaría igual con 27.

| Stack | Herramientas | Pistas de detección |
|-------|--------------|---------------------|
| TS/JS | No hay estándar. Harness propio que mute `.feature`/tablas y espere fallo | scripts `*mutate*` sobre features; manifiestos `mutation-stamp` en cabeceras de `.feature` |
| Ruby | No hay estándar. Ídem | ídem |
| Genérico | gherkin-mutator de Acceptance-Pipeline-Specification (spec pública) como modelo | comentarios `# acceptance-mutation-manifest` en features |

Casi todo repo puntúa 0 aquí. Nivel 1 = existe el script propio; 3 = corre como gate;
4 = manifiestos sellados por escenario (hash + killed/survived) commiteados y frescos.
Sin campo 1 (sin capa de aceptación), este campo es 0 por construcción.

### Campo 9 — Proceso spec-first

**Pregunta:** ¿la especificación y los criterios existen antes del código, y cada test se ve fallar primero?

Detección (no hay herramienta; se audita el proceso materializado):

- Nivel 1: instrucciones escritas que lo exigen (`CLAUDE.md`/`AGENTS.md` con TDD/ver-fallar,
  guía de contribución).
- Nivel 2: estructura que lo canaliza: plantilla de PR con criterios de aceptación obligatorios,
  directorio de planes/specs commiteados (`plans/`, `.claude/*plan*.md`), tickets enlazados.
- Nivel 3: gate mecánico: hook o check de CI que exige plan/spec/test nuevo junto a cada cambio
  de producción (p. ej. falla si el diff toca `src/` sin tocar tests).
- Nivel 4: evidencia en el historial: secuencias spec→test→código en commits recientes,
  planes completados archivados.

---

## Agente B — capa de tests

### Campo 2 — Mutation testing del código

**Pregunta:** ¿mis tests detectan un cambio en el código? Es la única métrica de si la suite protege algo.

| Stack | Herramientas | Pistas de detección |
|-------|--------------|---------------------|
| TS/JS | StrykerJS | `stryker.config.json|mjs`, `@stryker-mutator/core` en deps; umbral = `thresholds.break` |
| Ruby | mutant (`mutant-rspec`/`mutant-minitest`) | gem `mutant*`; `.mutant.yml`, `config/mutant.yml`; en CI: `bundle exec mutant run` |
| Genérico | Pitest (Java), gremlins/go-mutesting (Go), mutmut/cosmic-ray (Python), cargo-mutants (Rust) | config o invocación en CI |

Matices: 2 exige umbral de kill/score que pueda fallar (`thresholds.break` ≠ null; mutant
`--fail-fast`/cobertura de mutación exigida); 3 = ese umbral corre en CI aunque sea incremental
(`--since`, `--incremental`); 4 = informe (`reports/mutation/`, dashboard) o run reciente.

### Campo 5 — Cobertura con umbral

**Pregunta:** ¿qué código nunca ejercita ningún test, y baja el listón rompe el build?

| Stack | Herramientas | Pistas de detección |
|-------|--------------|---------------------|
| TS/JS | jest `coverageThreshold`, nyc/c8 `check-coverage` | `jest.config.*`, `.nycrc`; umbral global y/o por fichero |
| Ruby | simplecov `minimum_coverage` / `refuse_coverage_drop` | `spec_helper.rb`/`.simplecov` |
| Genérico | `go test -cover` + gate, coverage.py `--fail-under`, JaCoCo `check` | invocación en CI con umbral |

Matices: un umbral de risa (p. ej. 10 %) es 2, no "configurado bien" — anótalo en el gap.
Referencia del gauntlet: 90 alto. 4 = badge/informe/run reciente.

### Campo 8 — Calidad del código de test

**Pregunta:** ¿los tests asertan de verdad, tocan producción y no son un pantano de mocks y setup?
(Equivalente de scrap/deintroverter: tests introvertidos, sin aserciones, hipertrofiados.)

| Stack | Herramientas | Pistas de detección |
|-------|--------------|---------------------|
| TS/JS | eslint-plugin-jest: `expect-expect`, `no-disabled-tests`, `no-conditional-expect`, `max-nested-describe`, `prefer-strict-equal` | reglas activas en la config de ESLint aplicada a specs |
| Ruby | rubocop-rspec: `RSpec/MultipleExpectations`, `RSpec/ExampleLength`, `RSpec/MessageSpies`, `RSpec/VerifiedDoubles`, `RSpec/NoExpectationExample` | gem + `.rubocop.yml` con los cops habilitados |
| Genérico | linters de test del ecosistema; el mutation testing (campo 2) lo cubre indirectamente | — |

Matices: si el campo 2 está a nivel ≥3, concede aquí mínimo 2 aunque falten linters (la mutación
mata tests vacíos). 3 = las reglas rompen el lint de CI; 4 = lint verde reciente + cero disables
masivos sobre esas reglas.

---

## Agente C — capa de código

### Campo 4 — Riesgo CRAP (complejidad × cobertura)

**Pregunta:** ¿hay funciones complejas sin tests? `CRAP = CC² × (1-cov)³ + CC`. Umbral del gauntlet: ≤ 6-8 por función.

| Stack | Herramientas | Pistas de detección |
|-------|--------------|---------------------|
| TS/JS | Aproximación: ESLint `complexity` + coverage por función (jest `coverageThreshold` per-glob); SonarQube/CodeClimate combinan ambos | regla `complexity` con límite; sonar-project.properties; `.codeclimate.yml` |
| Ruby | rubycritic (churn×complexity), flog + simplecov combinados; rubocop `Metrics/*` | gems `rubycritic`/`flog`; `.rubocop.yml` Metrics con límites |
| Genérico | SonarQube; scripts propios estilo crap4java/crap4clj/crap4go | invocación en CI |

Matices: complejidad sola (sin cruzar con cobertura) tapa la mitad del campo → máximo 2 y anótalo.
3 = el límite combinado (o ambos límites por separado) rompe el build.

### Campo 6 — Duplicación estructural (DRY)

**Pregunta:** ¿hay estructura repetida más allá de nombres y literales?

| Stack | Herramientas | Pistas de detección |
|-------|--------------|---------------------|
| TS/JS | jscpd (`.jscpd.json`, `threshold`); ESLint `sonarjs/no-identical-functions`, `sonarjs/no-duplicate-string` | config/deps; jscpd en CI con `--exitCode 1` |
| Ruby | flay; reek `DuplicateMethodCall` | gems; invocación en CI |
| Genérico | PMD CPD, simian | invocación en CI |

### Campo 7 — Arquitectura y dependencias como gate

**Pregunta:** ¿las fronteras entre capas/módulos y la ausencia de ciclos las verifica una herramienta, no la memoria del revisor?

| Stack | Herramientas | Pistas de detección |
|-------|--------------|---------------------|
| TS/JS | dependency-cruiser (reglas `severity: error`), ESLint `import/no-cycle` (con `import/parsers` para TS, si no no detecta nada), `no-restricted-imports`, eslint-plugin-boundaries, madge `--circular` | `.dependency-cruiser.js`; reglas en ESLint; script en CI |
| Ruby | packwerk (`packwerk.yml`, `package.yml` con `enforce_dependencies`), rubocop custom de capas | packs/ + configs; `packwerk check` en CI |
| Genérico | ArchUnit (Java), go vet + depguard, import-linter (Python) | config + CI |

Matices: reglas custom de lint que codifican fronteras del dominio (imports prohibidos entre
capas, "solo primitives toca react-native") cuentan como herramienta de este campo.
2 exige reglas que describan la arquitectura real, no solo `no-cycle` suelto.
