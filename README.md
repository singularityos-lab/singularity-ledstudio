# singularity-ledstudio

> [!IMPORTANT]
> Report bugs and request features in the
> [Singularity Desktop tracker](https://github.com/singularityos-lab/singularity-desktop/issues/new/choose).

LED Studio for the [Singularity Desktop Environment](https://github.com/singularityos-lab): draw, animate and test scenes for LED matrices, such as the one on the Arduino UNO Q.

Scenes combine text, drawings with frames and bars fed by live values (time, battery, CPU, media, notifications). The studio plays them on an emulated matrix, previews them on a real one when present, and sets them as the matrix content in Displays.

## Requirements

- [Meson](https://mesonbuild.com/) ≥ 1.0
- [Vala](https://vala.dev/) compiler
- GTK4, libgee-0.8, json-glib
- [libsingularity](https://github.com/singularityos-lab/libsingularity)

## Build & Install

```sh
meson setup build
meson compile -C build
meson install -C build
```

## License

GPL-3.0-only - see [LICENSE](LICENSE).

## Use of Generative AI

Maintainers may use generative AI tools as assistants while working on singularity-ledstudio. Non-trivial assisted commits disclose the tool, model, and scope of the work.

AI tools may assist with code comments, documentation, repetitive code, and issue triage. Maintainers make project decisions and review every assisted change before it is merged.

Use these trailers for non-trivial assisted commits:

```plain
Assisted-by: <tool>:<model-version>
AI-Scope: <what the tool generated and the prompt or a short prompt summary>
```
