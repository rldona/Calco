# Ciclos e intermedios

## Repetir como ciclo

Un paso, una carrera o la respiración en reposo repiten los mismos pocos dibujos. En vez de copiarlos, **repítelos** enlazados: si cambias uno, cambian todas las repeticiones.

![Repetir como ciclo](/crops/es/repeat-popover.jpg)

1. Ve al último dibujo del ciclo.
2. Toca **Más → Repetir dibujos…** en el riel de animación y elige cuántos de los últimos dibujos repetir.
3. Toca **Repetir N dibujos**. Se añaden después del cabezal, con la misma duración.

Las repeticiones muestran un **icono de enlace** y el número del dibujo que repiten. Dibujar en una repetición edita el original. Las etiquetas también se copian, así que un evento *step* salta en cada vuelta en Unity.

- **Desenlazar** (en el riel, o manteniendo pulsada la celda) convierte una repetición en un dibujo propio, quedándose una copia.
- Eliminar una repetición nunca elimina el original.
- Con **Todas** en el riel, los fotogramas se repiten en todas las capas.

## Intermedio a mitad

Para añadir una pose entre dos dibujos, parte en dos el tiempo del primero: **Más → Partir el dibujo a mitad**.

![Partir el dibujo a mitad](/crops/es/split-menu.jpg)

- **Intermedio vacío a mitad**: la segunda mitad se convierte en un dibujo nuevo y vacío donde dibujar el intermedio. El papel cebolla muestra los dibujos de los dos lados.
- **Duplicar partiendo a mitad**: la segunda mitad se convierte en una copia, para ajustarla desde ahí.

La duración total del clip no cambia y las demás capas no se tocan. El dibujo tiene que durar al menos 2 fotogramas; si la duración es impar, la primera mitad se queda el fotograma de más.
