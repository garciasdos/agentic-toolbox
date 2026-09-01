# 540 Agentic Toolbox

Skills, hooks y recursos que [540](https://540deg.com) comparte en la serie [IA en 540](https://ia-en-540.substack.com). Cada pieza sale de nuestro trabajo real con agentes y se publica tal cual la usamos.

*Skills, hooks and resources 540 shares in its build-in-public series about AI adoption. Content in Spanish.*

## Instalación

En Claude Code, como plugin (incluye hooks y comandos cuando la pieza los tiene):

```
/plugin marketplace add 540/agentic-toolbox
/plugin install gauntlet-audit@540
```

En cualquier otro agente compatible con [skills.sh](https://skills.sh) (solo skills):

```
npx skills add 540/agentic-toolbox
```

## Piezas

| Pieza | Qué hace | Número de la serie |
|-------|----------|--------------------|
| [gauntlet-audit](plugins/gauntlet-audit/) | Audita la red de verificación de un repo: 9 campos con madurez 0-4, score global y roadmap. Responde "¿puedo confiar en código escrito por agentes sin leerlo?". | — |

## Estructura

- `plugins/`: piezas instalables, un plugin por pieza.
- `resources/`: docs, plantillas y scripts que acompañan a la serie.

## Contribuciones

Issues y PRs abiertas. Las piezas nuevas entran cuando aparecen en la serie.

## Licencia

[MIT](LICENSE)
