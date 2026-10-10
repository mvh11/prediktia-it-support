# Modelo operativo — CLOUD_CONTROL_PLANE + LOCAL_BRIDGE

```
AGENT_ID: IT_SUPPORT_AGENT   (una sola identidad en ambos modos)
EXECUTION_MODES: CLOUD_CONTROL_PLANE | LOCAL_BRIDGE
SOURCE_OF_TRUTH: mvh11/prediktia-it-support
```

## 1. Una identidad, dos modos de ejecución

| Modo | Dónde corre | Para qué | Credenciales |
|------|-------------|----------|--------------|
| CLOUD_CONTROL_PLANE | Sesión cloud efímera | Diseño, análisis, preparación de tareas, revisión de evidencia, documentación de este repo | Ninguna credencial de producción |
| LOCAL_BRIDGE | Estación local con conexión PREDIKTIA existente | Ejecutar tareas preparadas que necesitan acceso real (p. ej. lectura de catálogos Neon) | La conexión local existente, como fuente opaca |

El modo no cambia la identidad ni la autoridad: ambos se rigen por
[`authority-and-scope.md`](authority-and-scope.md).

## 2. Límite de secretos

- Las credenciales del `.env` local **se quedan en local**. Nunca se copian,
  imprimen, suben, pegan en chat ni se mueven a la nube.
- LOCAL_BRIDGE usa la conexión como **fuente opaca**: carga el valor en
  memoria del proceso sin mostrarlo.
- CLOUD_CONTROL_PLANE nunca intenta conectarse a Neon ni pide credenciales.
- La evidencia que vuelve al repo se sanea antes del commit (reglas en cada
  paquete de tarea).

## 3. Este repositorio como fuente de verdad

```
handoffs/local/<task-id>.md      paquete de tarea cloud -> local
evidence/<task-id>-result.md     resultado saneado local -> cloud
scripts/read-only/               scripts de solo lectura validados
docs/                            autoridad, modelo, estado actual
```

Flujo:
1. CLOUD_CONTROL_PLANE prepara el paquete en `handoffs/local/`, hace commit y
   push.
2. LOCAL_BRIDGE hace `git pull`, verifica el paquete y lo ejecuta tal cual.
3. LOCAL_BRIDGE escribe el resultado saneado en `evidence/`, hace commit y
   push.
4. CLOUD_CONTROL_PLANE revisa la evidencia y actualiza
   `docs/current-status.md`.

Un paquete solo se ejecuta si su `CHIEF_AUTHORIZATION` lo cubre. Lo que no está
en el paquete no está autorizado.

## 4. Un escritor de TI a la vez

- Solo un modo escribe en este repo en cada momento. El escritor activo se
  indica en `docs/current-status.md` §0.
- Antes de cualquier commit: `git fetch`, verificar que la rama local coincide
  con la remota y que no hay otra PR/rama de TI abierta en paralelo.
- Si la rama remota avanzó o diverge: detenerse, no forzar. Nunca
  `push --force`.
- Al terminar, el escritor deja indicado en §0 a quién pasa el turno.

## 5. Repositorios de aplicación

Solo lectura en ambos modos. LOCAL_BRIDGE puede **leer** el `.env` de un
worktree de aplicación para obtener la conexión, pero no modifica, no hace
commit ni cambia de rama en ningún repositorio de aplicación.
