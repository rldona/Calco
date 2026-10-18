# Línea de tiempo y dibujos

La línea de tiempo es la parte inferior del editor: los clips y la reproducción arriba, una fila por capa y la barra con las acciones de dibujo.

![La línea de tiempo](/crops/es/timeline.jpg)

## Hacerla más alta

Arrastra hacia arriba el **agarre** de la parte superior de la línea de tiempo (la barrita del centro) para hacer sitio a más capas: las filas crecen hasta una altura cómoda y el lienzo se hace más pequeño. Calco recuerda la altura. Toca **dos veces** el agarre para volver a la altura automática, la que cabe con las capas que tienes.

## Fila superior

- **▶** reproduce el clip (Espacio). El contador muestra fotograma / total.
- **Clips** (Idle, Walk, Jump): toca para cambiar. El botón **…** tiene más opciones; ver [Clips y pivote](./clips).
- **Bucle** activa o desactiva la repetición de este clip.
- **fps − +** es la velocidad del clip. La flecha la vuelve a dejar en los fps del proyecto.
- **Pivote** muestra el punto de pivote; ver [Clips y pivote](./clips).
- A la derecha, el [papel cebolla](./onion-skin).

## Celdas

Cada fila de capa es una tira de **celdas**. Una celda es un dibujo, y su ancho es lo que dura.

- Toca una celda para ir ahí y dibujar en esa capa.
- Una celda discontinua todavía no tiene nada dibujado.
- Una flecha → significa que el dibujo se sigue viendo en los fotogramas siguientes (se mantiene).
- Una etiqueta (por ejemplo *step*) sustituye al número cuando el dibujo tiene una.
- Un icono de enlace indica una [repetición enlazada](./cycles).

**Arrastra el borde derecho de una celda** con el Pencil o con el dedo para que ese dibujo dure más o menos. Lo que viene después se desplaza: alargar un dibujo empuja al siguiente en vez de taparlo.

Mantén pulsada una celda para ver su menú:

![Menú de la celda](/crops/es/cell-menu.jpg)

- **Mantener el dibujo anterior**: esta capa sigue mostrando el dibujo de antes.
- **Nuevo dibujo aquí** / **Copiar dibujo aquí**: da a una celda mantenida un dibujo propio, vacío o como copia.
- **Etiqueta…**: un nombre que se ve en la celda (contacto, paso…). Las etiquetas pueden convertirse en eventos de animación de Unity.
- **Vaciar dibujo**.

## La barra

![La barra](/crops/es/bottom-bar.jpg)

**Dura N fotogramas − +** fija cuánto tiempo se ve el fotograma donde está el cabezal. Se ilumina en naranja cuando dura más de uno.

El marco naranja actúa sobre **el dibujo de la capa actual**; su título dice cuál (*Line · dibujo 3*):

| Botón | Qué hace |
|---|---|
| Mantener anterior / Nuevo dibujo / Copiar dibujo | Igual que el menú de la celda, para la celda actual. |
| Etiqueta | Pon nombre al dibujo. |
| Partir el dibujo a mitad | Un intermedio; ver [Ciclos e intermedios](./cycles). |
| Repetir dibujos | Un ciclo; ver [Ciclos e intermedios](./cycles). |
| Duplicar | Copia el dibujo en un fotograma nuevo después. |
| Papelera | Elimina el dibujo. Se sigue viendo el anterior; un fotograma que se queda sin nada propio desaparece. |
| **+** | Un dibujo nuevo y vacío después del cabezal, en esta capa. Las demás capas siguen mostrando lo que tenían. |

### Sincronizar capas

Con **Sincronizar capas** activado, los mismos botones actúan sobre **fotogramas enteros**, todas las capas a la vez.

![Sincronizar capas activado](/crops/es/sync-layers-bar.jpg)

### El menú Fotograma

**Fotograma** reúne las acciones que siempre afectan a todas las capas:

![Menú Fotograma](/crops/es/frame-menu.jpg)

Añadir, duplicar, mover antes o después, fijar el **rango de reproducción** (reproducir desde o hasta este fotograma) y eliminar el fotograma.
