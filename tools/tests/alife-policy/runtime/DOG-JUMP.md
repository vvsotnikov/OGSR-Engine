# Native dog jump validation

Vanilla SoC defines bite parameters for `stand_attack_0` but none for its default
`jump_right_0` movement animation. The default jump therefore uses the named bite;
`anim_jump_ataka_02` remains a movement choice. If that motion has a hit row,
it supplies jump damage; otherwise the named bite is used. `jump_attack_params_anim`
can explicitly select another row, independently of movement. Resolution happens
after the attack table is rebuilt on each reinit, before combat; the cached row
remains valid until the next reinit. An explicit missing row never falls back.
Missing required entries are content errors in every build, never a request to
use an arbitrary first attack. Multiple hit events for one motion retain their
existing ordering; name-only jump lookup selects its first configured event.

Use an isolated installation prepared by `Prepare-RegularValidation.ps1`, an
original Bar save, and a Debug or Release package with its validated `build.json`:

```powershell
./Run-DogJumpValidation.ps1 -InstallRoot $install -Package $package -Case default
./Run-DogJumpValidation.ps1 -InstallRoot $install -Package $package -Case explicit
./Run-DogJumpValidation.ps1 -InstallRoot $install -Package $package -Case override
./Run-DogJumpValidation.ps1 -InstallRoot $install -Package $package -Case damage
./Run-DogJumpValidation.ps1 -InstallRoot $install -Package $package -Case missing
./Run-DogJumpValidation.ps1 -InstallRoot $install -Package $package -Case empty
```

Pass `-Configuration Release` when using a Release package; run the missing/empty
cases there too, since their rejection must not depend on Debug assertions.

The private fixture places an invulnerable pack near an elevated actor so the
production attack AI and jump controller produce hits. An enemy filter excludes
ambient NPC targets and an initial hit from the actor attracts attention (the
fixture immunity prevents damage). Script control is not taken, because it
disables attack jumps. This scenario does not test general enemy choice. A lone dog may panic instead.
God mode protects the actor: evidence verifies the power and impulse passed to
`HitEntity`, not the actor's health loss. Positive cases require matching dog IDs
and actual jump-hit records; merely spawning or waiting cannot pass. The negative
cases require the exact missing-parameter fatal error during initialization, not
a clean game exit. Overrides use the real `jump_right_0` motion, with distinct
parameters to distinguish movement-row selection from the explicit damage key.

CTest checks preparation, evidence rejection and Lua syntax without launching
the game. Run the separate particle-pool roundtrip scenario for map transitions.
