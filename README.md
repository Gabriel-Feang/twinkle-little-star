## Twinkle Little Star

A tiny cosmic platformer built with LÖVE 11.x. Run, jump, grapple, and slingshot between miniature planets, rescue all baby stars, and dive into the black hole to win.

### Highlights
- **Orbiting worlds + black hole gravity**: Smooth planet surface movement and airy space flight influenced by nearby bodies.
- **Baby stars**: Each planet has a crying baby star. Touch to collect; they orbit you. Win by collecting them all, then entering the black hole.
- **Bigger map, more planets**: A colorful spiral of planets with varied patterns and rotations.
- **Asteroids that matter**:
  - Rockier visuals and shimmering comet trails.
  - Some planets **capture** passing asteroids; they orbit the planet for exactly five spins before being released.
  - Getting hit causes an explosion and sends the babies back to their planets (progress lost), and you lose the grappling hook if you had it.
- **Power-ups**:
  - **Blue Ball (Shield)**: Destroy asteroids on contact and become less affected by planet gravity. Breaks when you touch the ground of any planet.
  - **Grappling Hook**: Aim with the mouse and LMB to latch onto a planet and pull yourself in. Max rope length equals 5 stars plus 1 star for each baby you currently carry. Lost if you get hit by an asteroid.
  - **Pizza**: Makes you fat. That’s it (bigger hitbox; easier to get bonked).
- **Hazard planets**: Some worlds feature lava rings or spikes; touching the surface kills you.
- **Juice**: Additive glow, explosion bursts, orbiting followers, spinning world patterns.
- **Procedural audio**: Rhythmic, mysterious, nostalgic music; SFX for jump, land, collect, cry, and explosion.

### Controls
- **Move**: A / D or Left / Right
- **Jump**: W / Up / Space / Z
- **Grapple**: Left Mouse Button (after picking the hook power-up)
- **Reset**: R (new map and state)

### Goal
- Collect all baby stars from their planets.
- Enter the black hole while carrying all babies to win.

### Notes & Tips
- The shield destroys asteroids but breaks when your feet touch any planet.
- Without a shield, asteroid hits cause an explosion, reset all collected babies back home, and remove your grappling hook.
- Some planets attract asteroids into local orbits; time your approach or find another route.
- Lava/spike planets are lethal the moment you land.

### Run locally
Requires LÖVE 11.x.

- macOS (Homebrew):
  - Install: `brew install --cask love`
  - Run from project folder: `love .`
- Windows/Linux:
  - Download LÖVE from `https://love2d.org/` and run the project folder with it.

### Folder
- `main.lua`, `conf.lua` — all code and procedural audio/assets are generated on the fly.

### Roadmap ideas
- Achievements and time trials
- More power-up variety and planet biomes
- Post-win endless mode or score attack

---
Made with love (and LÖVE).