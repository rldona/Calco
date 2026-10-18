# Exportar a tu juego

Menú de archivo → **Exportar…** (⌘E) abre la hoja de exportación. A la izquierda, los **perfiles**; a la derecha, los ajustes del seleccionado. Los cambios se guardan directamente en el perfil, así el siguiente proyecto se exporta igual.

![Exportar](/crops/es/export.jpg)

## Perfiles

Calco trae de serie:

| Perfil | Exporta |
|---|---|
| **Unity** | Hoja de sprites + JSON, para el importador calco-unity. |
| **Unity · trimmed** | Lo mismo, recortado y en potencia de dos. |
| **Pixel art 4×** | Hoja de sprites a 4×, sin desenfocar. |
| **GIF to share** | Un GIF por clip. |
| **PNG frames** | Una carpeta por clip, un PNG por tick. |
| **Godot** | Hoja de sprites + SpriteFrames `.tres`. |

**Duplicar perfil** para crear el tuyo, **Eliminar perfil**, o **Restaurar perfiles de serie**. **Exportar de nuevo** (⇧⌘E) repite la última exportación sin abrir la hoja.

## Ajustes

- **Exportar como**: hoja de sprites + JSON, GIF, secuencia PNG o Godot SpriteFrames.
- **Clips**: todos o solo algunos.
- **Escala**: ½×, 1×, 2× o 4×. Al ampliar, los píxeles siguen nítidos.
- **Recortar bordes transparentes**: cada clip se recorta a la caja que usan sus dibujos; el pivote se mantiene en su sitio.
- **Margen** entre fotogramas y **Hoja en potencia de dos** para motores antiguos.

## Antes de exportar

Calco revisa los clips y te enseña lo que merece una segunda mirada. Solo son consejos: un salto levanta los pies a propósito, por ejemplo.

![Comprobaciones y ajustes de Unity](/crops/es/export-checks.jpg)

- Fotogramas vacíos en un clip que sí tiene dibujos.
- Capas ocultas con dibujos (no se exportarán).
- **Pies que patinan**: en clips con el pivote en el suelo, el punto más bajo se mueve entre fotogramas.
- Bucles cuyo último fotograma repite el primero, lo que hace que el bucle dé un tirón.

## Unity

Copia el paquete `calco-unity` en tu proyecto de Unity y suelta el PNG y el JSON exportados en Assets: crea los sprites, una animación por clip y un Animator Controller.

- **Fijar píxeles por unidad**: escribe los píxeles por unidad de la textura.
- **Etiquetas como eventos de animación**: un dibujo con la etiqueta *step* llama a `OnCalcoLabel("step")` en el GameObject cuando se reproduce su fotograma. Añade ese método a un script del mismo objeto.

## Godot

El perfil **Godot** escribe el PNG y un recurso `SpriteFrames` (`.tres`) con una animación por clip, las duraciones de cada fotograma y los fps del clip como velocidad. Mantén los dos archivos juntos; ajusta el offset del AnimatedSprite2D para el pivote.

::: info Dónde van las exportaciones
A **En mi iPad › Calco › Exports › proyecto › perfil**. Después de exportar, la hoja de compartir te deja enviarlas por AirDrop o a Archivos.
:::
