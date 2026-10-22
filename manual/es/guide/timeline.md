# Línea de tiempo y dibujos

Se anima en dos sitios: el **riel de animación**, a la derecha del lienzo, con lo que haces a los dibujos, y la **línea de tiempo**, abajo, con los clips, las capas y sus dibujos.

## El riel de animación

![El riel de animación](/crops/es/animation-rail.jpg){.rail}

De arriba abajo:

| Botón | Qué hace |
|---|---|
| **+ Nuevo** | Un dibujo nuevo y vacío después del cabezal, en la capa actual (⌥N). Las demás capas siguen mostrando lo que tenían. Es el botón que más vas a pulsar. |
| **Duplicar** | Copia el dibujo en un fotograma nuevo después (⌘D). |
| **Mantener** | Esta capa sigue mostrando el dibujo anterior. En una celda mantenida pasa a ser **Dibujo propio** (nuevo o copia), y en una [repetición enlazada](./cycles), **Desenlazar**. |
| **Eliminar** | Elimina el dibujo (⌫). Se sigue viendo el anterior; un fotograma que se queda sin nada propio desaparece. |
| **Más** | Etiquetar el dibujo, [partirlo a mitad](./cycles#intermedio-a-mitad), [repetir dibujos](./cycles), [interpolar un movimiento](./cycles#interpolar-un-movimiento) y las acciones del fotograma entero. |
| **Cebolla** | Activa o desactiva el [papel cebolla](./onion-skin); los números de debajo abren sus ajustes. |
| **Capa / Todas** | Sobre qué actúan los botones: el dibujo de la capa actual o **fotogramas enteros**, todas las capas a la vez. |

<div class="clear"></div>

Con **Todas**, **Nuevo** añade un fotograma entero, **Duplicar** copia el fotograma y **Eliminar** lo quita.

### El menú Más

![El menú Más](/crops/es/more-menu.jpg)

En **Fotograma N, todas las capas**: añadir, duplicar, mover antes o después, fijar el **rango de reproducción** (reproducir desde o hasta este fotograma, o de nuevo el clip entero) y eliminar el fotograma.

::: tip En vertical
Con el iPad en vertical, el riel de animación se tumba entre el lienzo y la línea de tiempo, con **+ Nuevo dibujo** como un botón ancho a la derecha.
:::

## La línea de tiempo

![La línea de tiempo](/crops/es/timeline.jpg)

### Fila superior

- **▶** reproduce el clip (Espacio). El contador muestra fotograma / total.
- **Clips** (Idle, Walk, Jump): toca para cambiar. El botón **…** tiene más opciones; ver [Clips y pivote](./clips).
- **12 fps ⌄** abre los ajustes del clip: su velocidad, **Bucle** y **Mostrar el pivote**. Los iconos junto a los fps indican que el clip se repite y que el pivote está a la vista.
- **Dura N fotogramas − +** fija cuánto se ve el fotograma donde está el cabezal. Se ilumina en naranja cuando dura más de uno (⌥= / ⌥−).

![Ajustes del clip](/crops/es/clip-settings.jpg)

### Capas

Sobre los nombres de las capas, **+** añade una capa y el icono de la pila abre el panel de capas; ver [Capas](./layers).

### Números de fotograma

Encima de las celdas van los números de los fotogramas:

- **Toca un número** para ir a ese fotograma.
- **Arrastra por los números**, con el dedo o el Pencil, para pasar los fotogramas bajo el dedo, tan rápido o tan despacio como lo muevas, con un toque háptico en cada uno. Así ves el movimiento a tu ritmo sin reproducir. La línea de tiempo se queda quieta mientras arrastras.
- **Mantén pulsado un número y arrastra** para mover el fotograma, con todas sus capas.
- **Toca dos veces un número** para elegir ese fotograma; después **arrastra por los números** para elegir un rango.

### Varios fotogramas a la vez

Con fotogramas elegidos, una barra bajo el lienzo actúa sobre todos ellos: **Copiar**, **Cortar**, **Pegar** (después del cabezal, cada fotograma con su duración), **Invertir** (reproducirlos al revés, para la vuelta de un ciclo), **Duplicar** (justo detrás) y **Eliminar**. Con **Capa** en el riel de animación actúan solo sobre los dibujos de la capa actual (las piernas, sin el resto); con **Todas**, sobre los fotogramas enteros. Cada acción se deshace de una vez; **✕** suelta el rango. Con teclado: ⌘C, ⌘X, ⌘V y ⌘⌫.

### Celdas

Cada fila de capa es una tira de **celdas**. Una celda es un dibujo, y su ancho es lo que dura.

- Toca una celda para ir ahí y dibujar en esa capa.
- Cada celda muestra una **vista previa** de su dibujo, con su número (o etiqueta) en la esquina.
- Una celda discontinua todavía no tiene nada dibujado.
- Una flecha → significa que el dibujo se sigue viendo en los fotogramas siguientes (se mantiene).
- Una etiqueta (por ejemplo *step*) sustituye al número cuando el dibujo tiene una.
- Un icono de enlace indica una [repetición enlazada](./cycles).
- La celda **+** discontinua después del último dibujo de la capa actual añade otro al final.

**Arrastra el borde derecho de una celda** con el Pencil o con el dedo para que ese dibujo dure más o menos. Lo que viene después se desplaza: alargar un dibujo empuja al siguiente en vez de taparlo.

Mantén pulsada una celda para ver su menú:

![Menú de la celda](/crops/es/cell-menu.jpg)

- **Mantener el dibujo anterior**: esta capa sigue mostrando el dibujo de antes.
- **Nuevo dibujo aquí** / **Copiar dibujo aquí**: da a una celda mantenida un dibujo propio, vacío o como copia.
- **Etiqueta…**: un nombre que se ve en la celda (contacto, paso…). Las etiquetas pueden convertirse en eventos de animación de Unity.
- **Vaciar dibujo**.

### Hacerla más alta

Arrastra hacia arriba el **agarre** de la parte superior de la línea de tiempo (la barrita del centro) para hacer sitio a más capas: las filas crecen y el lienzo se hace más pequeño. Calco recuerda la altura. Toca **dos veces** el agarre para volver a la altura automática.

Si sigues empujando el agarre hacia abajo pasada la altura mínima, la línea de tiempo **se oculta**: el lienzo ocupa toda la altura, los rieles quedan centrados a los lados y abajo queda una barra fina con reproducir y el contador de fotogramas. Tócala, o arrástrala hacia arriba, para volver a mostrar la línea de tiempo. En los dos sentidos se desliza, y el dibujo se recoloca con suavidad.

![La línea de tiempo oculta](/screens/es/timeline-hidden.jpg)
