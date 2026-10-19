# Clips y pivote

Un proyecto contiene un personaje; cada **clip** es una de sus animaciones. En un juego, cada clip se convierte en una animación propia: Idle, Walk, Jump, Attack…

## Gestionar los clips

Toca el nombre de un clip en la línea de tiempo para cambiar. El botón **…** junto a los clips abre su menú:

![Menú del clip](/crops/es/clip-menu.jpg)

- **Nuevo clip…**: empieza con un fotograma vacío y las mismas capas que el clip actual.
- **Renombrar…** y **Eliminar**.

Cada clip tiene sus propios **fps** y su propio ajuste de **bucle**: un paso se repite, un salto se reproduce una vez. Los dos están en el botón **12 fps ⌄**; **Usar los fps del proyecto** vuelve a la velocidad del proyecto.

![Ajustes del clip](/crops/es/clip-settings.jpg)

## Pivote

El pivote es el punto que usa el juego para colocar el sprite, normalmente entre los pies. Activa **Mostrar el pivote** en **12 fps ⌄** para verlo en el lienzo y arrástralo.

![El pivote](/crops/es/pivot.jpg)

El pivote va en la exportación: los sprites de Unity lo mantienen aunque los fotogramas se recorten. Déjalo en el suelo para los personajes que caminan, así Calco puede avisarte si los pies patinan (ver [Antes de exportar](./export#antes-de-exportar)).
