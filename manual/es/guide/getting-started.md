# Primeros pasos

Calco es una app de iPad para dibujar a mano animaciones de sprites: el reposo, el paso, el salto y el ataque de un personaje, fotograma a fotograma, listos para meterlos en un juego.

![El editor de Calco](/screens/es/editor.jpg)

## Lo que ves

El editor tiene cuatro zonas:

| Zona | Para qué sirve |
|---|---|
| **Barra de herramientas** (izquierda) | Pincel, goma, relleno, cuentagotas, lazo, color, tamaño, deshacer y rehacer. Ver [Herramientas de dibujo](./drawing). |
| **Lienzo** (centro) | Donde dibujas. Pellizca para ampliar y usa dos dedos para desplazar y girar. |
| **Barra superior** | El menú de archivo a la izquierda; voltear la vista, ajustes del papel cebolla y modo Zen a la derecha. |
| **Línea de tiempo** (abajo) | Clips, capas y sus dibujos, la reproducción y la barra de fotogramas. Ver [Línea de tiempo y dibujos](./timeline). |

## Tu primera animación en cinco pasos

1. En la galería, toca **Nuevo**, elige un tamaño de sprite y los clips que necesites (Idle, Run…) y toca **Crear y empezar a dibujar**. Ver [Galería y proyectos](./gallery).
2. Dibuja la primera pose con el Apple Pencil en la capa **Line**.
3. Toca el **+** naranja de la barra para añadir el siguiente dibujo. El anterior se ve en rojo transparente (el [papel cebolla](./onion-skin)) para que puedas seguirlo.
4. Repite y toca **▶** para reproducir. Cambia la velocidad con **fps − +**, o haz que un dibujo dure más con **Dura N fotogramas**.
5. Abre el menú de archivo → **Exportar…** y elige un perfil, por ejemplo **Unity**. Ver [Exportar a tu juego](./export).

::: tip Todo se guarda solo
Los proyectos viven en la galería y se guardan solos al salir del editor o cuando la app pasa a segundo plano. **Guardar** (⌘S) está ahí por si quieres asegurarte.
:::

## Vocabulario rápido

- **Proyecto**: un personaje u objeto, con su tamaño de lienzo y su velocidad.
- **Clip**: una animación de ese personaje (Idle, Walk, Jump). Cada clip se exporta como una animación propia.
- **Capa**: una hoja apilada sobre las demás, como la línea encima del color.
- **Dibujo**: lo que muestra una capa durante un tiempo. Un dibujo puede durar varios fotogramas.
- **Fotograma**: un paso del clip. Su duración se cuenta en ticks de los fps del clip.
