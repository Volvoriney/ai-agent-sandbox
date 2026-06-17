# Tasks: absolute-compose-paths

## 1. Dispatcher

- [x] 1.1 `sandbox.sh`: export `SANDBOX_ROOT="$ROOT"` (so every compose call has it)

## 2. Compose files → `${SANDBOX_ROOT}` absolute paths

- [x] 2.1 `compose.eshop.yml`: `build.context`, `dockerfile`, and all volume sources use `${SANDBOX_ROOT}/…`
- [x] 2.2 `compose.medplum.yml`: same
- [x] 2.3 Add a one-line header note to each compose file: "invoke via sandbox.sh, which sets SANDBOX_ROOT"

## 3. Verify

- [x] 3.1 eShop: `up` + `run` green via dispatcher (paths resolve)
- [x] 3.2 Medplum: `up` + `run` green via dispatcher

## 4. Docs

- [x] 4.1 README: note that host paths are `${SANDBOX_ROOT}`-rooted and the dispatcher sets it
