# Capas

Cada clip tiene una pila de capas, de arriba abajo en la línea de tiempo. Los clips nuevos empiezan con **Line** arriba y **Color** debajo, la forma habitual de animar: primero la línea y después el color.

Cada capa tiene **sus propios dibujos y su propio ritmo**. Line puede cambiar en cada fotograma mientras Color mantiene el mismo relleno durante tres, o una capa de fondo puede quedarse quieta todo el clip.

## En la línea de tiempo

A la izquierda de cada fila:

- **Ojo**: muestra u oculta la capa. Las capas ocultas no se exportan (Calco te avisa antes de exportar).
- **Nombre**: tócalo para dibujar en esa capa. Se resalta en naranja.
- **Candado**: protege la capa del lápiz, la goma, el relleno y las selecciones.

Mantén pulsado el nombre para **Renombrar…**, **Opacidad…**, **Enmascarar con la capa de abajo**, **Solo guía (no se exporta)**, **Voltear**, **Subir**, **Bajar** y **Eliminar capa…**.

**Voltear** hace el espejo del dibujo de la capa en el cabezal, en horizontal o en vertical (una cabeza que mira hacia el otro lado), o de todos los dibujos de la capa en el clip a la vez. Los trazos siguen siendo trazos, nítidos y editables; un paso de deshacer.

El botón de puntos sobre los nombres de las capas pone el timeline en modo **compacto**: filas finas con un punto por dibujo (hueco si está en blanco) y una línea por los fotogramas que lo mantienen, para ver muchas capas y fotogramas a la vez. Tócalo otra vez para volver a las miniaturas. Los proyectos de pixel art lo muestran compacto, y el resto con miniaturas.

## El panel de capas

El icono de la pila sobre los nombres de las capas abre el panel completo: arrastra el tirador para reordenar, un control de opacidad para la capa seleccionada y botones para añadir, renombrar, vaciar, enmascarar y eliminar.

![Panel de capas](/screens/es/layers-panel.jpg)

## Nueva capa

El **+** sobre los nombres de las capas (**Nueva capa**) ofrece tres tipos de capa y dos formas de traer una imagen:

![Menú de nueva capa](/crops/es/new-layer-menu.jpg)

- **Capa vacía**: una capa en blanco encima de la actual.
- **Mismo ritmo que Line, vacía**: una capa *debajo* de la actual con los mismos dibujos y pausas, todos vacíos. Perfecta para colorear: un dibujo vacío esperando bajo cada dibujo de línea.
- **Duplicar Line**: una copia con todos sus dibujos.
- **Imagen desde Archivos…** / **Imagen desde Fotos…**: una [imagen de referencia](#imagenes-de-referencia) para dibujar encima.
- **Secuencia como guía…**: una imagen por fotograma, para [calcar un movimiento](./guide-sequence) hecho en otro sitio.

## Imágenes de referencia

Importa un boceto, una hoja de modelo o un fotograma de vídeo de referencia y calca encima. **Nueva capa → Imagen desde Fotos…** (o **Imagen desde Archivos…**) la añade como una capa llamada **Referencia**:

![Una imagen de referencia bajo Pip](/crops/es/guide-canvas.jpg)

- Va **debajo de todas las capas**, ajustada al lienzo sin deformarse, y se ve **durante todo el clip**.
- Está al **40 % de opacidad** y **bloqueada**, así que el lápiz, la goma y el relleno nunca la tocan: sigues dibujando en la capa en la que estabas.
- Es una **guía** (el icono de foto junto al nombre): la ves en el editor, pero **nunca se exporta** y el relleno no la usa como contorno.

![La capa de referencia en la línea de tiempo](/crops/es/timeline-tall.jpg)

Para cambiarla, toca **40%** para su opacidad o el **candado** para desbloquearla. Mantén pulsado el nombre y elige **Exportar esta capa** para que forme parte del sprite, o **Solo guía (no se exporta)** para convertir cualquier capa en guía, por ejemplo una capa de líneas de construcción.

## Enmascarar con la capa de abajo

Una capa enmascarada solo se ve donde la capa de debajo tiene pintura, como una máscara de recorte. Pon una capa **Sombras** encima de **Color**, enmascárala y pinta sin miedo: las sombras nunca se salen del color. Varias capas enmascaradas seguidas comparten la misma base. Las capas enmascaradas se exportan aplanadas, tal como las ves.

::: tip Color y línea, paso a paso
1. Dibuja la animación en **Line**.
2. **Nueva capa → Mismo ritmo que Line, vacía** crea una capa de color debajo.
3. Selecciónala y usa el **relleno**: las líneas de Line hacen de contorno y la pintura va a la capa de color.
:::
