# lib/api — Generated OpenAPI client

This directory holds the **dart-dio + built_value** client generated from the backend
OpenAPI contract. It is part of the `lumen` package, so the sources import as
`package:lumen/api/...`. The HTTP entry class is `Lumen` (`lib/api/api.dart`); the typed
operations live on `LumenApiApi` (`lib/api/api/lumen_api_api.dart`).

**Do not hand-edit any files here.** Everything (including the `*.g.dart` built_value
files) is regenerated from the pinned spec at `client/openapi/lumen.openapi.json`.

## Why not the `openapi_generator` build_runner package?

The `openapi_generator` Dart package (the `@Openapi(...)` annotation approach) is
**incompatible** with this app's toolchain: its latest release (7.0.0) pins
`source_gen <=2.0.0`, while `built_value_generator ^8.12.5` (a required dev dep) needs
`source_gen >=3.0.0`. `flutter pub add dev:openapi_generator` fails version solving.
We therefore invoke the `openapi-generator-cli` JAR directly (the same underlying
generator) and run `built_value` codegen via the app's own `build_runner`.

## Regenerating

Requires Java 21 and the `openapi-generator-cli` JAR (7.x; 7.11.0 was used). On this
machine the JDK ships with Android Studio:

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"

# 1. (Re)generate the dart-dio sources from the pinned spec into a temp dir.
#    pubName=lumen + sourceFolder=api  ->  imports as package:lumen/api/... and keeps the
#    generated code as first-class sources of the lumen package. This is deliberate: a
#    single language version keeps each built_value part (*.g.dart) consistent with its
#    library (a nested path-package at a different SDK floor triggers a CFE
#    "language version override has to be the same in the library and its part(s)" error).
java -jar <path>\openapi-generator-cli-7.x.jar generate `
  -i client\openapi\lumen.openapi.json `
  -g dart-dio `
  -o <tmp-out> `
  --additional-properties=pubName=lumen,pubLibrary=lumen.api,sourceFolder=api

# 2. Copy <tmp-out>\lib\api\* into client\lib\api\ (preserve this README).

# 3. Generate the built_value *.g.dart files from the app root:
$env:PUB_CACHE = 'C:\pub_cache'
flutter pub get
dart run build_runner build
```

> **`--delete-conflicting-outputs` is gone (corrected P4a/T22).** build_runner **2.15.0** removed the
> flag: passing it prints a deprecation warning and proceeds, because deleting conflicting outputs is
> now the default behaviour. Earlier revisions of this file documented it; drop it from the command.

**Commit the regenerated `*.g.dart` files.** `.github/workflows/ci-client.yml` runs `pub get` →
`analyze` → `test --coverage` and **never** runs `build_runner`, so uncommitted generated code means CI
tests stale bindings. Note also that `client/analysis_options.yaml` excludes `lib/api/**` and
`**/*.g.dart`, so **`flutter analyze` cannot detect a broken regenerated client** — it reports "No
issues found" against deliberately stale `*.g.dart`. The real compile gate for this directory is
**`flutter test`**.

`serializationLibrary` defaults to `built_value` for the `dart-dio` generator. The
generated client depends on `dio`, `built_value`, `built_collection`, `one_of`, and
`one_of_serializer` (all declared in the app `pubspec.yaml`).

The pinned spec at `client/openapi/lumen.openapi.json` is a byte-identical copy of
`backend/contract/openapi.json`, which is emitted + drift-checked by
`backend/tests/Lumen.IntegrationTests/OpenApiSnapshotTests.cs`
(run that test with `LUMEN_OPENAPI_UPDATE=1` to refresh both snapshots).
