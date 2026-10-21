# Herramientas de dibujo

La barra de la izquierda tiene las herramientas. Toca una vez para elegirla y otra vez para abrir sus opciones.

![Barra de herramientas](/crops/es/tool-rail.jpg){.rail}

De arriba abajo:

- **Pincel** (B)
- **Goma** (E)
- **Relleno** (G)
- **Cuentagotas** (I)
- **Lazo** (L)
- **Mover** (V)
- **Color**: toca para la paleta y el selector de color.
- **Tamaño**: arrastra la barra, o toca el número para valores exactos. `[` y `]` con teclado.
- **Deshacer / Rehacer**: también tocando con dos y tres dedos en el lienzo.

<div class="clear"></div>

::: tip En vertical
Con el iPad en vertical, las herramientas se tumban arriba, bajo el nombre del documento, con la barra de tamaño en horizontal. El lienzo ocupa todo el ancho.
:::

## Pincel

Toca otra vez el pincel para abrir la **biblioteca de pinceles**: todos los pinceles con una muestra de cómo pintan.

![Biblioteca de pinceles](/crops/es/brush-library.jpg)

| Pincel | Para qué sirve |
|---|---|
| **Entintador** | Línea limpia: afina con poca presión. |
| **Bolígrafo** | Líneas finas y constantes, y detalles pequeños. |
| **Rotulador** | Grueso y uniforme, al 70 %: no se oscurece donde el trazo se cruza consigo mismo. |
| **Lápiz** | Bocetar con grano de papel; con poca presión es más claro, e inclinar el Pencil sombrea con el lateral de la mina. |
| **Lápiz azul** | El mismo lápiz, siempre azul claro, para encajar el movimiento bajo la línea limpia. |
| **Carboncillo** | Áspero y con grano, para manchar rápido. |
| **Pincel** | Borde suave y una punta que afina al empezar. |
| **Aerógrafo** | Muy suave; se acumula al repasar, para degradados y brillos. |
| **Plano** | Un relleno duro y uniforme, sin presión: para colorear. |

Cada pincel recuerda **su propio tamaño y opacidad**: la barra de tamaño del riel muestra los del pincel actual, y **Opacidad** está bajo la biblioteca. El icono del pincel en el riel cambia al pincel que eliges.

La pestaña **Ajustes** tiene las opciones comunes a todos:

![Opciones del pincel](/crops/es/brush-options.jpg)

- **Pinta**: dónde va la pintura en la capa.
  - **Delante**: encima de lo que ya hay.
  - **Detrás**: debajo de lo que hay. Colorear bajo la línea sin tocarla.
  - **Dentro**: solo sobre lo ya dibujado, respetando sus bordes. Para sombrear y cambiar el color.
- **Suavizado**: estabiliza la línea. Más alto es más tranquilo, con algo más de retraso.
- **La presión del Pencil cambia el tamaño**: desactívalo para una línea uniforme.
- **Solo dibuja el Apple Pencil**: los dedos nunca dibujan; siguen sirviendo para ampliar, desplazar y deshacer. Ver [Apple Pencil y gestos](./pencil).
- **Pixel art**: bordes duros para este proyecto. El tamaño del pincel pasa a ser un ancho en píxeles: el tamaño 1 pinta exactamente un píxel.

## Goma

La goma tiene su propio tamaño, que se recuerda aparte de los pinceles. Tócala otra vez para elegir su **punta**: el borde de cualquier pincel, como un aerógrafo suave o un lápiz con grano. En modo pixel art borra píxeles enteros.

## Relleno

![Opciones del relleno](/crops/es/fill-options.jpg)

Toca dentro de un contorno para rellenarlo con el color actual. El contorno es todo lo visible, en todas las capas, pero la pintura va solo a la capa actual. Dibuja las líneas en **Line**, elige **Color** y rellena ahí: el color queda debajo de las líneas.

- **Pinta**: delante, detrás o dentro, como con el pincel.
- **Cerrar huecos**: cierra pequeños cortes en la línea para que la pintura no se salga. Prueba primero con **Pequeño**.

## Cuentagotas

Toca en cualquier punto del lienzo para coger ese color. Después Calco vuelve a la herramienta que tenías.

## Lazo

Rodea algo para levantarlo como selección.

![Una selección con el lazo](/crops/es/lasso-selection.jpg)

