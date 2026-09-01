# 540 Agentic Toolbox

Skills, hooks y recursos que [540](https://540deg.com) comparte. Cada pieza sale de nuestro trabajo real con agentes y se publica tal cual la usamos.

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

| Pieza | Qué hace |
|-------|----------|
| [gauntlet-audit](plugins/gauntlet-audit/) | Audita la red de verificación de un repo: 9 campos con madurez 0-4, score global y roadmap. Responde "¿puedo confiar en código escrito por agentes sin leerlo?". |
| [no-comments](plugins/no-comments/) | Hook que bloquea los comentarios que el agente añade a ficheros Ruby: el código se explica solo. Exime los pragmas de máquina. |

## Estructura

- `plugins/`: piezas instalables, un plugin por pieza.
- `resources/`: docs, plantillas y scripts que acompañan a las piezas.

## Licencia

[MIT](LICENSE)
