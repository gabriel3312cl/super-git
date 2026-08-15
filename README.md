# Super Git

Gestor git multi-repositorio nativo para macOS (SwiftUI), inspirado en el panel
de control de código fuente de VS Code: ves todos tus repos a la vez, con su
branch, su estado y sus archivos modificados, y puedes hacer stage / commit /
push / pull sin cambiar de carpeta.

## Instalar

Descarga el ZIP de la [última release](../../releases/latest), descomprímelo y
mueve `SuperGit.app` a `/Applications`.

La app está firmada ad-hoc pero **no notarizada por Apple**, así que la primera
vez macOS la bloquea. Para desbloquearla:

```bash
xattr -dr com.apple.quarantine /Applications/SuperGit.app
```

Requiere macOS 14 o superior. El binario es universal (Apple Silicon e Intel).

## Compilar desde el código

Requisitos: Xcode command line tools (Swift 6) y `git` en `/opt/homebrew/bin`,
`/usr/local/bin` o `/usr/bin`.

```bash
./build.sh
open dist/SuperGit.app
```

Para desarrollo rápido, sin bundle:

```bash
swift run
```

Para un binario universal (lo que usa la release):

```bash
UNIVERSAL=1 ./build.sh
```

La primera vez macOS pedirá permiso para acceder a `~/Documents`.

## Qué hace

**Descubrimiento**
- Escanea las carpetas configuradas (por defecto `~/Documents`) hasta 3 niveles
  de profundidad y detecta cualquier carpeta con `.git`.
- Salta `node_modules`, `.build`, `Pods`, `venv`, etc.
- Puedes ocultar repos de la lista y añadir otras carpetas raíz.

**Por repositorio**
- Branch actual (o `detached @ sha`), upstream, y contadores ahead / behind.
- Archivos en staged y sin stage, con su letra de estado (M, A, D, R, U).
  Un archivo con cambios en ambos lados aparece en las dos secciones, igual
  que en VS Code.
- Conflictos en su propia sección.
- Stage / unstage por archivo o masivo, descartar cambios (con confirmación).
- Commit, "stage todo y commit", y amend.
- Fetch, Pull (fast-forward / rebase / merge) y Push. Si el branch no tiene
  upstream, el botón cambia a "Publicar branch" y hace `push -u origin <branch>`.

**Revisión de rama (pestaña «Comparar»)**
- Vista tipo pull request: lista de archivos a la izquierda y el diff a la
  derecha, con números de línea de ambos lados.
- Selector de base: cualquier rama local o remota. Por defecto elige
  `origin/main`, `main`, `master` o `develop`, la primera que exista y no sea
  la rama actual.
- Diff de toda la rama (`base...HEAD`), de un commit suelto o de un tramo de
  commits. Si los commits elegidos no son consecutivos, avisa que el rango
  arrastra también los que quedan en medio.
- «Incluir cambios sin commitear» compara la base contra el árbol de trabajo,
  no contra el último commit, y suma los archivos sin seguimiento (que `git
  diff` no ve). Se activa sola cuando la rama no tiene commits propios pero sí
  trabajo sin commitear, que si no aparecería como «sin diferencias».
- Vista lado a lado o unificada. El ancho se calcula en caracteres, así que
  las columnas quedan alineadas y las líneas largas se ven con scroll
  horizontal en vez de partirse.
- En la vista lado a lado el separador central se arrastra para repartir el
  ancho entre la versión anterior y la nueva, y cada columna tiene su propio
  scroll horizontal. Clic derecho sobre el separador para igualarlas.
- Los signos `+` y `−` se escriben en cada línea: el color no es la única
  señal. Cada fila tiene su etiqueta para VoiceOver.
- Los archivos con más de 500 líneas de diff se recortan (con botón para ver
  el resto) y los de más de 1500 arrancan plegados.

**Refresco**
- Automático cada 20 s (configurable) y al volver a la app.
- `⌘R` refresca el repo activo, `⇧⌘R` vuelve a escanear las carpetas.

## Configuración

`~/.config/super-git/config.json`

```json
{
  "roots": ["~/Documents"],
  "maxDepth": 3,
  "hiddenRepos": [],
  "autoRefreshSeconds": 20
}
```

## Notas de diseño

- Todo se hace ejecutando el binario `git` como subproceso (no libgit2), así
  que respeta tu `.gitconfig`, hooks, credential helpers y claves SSH.
- `GIT_TERMINAL_PROMPT=0`: si una operación remota necesita credenciales que no
  están en el keychain o en el ssh-agent, falla con un mensaje en vez de
  quedarse colgada. Cada comando tiene además un timeout.
- El estado se lee con `git status --porcelain=v2 -z`, que es el formato
  estable pensado para herramientas.

## Estructura

```
Sources/SuperGit/
  SuperGitApp.swift        entrada, AppDelegate, puente a AppKit
  AppModel.swift           estado global y operaciones
  Config/AppConfig.swift   configuración persistida
  Discovery/RepoScanner.swift
  CompareState.swift       estado de la vista de comparación
  Git/GitRunner.swift      ejecución de subprocesos
  Git/GitStatusParser.swift
  Git/GitService.swift     operaciones git de alto nivel
  Git/GitCompare.swift     ramas, commits y diffs entre referencias
  Git/DiffParser.swift     diff unificado → líneas numeradas
  Models/                  Repo, RepoStatus, FileChange, DiffModels
  Views/                   ContentView, SidebarView, RepoDetailView,
                           ChangeRow, CompareView, DiffFileView
Resources/
  AppIcon.svg              icono, fuente vectorial
  make-icon.sh             SVG → AppIcon.icns
.github/workflows/
  ci.yml                   compila en cada push a main
  release.yml              tag v* → binario universal + ZIP en Releases
```

## Publicar una release

```bash
git tag v1.0.0 && git push origin v1.0.0
```

El workflow compila el binario universal, sella la versión en el `Info.plist`,
firma ad-hoc, empaqueta el `.app` en un ZIP y crea la release con ese archivo.

## Próximos pasos naturales

- Visor de diff por archivo (`git diff` / `git diff --cached`).
- Cambio y creación de branches, stash, y grafo de commits.
- Acciones masivas: "fetch en todos los repos", "pull en todos".
