# M5.9C — Clasificación del endpoint Neon auditado

```
AGENT_ID: IT_SUPPORT_AGENT
EXECUTION_MODE: LOCAL_BRIDGE
FECHA_UTC: 2026-10-09
NEON_ENDPOINT_CLASSIFICATION: UNRESOLVED
NEON_MUTATION: NO
NEW_DB_QUERIES: NO
SECRETS_EXPOSED: NO
```

## Criterio

Se exige una **correspondencia directa** entre el endpoint auditado y una rama o
entorno de Neon. Coincidir con el esquema documentado de producción no basta.

## Fuentes revisadas (solo lectura)

| Fuente | Resultado |
|--------|-----------|
| Configuración local de la aplicación (solo nombres de variables) | Un único archivo local con la URL de la base y claves de proveedores de datos; **sin** variable de destino esperado ni URL de test |
| Configuración de ops (workflows de la aplicación) | Los jobs usan el entorno `production` de GitHub con secretos `DATABASE_URL` y `PREDIKTIA_EXPECTED_DB_TARGET`; los valores no son legibles desde la estación |
| Metadata del destino esperado en documentación | No se registra ningún destino saneado en los documentos de la aplicación |
| Metadata de rama/proyecto Neon | No hay CLI ni credencial de API de Neon en la estación |
| Herramientas GitHub | No hay CLI autenticada; los logs de Actions no son accesibles |
| Estado de esquema/migraciones | Coincide con el estado documentado de producción (`0007`) — **indicador, no correspondencia** |
| Evidencia de jobs operativos | Las tablas de seguimiento operativo tienen registros — **indicador, no correspondencia** |

## Conclusión

`UNRESOLVED`. Existen indicadores de producción, pero ninguna correspondencia
directa. Hasta resolverlo, toda propuesta sobre esta base la trata como
producción.

## Cómo resolverlo (cualquiera de estas, solo lectura)

1. Consola de Neon: identificar la rama a la que pertenece el endpoint de la
   configuración local (el responsable lo confirma sin publicar el ID).
2. El responsable del entorno `production` de GitHub compara el destino
   esperado (`PREDIKTIA_EXPECTED_DB_TARGET`) con el host/base de la
   configuración local y reporta solo `MATCH` / `NO_MATCH`.
3. Una clave de API de Neon de solo lectura, entregada a LOCAL_BRIDGE como
   entrada opaca, para consultar ramas y endpoints del proyecto.
