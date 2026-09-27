## What and why

<!-- The change, and the problem it solves. -->

## How it was tested

<!-- CONTRIBUTING asks for a test that fails before the change and passes after. Say which. -->

- [ ] `dart format --set-exit-if-changed .` in `packages/guidester` and `apps/dashboard`
- [ ] `flutter analyze` and `flutter test` pass in both
- [ ] Backend changes: `./supabase/tests/run.sh` and `./supabase/tests/ingest_test.sh`
- [ ] A version bump also updates the dashboard's install snippet and its golden