- **Arrastra por dentro** para moverla.
- **Tirador de la esquina**: escalar. **Tiradores de los lados**: estirar a lo ancho o a lo alto, para el *squash & stretch*. **Tirador redondo**: girar. **Punto central**: el punto alrededor del que escala, estira y gira; arrástralo para moverlo (a los pies, por ejemplo, para que al aplastar sigan en el suelo).
- Mientras escalas o estiras, una etiqueta muestra el ancho y el alto en porcentaje. Cada uno **encaja** en el 100 %, o en las proporciones del otro, con un toque háptico suave.
- **Uniforme | Libre**, bajo el lienzo, es lo que hace la esquina: mantener las proporciones, o estirar el ancho y el alto por separado.
- La barra de encima: **Copiar**, **Cortar**, **Eliminar**, **Voltear en horizontal**, **Cancelar** (✕, Esc) y **Aplicar** (✓, Retorno). Tocar fuera también aplica.

Toca otra vez el lazo para **Seleccionar todo** y **Pegar**:

![Opciones del lazo](/crops/es/lasso-options.jpg)

Lo pegado aparece donde lo copiaste, en el fotograma y la capa en que estés: útil para llevar una pose a otro dibujo y ajustarla.

## Mover

**Mover** coge el dibujo de la capa actual, en el cabezal, para moverlo, escalarlo o girarlo, con los mismos tiradores que el lazo.

![Mover: todo el dibujo](/crops/es/move-all.jpg)

- Al elegir **Mover** se coge **todo el dibujo**, en un recuadro ajustado a la pintura.
- **Toca un trazo** para coger solo ese: un ojo, una mano, una antena. Calco recuerda cada trazo que haces con el pincel, así que coge el trazo exacto aunque se cruce con otros.
- **Arrastra un trazo** para cogerlo y moverlo de una vez.
- Toca un hueco para volver a todo el dibujo.

![Mover: un trazo](/crops/es/move-stroke.jpg)

Al escalarlo, estirarlo o girarlo, un trazo **sigue nítido**: Calco lo vuelve a pintar donde cae, con su pincel, en vez de remuestrear sus píxeles. Los trazos borrados, rellenados o pasados por el lazo, y las imágenes importadas, se remuestrean.

Donde se cruzan varios trazos, **toca otra vez en el mismo sitio** para pasar al de debajo; el aviso bajo el lienzo dice cuál tienes. **Añadir trazos** hace que cada toque añada un trazo a lo que mueves, o lo quite, para mover varios juntos.

![Coger el trazo de debajo](/crops/es/move-crossing.jpg)

Al mover, girar y escalar, la forma **se engancha** a su sitio de inicio, recta (o a un cuarto de vuelta) y a su tamaño, con un toque suave que se nota; el pivote se engancha al centro. Así siempre puedes volver a donde empezaste. Toca fuera, cambia de herramienta o de fotograma para soltarlo; todo el movimiento se deshace en un paso.

- Los trazos movidos siguen siendo trazos: puedes volver a cogerlos.
- La **goma** recorta los trazos por los que pasa. Un **relleno**, el **lazo** o pegar funden el dibujo, que entonces se separa en sus formas sueltas.
- En una capa **bloqueada**, como una [imagen importada](./layers#imagenes-de-referencia), Mover ofrece **Desbloquear y mover**, y la vuelve a bloquear al terminar.

## Pixel art

Con **Pixel art** activado, todas las herramientas trabajan con píxeles enteros: sin bordes suaves en el pincel, la goma, el relleno ni el lazo, y las selecciones movidas siguen nítidas. Actívalo al crear el proyecto o en las opciones del pincel.

## Vista

- **Voltear la vista** (el icono del espejo en la barra superior, o H) muestra el dibujo en espejo sin modificarlo, para ver los errores con otros ojos.
- **Ajustar** vuelve al lienzo centrado y recto (⌘0); si la vista está volteada, sigue volteada.
- El **modo Zen** oculta todo menos el lienzo y una pequeña barra flotante con deshacer, rehacer, todas las herramientas y el color. Desliza **tres dedos hacia abajo** para entrar y **hacia arriba** para salir, como el agarre de la línea de tiempo (o ⌃⌘F).

![Modo Zen](/screens/es/zen.jpg)
