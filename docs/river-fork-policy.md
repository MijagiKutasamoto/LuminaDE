# River Fork Policy

## Dlaczego fork
- Kontrola nad zmianami krytycznymi dla UX LuminaDE.
- Odporność na niespodziewane breaking changes upstream.
- Możliwość utrzymywania patchy specyficznych dla produktu.
- Utrzymanie spójnej integracji River z `luminade-sessiond` (GUI-first runtime + input/layout bridge).
- Stabilny kanał IPC sesji (`sessiond` unix socket) dla routingu komend panel/launcher/settings.

## Reguły
1. Upstream `riverwm/river` pozostaje single source of truth.
2. Nasz fork ma gałęzie:
   - `main` (synchronizowana z upstream)
   - `luminade/stable` (release dla distro)
   - `luminade/feature/*` (feature branches)
3. Każdy merge upstream przechodzi smoke test sesji.
4. Patche LuminaDE trzymamy możliwie małe i dobrze opisane.

## Workflow synchronizacji
1. `scripts/sync-river-upstream.sh`
2. Build + test River
3. Rebase/merge patchy LuminaDE
4. Tag release (np. `luminade-river-0.1.0`)

## Co dalej
- Automatyzacja przez GitHub Actions:
  - cotygodniowe fetch upstream,
  - automatyczne PR do `main` forka,
  - raport konfliktów.
