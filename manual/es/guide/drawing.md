# Herramientas de dibujo

La barra de la izquierda tiene las herramientas. Toca una vez para elegirla y otra vez para abrir sus opciones.

![Barra de herramientas](/crops/es/tool-rail.jpg){.rail}

De arriba abajo:

- **Pincel** (B)
- **Goma** (E)
- **Relleno** (G): el cubo de pintura.
- **Cuentagotas** (I)
- **Seleccionar** (L): libre, rectángulo o varita mágica.
- **Mover** (V)
- **Formas** (U)
- **Pluma** (P)
- **Nodo** (A)
- **Dedo** (S)
- **Color**: toca para la [paleta del proyecto](#paleta-del-proyecto), los colores básicos y el selector de color.
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
- **Pixel art**: bordes duros para este proyecto. El tamaño del pincel pasa a ser un ancho en píxeles: el tamaño 1 pinta exactamente un píxel, el 2 un cuadrado de 2×2, el 3 uno de 3×3. La presión y la inclinación no lo cambian.

## Goma

La goma tiene su propio tamaño, que se recuerda aparte de los pinceles. Tócala otra vez para elegir su **punta**: el borde de cualquier pincel, como un aerógrafo suave o un lápiz con grano. En modo pixel art borra píxeles enteros.

## Relleno

![Opciones del relleno](/crops/es/fill-options.jpg)

Toca dentro de un contorno para rellenarlo con el color actual. El contorno es todo lo visible, en todas las capas, pero la pintura va solo a la capa actual. Dibuja las líneas en **Line**, elige **Color** y rellena ahí: el color queda debajo de las líneas.

- **Pinta**: delante, detrás o dentro, como con el pincel.
- **Cerrar huecos**: cierra pequeños cortes en la línea para que la pintura no se salga. Prueba primero con **Pequeño**.

## Cuentagotas

Toca en cualquier punto del lienzo para coger ese color. Después Calco vuelve a la herramienta que tenías.

## Seleccionar

Marca una parte del dibujo y luego decide qué hacer con ella. Mientras Seleccionar está activa, una barra bajo el lienzo tiene la forma, cómo se combina cada marca, la tolerancia de la varita y Pegar si has copiado algo; tocando otra vez la herramienta se abre el resto:

- **Forma**: **Libre** (rodéalo), **Rectángulo** (arrastra una caja) o **Varita** (toca un color: coge la mancha de ese color, tal como se ve con todas las capas, y los vecinos tan parecidos como permita la **tolerancia**; en **Bloque**, todo lo dibujado que se toca con él, sea del color que sea: una cabeza con su contorno, ojos y relleno de un toque).
- **Al marcar**: **Nueva** selección, **Añadir** a la que hay o **Restar** de ella. Un toque en Nueva quita la selección.
- **Seleccionar todo** (⌘A), **Invertir selección** (⇧⌘I) y **Pegar**.

En **pixel art**, el lazo, el rectángulo o Seleccionar todo se quedan solo con los píxeles dibujados dentro, así la selección se ajusta al sprite píxel a píxel; mientras la trazas, se ven marcados los píxeles que va a coger. Lo seleccionado se ve con **hormigas**, y sigue ahí aunque cambies de herramienta, fotograma o capa. Mientras tanto **el pincel, la goma, el relleno, las formas y el dedo solo actúan dentro**: sombrea una mejilla sin salirte de la línea, o colorea una parte del sprite.

Con Seleccionar, la barra de encima tiene **Transformar**, **Rellenar** (con el color actual), **Borrar**, **Copiar**, **Cortar**, **Invertir**, **Pegar** (si has copiado algo) y **Deseleccionar** (✕, ⌘D, Esc). Sin nada seleccionado y con algo copiado, aparece un botón **Pegar** bajo el lienzo.

**Transformar** levanta lo seleccionado para moverlo, escalarlo, estirarlo o girarlo, en todas las capas visibles a la vez, para que las líneas y su color se muevan juntos (las capas bloqueadas y las guías no se mueven; si no hay nada dibujado dentro, un aviso lo dice):

![Una selección transformándose](/crops/es/lasso-selection.jpg)

- **Arrastra por dentro** para moverla.
- **Tirador de la esquina**: escalar. **Tiradores de los lados**: estirar a lo ancho o a lo alto desde el lado contrario, que no se mueve, para el *squash & stretch*. **Tirador redondo**: girar. **Punto central**: el punto alrededor del que escala, estira y gira; arrástralo para moverlo (a los pies, por ejemplo, para que al aplastar sigan en el suelo).
- Mientras escalas o estiras, una etiqueta muestra el ancho y el alto en porcentaje. Cada uno **encaja** en el 100 %, o en las proporciones del otro, con un toque háptico suave.
- **Uniforme | Libre**, bajo el lienzo, es lo que hace la esquina: mantener las proporciones, o estirar el ancho y el alto por separado.
- La barra de encima: **Copiar**, **Cortar**, **Pegar** (si has copiado algo), **Eliminar**, **Voltear en horizontal**, **Cancelar** (✕, Esc) y **Aplicar** (✓, Retorno). Tocar fuera también aplica. Al aplicar, la selección se va con el dibujo.

Lo pegado aparece donde lo copiaste, en el fotograma y la capa en que estés: útil para llevar una pose a otro dibujo y ajustarla.

## Mover

**Mover** coge el dibujo de la capa actual, en el cabezal, para moverlo, escalarlo o girarlo, con los mismos tiradores que Transformar.

![Mover: todo el dibujo](/crops/es/move-all.jpg)

- Al elegir **Mover** se coge **todo el dibujo**, en un recuadro ajustado a la pintura.
- **Toca un trazo** para coger solo ese: un ojo, una mano, una antena. Calco recuerda cada trazo que haces con el pincel, así que coge el trazo exacto aunque se cruce con otros.
- **Arrastra un trazo** para cogerlo y moverlo de una vez.
- **Toca fuera** del recuadro, en un hueco, para soltar lo que mueves (como ✓). Toca otra vez el botón Mover para coger el dibujo entero.

![Mover: un trazo](/crops/es/move-stroke.jpg)

Al escalarlo, estirarlo o girarlo, un trazo **sigue nítido**: Calco lo vuelve a pintar donde cae, con su pincel, en vez de remuestrear sus píxeles. Los trazos borrados, rellenados o transformados con Seleccionar, y las imágenes importadas, se remuestrean.

Donde se cruzan varios trazos, **toca otra vez en el mismo sitio** para pasar al de debajo; el aviso bajo el lienzo dice cuál tienes. **Añadir trazos** hace que cada toque añada un trazo a lo que mueves, o lo quite, para mover varios juntos.

![Coger el trazo de debajo](/crops/es/move-crossing.jpg)

Al mover, girar y escalar, la forma **se engancha** a su sitio de inicio, recta (o a un cuarto de vuelta) y a su tamaño, con un toque suave que se nota; el pivote se engancha al centro. Así siempre puedes volver a donde empezaste. Toca fuera, cambia de herramienta o de fotograma para soltarlo; todo el movimiento se deshace en un paso.

- Los trazos movidos siguen siendo trazos: puedes volver a cogerlos.
- La **goma** recorta los trazos por los que pasa. Un **relleno**, **Seleccionar** o pegar funden el dibujo, que entonces se separa en sus formas sueltas.
- En una capa **bloqueada**, como una [imagen importada](./layers#imagenes-de-referencia), Mover ofrece **Desbloquear y mover**, y la vuelve a bloquear al terminar.

**Delante o detrás**: con trazos, formas o paths cogidos, la barra de encima tiene **Traer al frente**, **Subir uno**, **Bajar uno** y **Llevar al fondo**: su sitio entre las demás piezas del dibujo, en la misma capa. Se ve al momento y se queda (un paso de deshacer) con ✓.

## Formas

**Formas** dibuja líneas, flechas, rectángulos, elipses, triángulos, polígonos, estrellas y rectángulos redondeados. El icono de la barra muestra la forma elegida; tócalo otra vez para sus opciones:

- **Forma**, y los **lados** del polígono o las **puntas** de la estrella.
- **Trazo**: continuo, discontinuo o por puntos.
- **Grosor**: también con la barra de tamaño mientras Formas está elegida.
- **Relleno**: sin relleno, relleno o solo relleno. Con relleno, elige **El de la línea** o **Otro color** para darle al interior su propio color, distinto del borde (el color de la barra).
- **Pincel**: el entintador, para una línea limpia, o el pincel que tengas elegido (un cuadrado a lápiz, con grano).

Arrastra de esquina a esquina sobre el lienzo; la forma sale con el color de la barra al levantar el dedo. Cerca de 1:1 **encaja** en un cuadrado o un círculo perfecto, y las líneas y flechas cada 45°, con un toque háptico; la etiqueta de debajo dice la medida.

Cada forma es un deshacer, y una pieza de su dibujo: con **Mover**, un toque la coge entera y sigue nítida al escalarla, estirarla o girarla.

## Pluma

La **Pluma** dibuja uniendo puntos:

- **Toca** para poner un punto; se une al anterior con una recta.
- **Arrastra al poner un punto**, o tira después de él, para curvarlo: salen dos manejadores que dan la forma a la curva a cada lado. Tira de un manejador para cambiarla; en un punto curvo los dos giran juntos.
- **Toca la línea** para añadir un punto ahí y curvar desde ese sitio.
- **Toca el primer punto** para cerrar el trazado.

Mientras el trazado está abierto, la barra de debajo del lienzo pasa el punto elegido a **Esquina** o **Curva**, cierra o abre el trazado, **borra el punto**, abre su **Estilo**, cancela (✕) o termina (✓, **Hecho**). Cambiar de herramienta, de fotograma o de capa también lo termina.

**Estilo** (o tocar otra vez la Pluma) cambia el trazo (continuo, discontinuo o por puntos), el grosor, el relleno (en trazados cerrados) y el pincel del trazado abierto; son los mismos ajustes que los de **Formas**. El color es el de la barra: al abrir un trazado, la barra toma el suyo, y un color nuevo se le aplica.

Un trazado **se puede volver a editar**: con la Pluma, tócalo y vuelven sus puntos. Es una pieza del dibujo, así que con **Mover** se coge entero y sigue nítido al escalarlo o girarlo.

## Nodo

**Nodo** edita trazados y formas punto a punto, sin dibujar nunca:

- **Toca un trazado de la Pluma o una forma** para ver sus nodos. Las formas (rectángulos, elipses, polígonos…) se editan como trazados: una elipse son cuatro nodos curvos. Las flechas no se pueden editar así.
- **Arrastra un nodo** o sus manejadores para cambiar la forma. Nodo no añade nodos: para eso está la Pluma.
- **Arrastra en un hueco** para hacer un recuadro: coge todos los nodos que haya dentro, y al arrastrar uno se mueven todos juntos.
- **Toca dos veces un nodo** para pasarlo de esquina a curva y al revés.
- **Toca fuera del trazado** para terminar (como ✓); un toque en su línea suelta los nodos elegidos.

La barra de debajo es la de la Pluma: cuántos nodos tienes, **Esquina** o **Curva** para todos, borrarlos, cancelar o terminar. Se puede pasar de la Pluma a Nodo sin cerrar el trazado.

## Dedo

El **Dedo** trabaja la pintura que ya hay en la capa:

- **Difuminar** la arrastra con el dedo.
- **Desenfocar** la suaviza por donde pasas.
- **Movimiento** la emborrona en la dirección en que mueves el dedo, como una estela.

Toca otra vez el Dedo para elegir el modo, la **fuerza** y la **punta** (suave, o la del pincel elegido). El tamaño es el de la barra, y cuanto más aprietas con el Pencil, más trabaja la pintura. Lo que pasa por el Dedo deja de ser un trazo que Mover recuerda: queda como píxeles.

## Cuadrícula

El botón de **cuadrícula**, arriba a la derecha, hace que los movimientos vayan a pasos: lo que mueves con Mover, Transformar o Pegar se asienta en la cuadrícula, con su esquina superior izquierda en una línea, cada 1, 2, 4, 8, 16 o 32 píxeles. Un bloque de 16 px cae justo en una casilla de 16 px. **Ver la cuadrícula** dibuja sus líneas, tenues, sobre el lienzo. Los movimientos siguen enganchando en su sitio de partida. Se guarda con el proyecto.

## Simetría

El botón de **simetría**, arriba a la derecha, pinta con un espejo: **Izq.–der.**, **Arriba–abajo** o **Cuatro**. El pincel, la goma y el dedo pintan también en el espejo mientras dibujas; el relleno, las formas y la Pluma no.

- Los ejes se ven discontinuos sobre el lienzo. Arrastra el **punto** del extremo de uno para moverlo; se engancha al centro, y un doble toque centra los dos.
- Los ejes caen en el borde o el centro de un píxel, así que en **pixel art** el espejo es exacto, píxel a píxel.
- Se queda activada, con sus ejes, en el proyecto: un sprite simétrico sigue siéndolo.

## Paleta del proyecto

El panel de color empieza con los colores del proyecto, con nombre: la línea del personaje, el cuerpo, la cara… Toca uno para pintar con él.

- **+** guarda el color actual en la paleta. Un proyecto sin paleta tiene **Desde los dibujos**, que toma los colores que más se usan en sus dibujos.
- Mantén pulsado un color para **Renombrarlo**, **Duplicarlo como variante**, **Quitarlo** o **Cambiarlo en todo el proyecto…**: elige el color nuevo y cada píxel del antiguo pasa a ser el nuevo, en todos los dibujos de todos los clips, con los bordes suaves, incluso donde toca otro color. Los trazos recordados también cambian, así que siguen nítidos con Mover. Un solo deshacer lo devuelve todo.

Sirve para cambiar la paleta de un personaje: duplica un proyecto o un clip, pasa el rojo del enemigo a azul y ya tienes un segundo enemigo. Las guías no se tocan. En los proyectos de pixel art solo cambia el color exacto.

## Pixel art

Con **Pixel art** activado, todas las herramientas trabajan con píxeles enteros: sin bordes suaves en el pincel, la goma, el relleno ni las selecciones, y las selecciones movidas siguen nítidas. Actívalo al crear el proyecto o en las opciones del pincel.

## Vista

- **Voltear la vista** (el icono del espejo en la barra superior, o H) muestra el dibujo en espejo sin modificarlo, para ver los errores con otros ojos.
- **Ajustar** vuelve al lienzo centrado y recto (⌘0); si la vista está volteada, sigue volteada.
- El **modo Zen** oculta todo menos el lienzo y una pequeña barra flotante con deshacer, rehacer, todas las herramientas y el color. Desliza **tres dedos hacia abajo** para entrar y **hacia arriba** para salir, como el agarre de la línea de tiempo (o ⌃⌘F).

![Modo Zen](/screens/es/zen.jpg)
