# no-comments

Parte de [540 Agentic Toolbox](https://github.com/540/agentic-toolbox).

Hook `PreToolUse` para Claude Code. Bloquea `Write`, `Edit` y `MultiEdit` cuando el agente añade comentarios a un fichero de un lenguaje soportado. La premisa: el código dice lo que hace, y un comentario que lo repite caduca en cuanto uno de los dos cambia. Si un bloque parece pedir comentario, el problema es de naming: se extrae un método (o una función) con buen nombre.

## Lenguajes

| Lenguaje | Extensiones | Se activa con | Exime |
|----------|-------------|---------------|-------|
| Ruby | `.rb`, `.rake` | `Gemfile` | shebang, `frozen_string_literal`, encoding, sigilo de Sorbet, directivas de RuboCop, `:nodoc:`/`:nocov:` |
| JavaScript / TypeScript | `.js`, `.jsx`, `.mjs`, `.cjs`, `.ts`, `.tsx`, `.mts`, `.cts` | `package.json`, `tsconfig.json`, `deno.json(c)`, `jsr.json` | `@ts-*` (en línea o dentro de un bloque), `/// <reference>`, `@import`, `@overload`, `@satisfies`, `@internal`, `@deprecated`, ESLint, Biome, oxlint, deno-lint, dprint, tslint, `prettier-ignore`, istanbul/c8/v8, `sourceMappingURL`, `@__PURE__`, hints de webpack y Vite, `/*! */`, `@license`, `@preserve`, `@flow`, `@generated` |

### JSDoc: depende del fichero

Un bloque JSDoc no es lo mismo en `.js` que en `.ts`, y el hook lo trata distinto:

| | `.js`, `.jsx`, `.mjs`, `.cjs` | `.ts`, `.tsx`, `.mts`, `.cts` |
|--|-------------------------------|-------------------------------|
| `@type`, `@param`, `@returns`, `@typedef`, `@template`, `@enum`… | **exento**: con `checkJs` o `// @ts-check` son el sistema de tipos, y borrarlos cambia lo que compila | **deny**: la sintaxis ya lo dice, y un `@param id The user id` es justo el ruido que este hook existe para frenar |
| `@import`, `@overload`, `@satisfies`, `@internal`, `@deprecated` | exento | exento: los lee el compilador (`@internal` con `stripInternal`) o el editor |
| Narración (`/** coge el usuario y sale */`) | deny | deny |

### Selección de lenguaje

Con la variable `NO_COMMENTS_LANGUAGES`, en el bloque `env` del `settings.json`:

| Valor | Efecto |
|-------|--------|
| sin definir | todos los lenguajes (por defecto) |
| `ruby`, `rb` | solo Ruby |
| `ts`, `js`, `typescript`, `javascript`, `node` | solo JS/TS |
| `js,ruby` | ambos |
| `all` | todos |
| `none` o vacío | desactiva el hook |

Al leerse del entorno, un repo puede desactivarlo — o reducirlo a un solo lenguaje — desde el `env` de su propio `.claude/settings.json`, sin tocar la configuración global.

## Cómo funciona

- Solo cuentan los comentarios **añadidos**. Un comentario que ya estaba en el `old_string` viaja con su código: los refactors y los movimientos no disparan el hook.
- La extensión del fichero elige el escáner. Cada lenguaje vive en `hooks/languages/` y aporta su escáner, sus pragmas exentos y los marcadores que dicen "esto es de verdad un proyecto así".
- Exime los pragmas que lee una máquina (tabla de arriba).
- El escáner de Ruby sigue strings, interpolación `#{}`, literales `%w[]` y heredocs: un `#` dentro de datos no se lee como comentario. Los bloques `=begin`/`=end` cuentan como un comentario.
- El de JS/TS sigue strings, template literals con `${}` e interpolación anidada, y literales de regex. Distingue regex de división por el token anterior, así que ni `total / count` ni el `/>` de JSX lo confunden. Un `{/* ... */}` de JSX sí es un comentario.
- Solo actúa si el directorio de trabajo tiene un marcador del lenguaje. Así no salta al editar fixtures o ejemplos en repos que no son de ese lenguaje.
- Ignora lo generado y lo vendorizado: `.d.ts`, `.d.mts`, `.d.cts`, `.min.js`, `.generated.*`, `node_modules/`, `dist/`, `build/`, `out/`, `coverage/`, `.next/`, `.nuxt/`, `__generated__/`, `vendor/bundle/`, `db/schema.rb`, `*_pb.rb`.
- Ignora los scratchpads (`/tmp/`) y todo lo que viva bajo `.claude/`: la configuración del propio agente queda fuera de la regla.
- Fail-open: ante cualquier error inesperado, deja pasar. Es un guardarraíl de flujo, no una frontera de seguridad.

Cuando bloquea, el mensaje de deny instruye al agente: reemite el edit sin comentarios, o extrae un método con buen nombre. Si un comentario es de verdad imprescindible (un quirk de un sistema externo), el agente debe parar y pedir al usuario que apruebe esa línea.

## Instalación

```
/plugin marketplace add 540/agentic-toolbox
/plugin install no-comments@540
```

Requiere `/usr/bin/ruby` (el Ruby del sistema, presente en macOS y en la mayoría de Linux). Sin gemas: solo stdlib. También para JS/TS — no hay `/usr/bin/node` que fijar, y el escáner no necesita más que stdlib.

## Tests

```
/usr/bin/ruby plugins/no-comments/test/no_comments_test.rb
```

Cada caso alimenta un payload de `PreToolUse` por stdin desde un proyecto de fixture y comprueba allow o deny: escáner por lenguaje, pragmas exentos, alcance (ficheros generados, vendorizados, scratchpads) y selección de lenguaje. Stdlib, como el hook.

## Añadir un lenguaje

Un fichero en `hooks/languages/` con un módulo que defina `NAME`, `ALIASES`, `PATHS`, `EXCLUDED`, `MARKERS`, `ADVICE` y `comments(text, path)` — el `path` llega para los lenguajes cuya política depende de la extensión, como el JSDoc de `.js` frente al de `.ts`, y se ignora si no hace falta; luego añadirlo a `LANGUAGES` en `hooks/no-comments.rb`. El escáner es lo único específico del lenguaje: el diff de "solo lo añadido", el gate de proyecto, la exclusión de scratchpads y el mensaje de deny son comunes.

## Adaptarlo

- ¿Otra política? El mensaje de deny vive en `hooks/no-comments.rb` (`MESSAGE_HEAD` y `MESSAGE_TAIL`) y el consejo por lenguaje en el `ADVICE` de cada módulo; ajústalos a la convención de tu equipo.
