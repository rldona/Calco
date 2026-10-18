# Capas

Cada clip tiene una pila de capas, de arriba abajo en la línea de tiempo. Los clips nuevos empiezan con **Line** arriba y **Color** debajo, la forma habitual de animar: primero la línea y después el color.

Cada capa tiene **sus propios dibujos y su propio ritmo**. Line puede cambiar en cada fotograma mientras Color mantiene el mismo relleno durante tres, o una capa de fondo puede quedarse quieta todo el clip.

## En la línea de tiempo

A la izquierda de cada fila:

- **Ojo**: muestra u oculta la capa. Las capas ocultas no se exportan (Calco te avisa antes de exportar).
- **Nombre**: tócalo para dibujar en esa capa. Se resalta en naranja.
- **Candado**: protege la capa del lápiz, la goma, el relleno y el lazo.

Mantén pulsado el nombre para **Renombrar…**, **Opacidad…**, **Enmascarar con la capa de abajo**, **Subir**, **Bajar** y **Eliminar capa…**.

## El panel de capas

**Capas** en la barra inferior abre el panel completo: arrastra el tirador para reordenar, un control de opacidad para la capa seleccionada y botones para añadir, renombrar, vaciar, enmascarar y eliminar.

![Panel de capas](/crops/es/layers-panel.jpg)

## Nueva capa

**Nueva capa** en la barra inferior ofrece tres tipos:

![Menú de nueva capa](/crops/es/new-layer-menu.jpg)

- **Capa vacía**: una capa en blanco encima de la actual.
- **Mismo ritmo que Line, vacía**: una capa *debajo* de la actual con los mismos dibujos y pausas, todos vacíos. Perfecta para colorear: un dibujo vacío esperando bajo cada dibujo de línea.
- **Duplicar Line**: una copia con todos sus dibujos.

## Enmascarar con la capa de abajo

Una capa enmascarada solo se ve donde la capa de debajo tiene pintura, como una máscara de recorte. Pon una capa **Sombras** encima de **Color**, enmascárala y pinta sin miedo: las sombras nunca se salen del color. Varias capas enmascaradas seguidas comparten la misma base. Las capas enmascaradas se exportan aplanadas, tal como las ves.

::: tip Color y línea, paso a paso
1. Dibuja la animación en **Line**.
2. **Nueva capa → Mismo ritmo que Line, vacía** crea una capa de color debajo.
3. Selecciónala y usa el **relleno**: las líneas de Line hacen de contorno y la pintura va a la capa de color.
:::
