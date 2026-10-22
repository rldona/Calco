# Calcar un movimiento

Anima primero el movimiento en otro sitio: un monigote en StykAnimate o Pivot, un modelo text-to-motion o un vídeo rotoscopiado. Exporta un PNG por fotograma y calca encima tu personaje en Calco. Las imágenes entran como **guía**: una por fotograma, tenue y sin exportarse nunca.

## En cinco pasos

1. Exporta el movimiento como **imágenes PNG, una por fotograma**, con fondo transparente si puedes. Nómbralas en orden: `walk_1.png`, `walk_2.png`… (Calco ordena `walk_2` antes que `walk_10`).
2. En Calco, abre el clip y toca **+** sobre los nombres de las capas → **Secuencia como guía…**.
3. Elige las imágenes, o la carpeta que las contiene.
4. Revisa las opciones (abajo) con la vista previa: muestra cada imagen sobre el fotograma al que va. Arrastra el control de debajo para ver cualquiera.
5. Toca **Importar**. La guía queda debajo de todas las capas y bloqueada, para que el primer trazo no caiga en ella. Elige la capa en la que dibujas y calca.

## Las opciones

| Opción | Qué hace |
|---|---|
| **En** | Una capa guía nueva (llamada **Guía**), o una guía que ya está en el clip, cuyas imágenes se reemplazan. |
| **Una imagen de cada** | Con 1 se usan todas; con 2, una sí y otra no, para animar a doses desde una exportación a 24 fps. |
| **Los nuevos duran** | Cuánto duran los fotogramas que añade la importación. Los que ya había en el clip conservan su duración. |
| **Empieza en** | El primer fotograma, o el del cabezal. |
| **Crear los fotogramas que falten** | Si hay más imágenes que fotogramas, se añaden al final. Desactivado, solo entran las que caben, y la hoja te dice cuántas. |
| **Encaje** | **Ajustar**: la imagen entera, tan grande como quepa. **Rellenar**: cubre el lienzo, recortando los bordes. **1:1**: a su tamaño, centrada. **Desplazamiento X / Y** la mueve, en píxeles del lienzo. La primera imagen decide el encaje y todas las demás llevan el mismo, para que la figura no salte. |
| **Opacidad** y **Tinte** | Lo tenue que se ve (40 % al empezar) y un color para sus líneas (rojo, azul o verde), para que no parezcan dibujo. |

Calco recuerda estas opciones para la próxima vez.

## Después

- La guía es una capa como las demás: puedes ocultarla, cambiar su opacidad o desbloquearla.
- Para usar otra toma, mantén pulsado el nombre de la guía → **Reemplazar secuencia…**. Se quitan todas las imágenes que tenía y entran las nuevas con las mismas opciones.
- No se exporta nunca, el relleno la ignora y el papel cebolla no la muestra.
- Un solo **deshacer** quita toda la importación, fotogramas incluidos.
- Una imagen que no se puede leer deja su fotograma sin guía; Calco te dice cuántas al terminar.
