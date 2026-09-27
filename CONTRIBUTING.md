# Contributing

## Layout

```
supabase/     schema, the ingest edge function, and their tests
packages/     the pub.dev SDK, plus a two-router example app
apps/         the Flutter web dashboard
```

## Before opening a pull request

Everything CI runs, you can run locally. None of it needs a Supabase account,
Docker, or network access.

```bash
# Backend: schema, RLS, and the edge function
./supabase/tests/run.sh
./supabase/tests/ingest_test.sh

# Dart, in packages/guidester and apps/dashboard
dart format --set-exit-if-changed .
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

`flutter analyze` must be clean at **info** level. The lint set in
`analysis_options.yaml` is deliberately stricter than `flutter_lints`: the
compiler is cheaper than review.

**The dashboard's golden tests run locally and not on CI, and that is the one
place your machine checks something the runner cannot.** Be clear-eyed about the
cost: goldens now verify nothing on the runner, so a genuine layout regression
can land on `main` in silence. If that starts to matter, the fix is a
**fixed-raster container** that renders text identically everywhere, not a wider
tolerance — a threshold big enough to absorb a font difference is also big enough
to absorb the 14px overflow a golden caught in Block D. They are tagged
`golden`, and CI passes `--exclude-tags golden`, because the goldens were
authored on macOS and Linux renders text through a different font stack — a
diff of 1.84% on the onboarding step full of code and 0.21% on the near-empty
shell, none of it a layout change. So `flutter test` on your machine is the
gate. Regenerate deliberately, never to make red go away:

```bash
flutter test --update-goldens        # then look at the diff before committing
```

**Bumping the SDK version touches the dashboard too.** The onboarding install
snippet (`apps/dashboard/lib/src/widgets/onboarding_previews.dart`) must name the
version in `packages/guidester/pubspec.yaml`; `install_preview_test` enforces it,
and the step 02 golden shows it. Change all three together: pubspec plus
`lib/src/version.dart`, the snippet, then regenerate `onboarding_02_1440.png`. Found
on #20, where the SDK went to 0.5.1 and the dashboard job failed.

## What the tests are for

The security model is the product. `supabase/tests/rls_test.sql` asserts it
behaviourally — that the `anon` role reads nothing and writes nothing, that
tenants are isolated in both directions, and that screenshots are scoped by
project folder — with Supabase's default table grants applied, so RLS is the
only thing standing.

**If you change a policy, the bucket, or the schema, add an assertion.** Those
tests are mutation-tested: granting `anon` read access, making the bucket
public, or removing the folder scope each fail a specific named assertion. A
change that quietly weakens the model should fail loudly.

### Green for the wrong reason — the failure this project keeps repeating

Three times now a test has been green while the thing it named was broken, and
the cause was the same each time: **the assertion and the mechanism it was
supposed to prove were not independent.** The test could only observe the
mechanism through the mechanism.

- A detached `NavigatorObserver` reported a stale screen name. The test built
  the observer stack by hand, and a hand-built stack never looks detached.
- A `TabController` **is** an `Animation`, so the usual `if (indexIsChanging)
  return;` guard skips every tick. Twenty-one tests passed; a real browser found
  it in one click.
- A Postgres view read straight past row-level security. Every attack in the
  security run returned empty, because no policy grants `anon` anything — and a
  definer view reintroduces the read path from the side, where no policy is
  consulted at all. The assertion that would have caught it then **passed with
  the protection removed**, because no seeded row matched the view's `where`
  clause. A green assertion over an empty table proves the query ran. It proves
  nothing about what the query would have been allowed to return.

**So, two rules, and the second is the one people skip:**

1. **Break it and watch the test fail.** Every suite here has been verified to go
   red on a deliberately broken input. A test that cannot go red is decoration.
2. **Make sure there is something to see.** Seed a row the assertion would catch,
   then assert. Otherwise step 1 passes too, and you have proved only that
   nothing was there.

## SDK constraints that are not negotiable

These are load-bearing. Changing one breaks something that is not obvious from
the diff:

1. **Dependencies.** `http`, `shared_preferences`, `device_info_plus`,
   `package_info_plus`. Nothing else. An SDK that drags a backend client into
   every host app is a bad citizen.
2. **`if (!Guidester.isEnabled) return widget.child;` is the first line of
   `build()`.** It is the production kill switch.
3. **Overlay chrome lives outside the `RepaintBoundary`**, or it lands in the
   screenshot.
4. **The tap catcher exists only while `_commentMode && _pin == null`.** Leave
   it up and the composer cannot be tapped.
5. **Never push a route or replace the widget tree.** Not taking the host app
   over is the entire positioning of this package, and the source of a whole
   class of bugs we do not have.
6. **Capture and context gathering stay bounded.** Telemetry is never worth
   losing a comment over.

## Third-party source

`feedback-master/` may appear in a working tree as reference material. It is
Apache-2.0 and `.gitignore`d. **Read it; never paste from it.** Every line in
this repository is written from scratch.

## Commits

Conventional Commits (`feat:`, `fix:`, `test:`, `chore:`, `docs:`). Explain
*why* in the body when it is not obvious from the diff.

## Decisions

Code comments and docs refer to decisions by number (D36, D71, D77). The decision
log is kept privately, so each comment says enough on its own to follow the
reasoning. If you make a call a future reader would question, put the reasoning
and the case against it in the pull request, and in a comment next to the code.
