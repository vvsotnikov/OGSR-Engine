# Native dog jump validation

Vanilla SoC defines bite parameters for `stand_attack_0` but none for its default
`jump_right_0` movement animation. The default jump therefore uses the named bite;
an explicit `anim_jump_ataka_02` override requires parameters for that animation.
Missing required entries are content errors in every build, never a request to
use an arbitrary first attack. Multiple hit events for one motion retain their
existing ordering; name-only jump lookup selects its first configured event.

Use an isolated installation prepared by `Prepare-RegularValidation.ps1`, an
original Bar save, and a full-Debug package with its validated `build.json`:

```powershell
./Run-DogJumpValidation.ps1 -InstallRoot $install -Package $package -Case default
./Run-DogJumpValidation.ps1 -InstallRoot $install -Package $package -Case override
./Run-DogJumpValidation.ps1 -InstallRoot $install -Package $package -Case missing
./Run-DogJumpValidation.ps1 -InstallRoot $install -Package $package -Case empty
```

The private fixture places an invulnerable pack near an elevated actor so the
normal AI and jump controller produce hits. A lone dog may panic instead.
God mode protects the actor: evidence verifies the power and impulse passed to
`HitEntity`, not the actor's health loss. Positive cases require matching dog IDs
and actual jump-hit records; merely spawning or waiting cannot pass. The negative
cases require the exact missing-parameter fatal error, not a clean game exit.

CTest checks preparation, evidence rejection and Lua syntax without launching
the game. Run the separate particle-pool roundtrip scenario for map transitions.
