-- Little Star: Worlds to Black Hole
-- LÖVE 11.x game

local TAU = math.pi * 2
local STAR_VISUAL_OFFSET = -math.pi / 2 -- rotate star sprite upright

local game = {
  state = "playing", -- "playing" | "win" | "dead"
  time = 0,
}

local camera = {
  x = 0,
  y = 0,
  smoothing = 6.0,
}

local player = {
  x = 0,
  y = 0,
  vx = 0,
  vy = 0,
  radius = 12,
  maxSpeedTangent = 220,
  accelerationTangent = 700,
  frictionTangent = 900,
  jumpSpeed = 320,
  grounded = false,
  currentWorld = nil,
  angle = 0, -- visuals
  -- Air control
  airAccelerationTangent = 420,
  maxAirSpeedTangent = 200,
  airDrag = 200,
}

local blackHole = {
  x = 0,
  y = 0,
  radius = 60,
  gravityStrength = 2600,
  swirlTime = 0,
}

local worlds = {}
local asteroids = {}
local starfield = {}
local babies = {}
local explosions = {}
local powerups = {}
local audio = { music = nil, sfxJump = nil, sfxLand = nil, sfxCollect = nil, sfxBabyCry = nil, sfxExplosion = nil }

local totalBabies = 0
local collectedBabies = 0

-- Player power-up state
player.baseRadius = player.radius
player.hasShield = false -- blue ball
player.hasGrapple = false
player.isFat = false -- pizza

local hook = {
  active = false,
  attached = false,
  hasAnchor = false,
  ax = 0,
  ay = 0,
  dirx = 0,
  diry = 0,
  startx = 0,
  starty = 0,
  tipx = 0,
  tipy = 0,
  length = 0,
  maxLength = 0,
  speed = 900,
  retractSpeed = 600,
  phase = "idle", -- "extending" | "attached" | "retracting"
}
local HOOK_BASE_STARS = 5
local HOOK_PER_BABY_STARS = 1

local palette = {
  { 0.98, 0.78, 0.20 }, -- gold
  { 0.44, 0.90, 0.80 }, -- aqua
  { 0.98, 0.50, 0.44 }, -- coral
  { 0.74, 0.56, 0.94 }, -- lavender
  { 0.48, 0.86, 0.36 }, -- lime
  { 0.96, 0.64, 0.84 }, -- pink
  { 0.48, 0.70, 0.98 }, -- sky
}

-- Utility math functions
local function clamp(value, minVal, maxVal)
  if value < minVal then return minVal end
  if value > maxVal then return maxVal end
  return value
end

local function length(x, y)
  return math.sqrt(x * x + y * y)
end

local function normalize(x, y)
  local len = length(x, y)
  if len == 0 then return 0, 0 end
  return x / len, y / len
end

local function dot(ax, ay, bx, by)
  return ax * bx + ay * by
end

local function perpendicular(x, y)
  return -y, x
end

local function angleOf(x, y)
  return math.atan2(y, x)
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function angleLerp(a, b, t)
  -- shortest arc interpolation
  local diff = (b - a + math.pi) % (2 * math.pi) - math.pi
  return a + diff * t
end

local function randomChoice(t)
  return t[math.random(1, #t)]
end

-- Content generation
local function generateStarfield()
  starfield = {}
  local layers = {
    { count = 360, parallax = 0.25, color = {1,1,1,0.35}, size = 1 },
    { count = 260, parallax = 0.5, color = {1,1,1,0.55}, size = 1 },
    { count = 160, parallax = 0.8, color = {1,1,1,0.8},  size = 2 },
  }
  for _, layer in ipairs(layers) do
    for i = 1, layer.count do
      starfield[#starfield + 1] = {
        x = math.random(-8000, 8000),
        y = math.random(-8000, 8000),
        parallax = layer.parallax,
        color = layer.color,
        size = layer.size,
      }
    end
  end
end

local function generateWorlds()
  worlds = {}
  -- Spiral of worlds from outer to inner space
  local count = 16
  local maxR = 3000
  local minR = 260
  for i = 1, count do
    local t = (i - 1) / (count - 1)
    local orbitRadius = lerp(maxR, minR, t)
    local angle = i * 1.7 -- spiral step
    local x = math.cos(angle) * orbitRadius
    local y = math.sin(angle) * orbitRadius
    local radius = lerp(140, 60, t) + math.random(-12, 12)
    local color = randomChoice(palette)
    local patterns = { "stripes", "dots", "rings" }
    local pattern = patterns[(i - 1) % #patterns + 1]
    worlds[#worlds + 1] = {
      x = x,
      y = y,
      radius = radius,
      color = color,
      edgeColor = { color[1]*0.7, color[2]*0.7, color[3]*0.7 },
      pattern = pattern,
      rotation = math.random() * TAU,
      gravityStrength = 5400 + math.random(-500, 500),
      attractAsteroids = math.random() < 0.35,
      hazardType = (function()
        if math.random() < 0.28 then return (math.random() < 0.5) and "lava" or "spikes" end
        return nil
      end)(),
      hazardData = nil,
    }
  end
end

local function generateBabies()
  babies = {}
  totalBabies, collectedBabies = 0, 0
  for i, w in ipairs(worlds) do
    local angle = -math.pi / 2 + (i % 3) * 0.6
    local r = w.radius + 10
    local bx = w.x + math.cos(angle) * r
    local by = w.y + math.sin(angle) * r
    babies[#babies + 1] = {
      homeWorld = w,
      state = "home", -- "home" | "following"
      x = bx,
      y = by,
      angleOnWorld = angle,
      cryTimer = math.random() * 2 + 1,
      bob = math.random() * TAU,
      followIndex = nil,
      radius = 7,
    }
    totalBabies = totalBabies + 1
  end
end

local function placeOnWorldSurface(world, angleOffset, distance)
  local angle = angleOffset or math.random() * TAU
  local r = world.radius + (distance or 10)
  return world.x + math.cos(angle) * r, world.y + math.sin(angle) * r, angle
end

local function generatePowerups()
  powerups = {}
  -- Ensure at least one of each type across the map
  local types = { "shield", "grapple", "pizza" }
  local chosenWorlds = {}
  -- randomly choose 6 worlds to place powerups
  local indexes = {}
  for i = 1, #worlds do indexes[#indexes+1] = i end
  for i = #indexes, 2, -1 do
    local j = math.random(1, i)
    indexes[i], indexes[j] = indexes[j], indexes[i]
  end
  local count = math.min(6, #worlds)
  for k = 1, count do
    local w = worlds[indexes[k]]
    local ptype = types[((k - 1) % #types) + 1]
    local x, y, ang = placeOnWorldSurface(w, math.random() * TAU, 14)
    powerups[#powerups + 1] = { type = ptype, world = w, x = x, y = y, angleOnWorld = ang, bob = math.random() * TAU, picked = false }
  end
end

local function generateAsteroids()
  asteroids = {}
  local bands = {
    { radius = 1100, num = 6, speed = -0.20 },
    { radius = 850,  num = 5, speed = 0.26 },
    { radius = 620,  num = 4, speed = -0.34 },
    { radius = 400,  num = 3, speed = 0.44 },
  }
  for _, band in ipairs(bands) do
    for i = 1, band.num do
      local angle = math.random() * TAU
      local size = math.random(12, 26)
      local rockShape = {}
      local points = math.random(6, 9)
      for p = 1, points do
        local ang = (p / points) * TAU
        local rr = size * (0.8 + math.random() * 0.5)
        rockShape[#rockShape + 1] = math.cos(ang) * rr
        rockShape[#rockShape + 1] = math.sin(ang) * rr
      end
      asteroids[#asteroids + 1] = {
        orbitRadius = band.radius + math.random(-30, 30),
        angle = angle,
        angularSpeed = band.speed * (0.8 + math.random() * 0.4),
        size = size,
        wobble = (math.random() * 0.3 + 0.1) * (math.random(0,1) == 0 and -1 or 1),
        rockShape = rockShape,
        trail = {},
      }
    end
  end
end

local function resetPlayer()
  -- Start on the outermost world, at the top point
  local startWorld = worlds[1]
  local nx, ny = normalize(1, 0) -- arbitrary initial, will place after
  player.currentWorld = startWorld
  player.grounded = true
  player.vx, player.vy = 0, 0
  local outward = { x = math.cos(-math.pi/2), y = math.sin(-math.pi/2) } -- top of the circle
  player.x = startWorld.x + outward.x * (startWorld.radius + player.radius)
  player.y = startWorld.y + outward.y * (startWorld.radius + player.radius)
  player.angle = -math.pi/2
end

-- Physics helpers
local function gravityFromBlackHole(px, py)
  local dx = blackHole.x - px
  local dy = blackHole.y - py
  local dist = math.max(40, length(dx, dy))
  local dirx, diry = dx / dist, dy / dist
  local g = blackHole.gravityStrength / (dist * dist)
  return dirx * g, diry * g
end

local function gravityFromNearestWorld(px, py)
  local nearest, nearestDist = nil, 1e9
  for _, w in ipairs(worlds) do
    local dx = w.x - px
    local dy = w.y - py
    local d = length(dx, dy)
    if d < nearestDist then
      nearest = w
      nearestDist = d
    end
  end
  if not nearest then return 0, 0, nil, 0 end
  local distToCenter = nearestDist
  local nx, ny = (nearest.x - px) / distToCenter, (nearest.y - py) / distToCenter
  local distToSurface = distToCenter - nearest.radius
  local g = nearest.gravityStrength / math.max(80, distToCenter * distToCenter)
  -- soften when very far
  if distToSurface > 420 then
    g = g * 0.35
  end
  return nx * g, ny * g, nearest, distToSurface
end

local function spawnExplosion(x, y)
  explosions[#explosions + 1] = {
    x = x,
    y = y,
    t = 0,
    duration = 0.9,
    particles = (function()
      local ps = {}
      for i = 1, 64 do
        local a = math.random() * TAU
        local sp = 120 + math.random() * 220
        ps[#ps + 1] = { ax = math.cos(a) * sp, ay = math.sin(a) * sp, life = 0.6 + math.random() * 0.4 }
      end
      return ps
    end)(),
  }
  if audio.sfxExplosion then audio.sfxExplosion:stop(); audio.sfxExplosion:play() end
end

local function tryLandOnWorld()
  local landed = false
  local landingWorld = nil
  for _, w in ipairs(worlds) do
    local dx = player.x - w.x
    local dy = player.y - w.y
    local dist = length(dx, dy)
    local targetDist = w.radius + player.radius
    if dist <= targetDist + 2 then
      -- Check if moving inward
      local nx, ny = dx / math.max(1e-6, dist), dy / math.max(1e-6, dist)
      local radialVelocity = dot(player.vx, player.vy, nx, ny)
      if radialVelocity <= 80 then -- allow gentle approach
        -- Hazard worlds kill on touch
        if w.hazardType ~= nil then
          spawnExplosion(player.x, player.y)
          game.state = "dead"
          return false, nil
        end
        -- Snap to surface and remove radial component
        local px = w.x + nx * targetDist
        local py = w.y + ny * targetDist
        -- Decompose velocity
        local tx, ty = perpendicular(nx, ny)
        local tanSpeed = dot(player.vx, player.vy, tx, ty)
        player.x, player.y = px, py
        player.vx, player.vy = tx * tanSpeed, ty * tanSpeed
        player.grounded = true
        player.currentWorld = w
        landed = true
        landingWorld = w
        break
      end
    end
  end
  return landed, landingWorld
end

-- Input helpers
local function getMoveInput()
  -- Movement disabled: only grappling hook control
  return 0
end

local function jumpPressed(key)
  return key == "space" or key == "w" or key == "up" or key == "z"
end

-- Drawing helpers
local function drawWorld(w)
  love.graphics.push()
  love.graphics.translate(w.x, w.y)
  love.graphics.rotate(w.rotation)

  love.graphics.setColor(w.color)
  love.graphics.circle("fill", 0, 0, w.radius)

  if w.pattern == "stripes" then
    love.graphics.setColor(w.edgeColor)
    love.graphics.setLineWidth(6)
    local step = 28
    for y = -w.radius, w.radius, step do
      local half = math.sqrt(math.max(0, w.radius * w.radius - y * y))
      love.graphics.line(-half, y, half, y)
    end
  elseif w.pattern == "dots" then
    love.graphics.setColor(w.edgeColor)
    for r = w.radius * 0.25, w.radius * 0.9, w.radius * 0.22 do
      local points = math.max(6, math.floor((r / w.radius) * 18))
      for i = 1, points do
        local a = (i / points) * TAU
        love.graphics.circle("fill", math.cos(a) * r, math.sin(a) * r, 3)
      end
    end
  elseif w.pattern == "rings" then
    love.graphics.setColor(w.edgeColor)
    love.graphics.setLineWidth(3)
    for r = w.radius * 0.3, w.radius * 0.95, w.radius * 0.18 do
      love.graphics.circle("line", 0, 0, r)
    end
  end

  -- outline
  love.graphics.setColor(0,0,0,0.25)
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", 0, 0, w.radius)

  -- Hazards visuals (screen-space relative within world transform)
  if w.hazardType == "lava" then
    -- Lava ring
    love.graphics.setLineWidth(12)
    love.graphics.setColor(1.0, 0.35, 0.1, 0.5)
    love.graphics.circle("line", 0, 0, w.radius * 0.85)
    -- Glowing cracks
    love.graphics.setColor(1.0, 0.6, 0.2, 0.6)
    local cracks = 10
    for i = 1, cracks do
      local a = (i / cracks) * TAU + game.time * 0.4
      local r1 = w.radius * 0.65
      local r2 = w.radius * 0.95
      love.graphics.setLineWidth(3)
      love.graphics.line(math.cos(a) * r1, math.sin(a) * r1, math.cos(a) * r2, math.sin(a) * r2)
    end
  elseif w.hazardType == "spikes" then
    -- Spikes around the world
    love.graphics.setColor(0.15, 0.15, 0.2)
    local spikes = math.max(12, math.floor(w.radius / 6))
    for i = 1, spikes do
      local a = (i / spikes) * TAU + w.rotation * 0.3
      local r1 = w.radius
      local r2 = w.radius + 10
      love.graphics.polygon("fill",
        math.cos(a) * r1, math.sin(a) * r1,
        math.cos(a + 0.05) * r1, math.sin(a + 0.05) * r1,
        math.cos(a + 0.025) * r2, math.sin(a + 0.025) * r2
      )
    end
  end

  love.graphics.pop()
end

local function starPolygonVertices(cx, cy, outerR, innerR, points)
  local vertices = {}
  for i = 0, points * 2 - 1 do
    local isOuter = (i % 2) == 0
    local r = isOuter and outerR or innerR
    local a = (i / (points * 2)) * TAU - math.pi / 2
    vertices[#vertices + 1] = cx + math.cos(a) * r
    vertices[#vertices + 1] = cy + math.sin(a) * r
  end
  return vertices
end

local function drawPlayer()
  love.graphics.push()
  love.graphics.translate(player.x, player.y)
  love.graphics.rotate(player.angle)

  local outer = player.radius
  local inner = player.radius * 0.45

  -- Glow (additive)
  love.graphics.push("all")
  love.graphics.setBlendMode("add")
  for i = 1, 5 do
    local r = outer + i * 4
    local a = 0.06 * (6 - i)
    love.graphics.setColor(1.0, 0.95, 0.5, a)
    love.graphics.circle("fill", 0, 0, r)
  end
  love.graphics.pop()

  -- Body
  love.graphics.setColor(1, 0.95, 0.5)
  love.graphics.polygon("fill", starPolygonVertices(0, 0, outer, inner, 5))
  love.graphics.setColor(1, 1, 1, 0.35)
  love.graphics.circle("fill", -outer * 0.15, -outer * 0.1, outer * 0.35)
  love.graphics.setColor(0.1, 0.1, 0.1, 0.35)
  love.graphics.setLineWidth(2)
  love.graphics.polygon("line", starPolygonVertices(0, 0, outer, inner, 5))

  -- Cartoon face
  love.graphics.setColor(0.1, 0.1, 0.15)
  local eyeY = -outer * 0.1
  love.graphics.circle("fill", -outer * 0.22, eyeY, outer * 0.11)
  love.graphics.circle("fill",  outer * 0.22, eyeY, outer * 0.11)
  love.graphics.setColor(1, 1, 1, 0.9)
  love.graphics.circle("fill", -outer * 0.24, eyeY - outer * 0.04, outer * 0.05)
  love.graphics.circle("fill",  outer * 0.20, eyeY - outer * 0.04, outer * 0.05)
  love.graphics.setColor(0.1, 0.1, 0.15)
  love.graphics.setLineWidth(2)
  love.graphics.arc("line", "open", 0, outer * 0.12, outer * 0.35, math.pi * 0.15, math.pi * 0.85)

  love.graphics.pop()
end

local function drawBaby(b)
  love.graphics.push()
  love.graphics.translate(b.x, b.y)
  local a = (b.state == "home") and (b.bob * 0.5) or 0
  love.graphics.rotate(a)
  local outer = b.radius
  local inner = b.radius * 0.45
  love.graphics.setColor(1, 0.95, 0.7)
  love.graphics.polygon("fill", starPolygonVertices(0, 0, outer, inner, 5))
  love.graphics.setColor(0.2, 0.2, 0.25, 0.6)
  love.graphics.setLineWidth(1)
  love.graphics.polygon("line", starPolygonVertices(0, 0, outer, inner, 5))
  -- eyes
  love.graphics.setColor(0.1, 0.1, 0.2)
  love.graphics.circle("fill", -outer * 0.22, -outer * 0.08, outer * 0.10)
  love.graphics.circle("fill",  outer * 0.22, -outer * 0.08, outer * 0.10)
  -- tears when at home (crying)
  if b.state == "home" then
    love.graphics.setColor(0.5, 0.7, 1.0, 0.7)
    local t = (game.time * 6 + b.bob) % 1
    local drop = t * 6
    love.graphics.circle("fill", -outer * 0.22, -outer * 0.08 + drop, 2)
    love.graphics.circle("fill",  outer * 0.22, -outer * 0.08 + drop * 0.9, 2)
  end
  love.graphics.pop()
end

local function drawBlackHole()
  love.graphics.push()
  love.graphics.translate(blackHole.x, blackHole.y)
  local t = blackHole.swirlTime

  -- Accretion disks
  for i = 1, 5 do
    local r = blackHole.radius + i * 14
    local alpha = 0.12 + 0.05 * i
    love.graphics.setColor(0.2, 0.2, 0.3, alpha)
    love.graphics.setLineWidth(10 - i)
    love.graphics.circle("line", 0, 0, r)
  end

  -- Swirl arms
  for i = 1, 24 do
    local a = t * 0.7 + i * (TAU / 24)
    local r1 = blackHole.radius * 0.5
    local r2 = blackHole.radius * 1.3
    love.graphics.setColor(0.1, 0.1, 0.15, 0.15)
    love.graphics.arc("fill", "open", 0, 0, r2, a, a + 0.35)
  end

  -- Core
  love.graphics.setColor(0, 0, 0)
  love.graphics.circle("fill", 0, 0, blackHole.radius)
  love.graphics.setColor(0.8, 0.8, 1, 0.1)
  love.graphics.setLineWidth(3)
  love.graphics.circle("line", 0, 0, blackHole.radius + 4)

  love.graphics.pop()
end

local function drawStarfield()
  local cx, cy = camera.x, camera.y
  for _, s in ipairs(starfield) do
    local px = s.x * s.parallax
    local py = s.y * s.parallax
    local sx = px + (love.graphics.getWidth() / 2 - cx * s.parallax)
    local sy = py + (love.graphics.getHeight() / 2 - cy * s.parallax)
    love.graphics.setColor(s.color)
    love.graphics.circle("fill", sx, sy, s.size)
  end
end

-- Core LÖVE callbacks
function love.load()
  love.window.setTitle("Little Star: Worlds to Black Hole")
  love.math.setRandomSeed(os.time())
  love.graphics.setBackgroundColor(0.03, 0.02, 0.05)

  generateStarfield()
  generateWorlds()
  generateBabies()
  generatePowerups()
  generateAsteroids()
  resetPlayer()
  -- Start with grappling hook
  player.hasGrapple = true

  camera.x, camera.y = player.x, player.y

  -- Audio: SFX and rhythmic, mysterious, nostalgic music
  local function makeTone(freq, duration, vol, decay)
    local rate = 44100
    local samples = math.floor(duration * rate)
    local data = love.sound.newSoundData(samples, rate, 16, 1)
    for i = 0, samples - 1 do
      local t = i / rate
      local envelope = math.exp(-t * (decay or 8))
      local v = math.sin(2 * math.pi * freq * t) * envelope * (vol or 0.4)
      data:setSample(i, v)
    end
    local src = love.audio.newSource(data, "static")
    src:setVolume(0.8)
    return src
  end

  -- Disable all SFX: music only
  audio.sfxJump = nil
  audio.sfxLand = nil
  audio.sfxCollect = nil
  audio.sfxBabyCry = nil
  audio.sfxExplosion = nil

  -- Procedural loop: soft clockwork beat + childlike pentatonic motif
  do
    local rate = 44100
    local bpm = 92
    local beats = 64 -- ~41.7s loop
    local seconds = beats * 60 / bpm
    local samples = math.floor(seconds * rate)
    local data = love.sound.newSoundData(samples, rate, 16, 2)
    local scale = { 261.63, 293.66, 329.63, 392.00, 440.00, 523.25 } -- C major pentatonic-ish
    local pattern = { 1, 3, 5, 2, 4, 6, 5, 3 }
    local stepSamples = math.floor(rate * 60 / (bpm * 2)) -- 8th notes
    for i = 0, samples - 1 do
      local t = i / rate
      local stepIndex = math.floor(i / stepSamples) % #pattern + 1
      local note = scale[pattern[stepIndex]]
      -- lead: plucky sine with quick attack/decay
      local tInStep = (i % stepSamples) / stepSamples
      local env = math.exp(-tInStep * 10)
      local lead = 0.13 * math.sin(2 * math.pi * note * t) * env
      -- pad: slow detuned sines
      local pad = 0.03 * math.sin(2 * math.pi * (note/2) * t)
                 + 0.03 * math.sin(2 * math.pi * (note/2 * 1.01) * t)
      -- No ticking/beeping overlay
      local l = lead + pad
      local r = lead + pad
      data:setSample(i, 1, l)
      data:setSample(i, 2, r)
    end
    audio.music = love.audio.newSource(data, "static")
    audio.music:setLooping(true)
    audio.music:setVolume(0.5)
    love.audio.setVolume(1.0)
    audio.music:play()
  end
end

function love.update(dt)
  game.time = game.time + dt
  blackHole.swirlTime = blackHole.swirlTime + dt

  -- Update rotating patterns on worlds
  for _, w in ipairs(worlds) do
    local spin = (w.pattern == "stripes" and 0.15 or (w.pattern == "dots" and -0.08 or 0.05))
    w.rotation = w.rotation + spin * dt
  end

  -- Asteroid orbits
  for _, a in ipairs(asteroids) do
    if a.capturedBy then
      -- captured around a world
      a.angle = a.angle + a.angularSpeed * dt
      local w = a.capturedBy
      a.orbitRadius = a.orbitRadius or (w.radius + 100 + (a.size or 16))
      a.x = w.x + math.cos(a.angle) * a.orbitRadius
      a.y = w.y + math.sin(a.angle) * a.orbitRadius
      -- lap count
      a.prevAngle = a.prevAngle or a.angle
      local delta = (a.angle - a.prevAngle)
      if delta < -math.pi then delta = delta + TAU elseif delta > math.pi then delta = delta - TAU end
      a.lapsProgress = (a.lapsProgress or 0) + math.abs(delta)
      a.prevAngle = a.angle
      if (a.lapsProgress or 0) >= TAU * 5 then
        -- after 5 spins, release back to black hole orbit
        a.capturedBy = nil
        a.lapsProgress = 0
      end
    else
      -- normal BH orbit
      a.angle = a.angle + a.angularSpeed * dt
    end
  end

  -- Explosions
  for ei = #explosions, 1, -1 do
    local e = explosions[ei]
    e.t = e.t + dt
    if e.t >= e.duration then
      table.remove(explosions, ei)
    end
  end

  -- Baby stars update
  for i, b in ipairs(babies) do
    b.bob = b.bob + dt
    if b.state == "home" then
      -- anchor to world surface with tiny bob
      local w = b.homeWorld
      b.angleOnWorld = b.angleOnWorld + 0.2 * dt
      local r = w.radius + 10 + math.sin(b.bob * 2) * 1.2
      b.x = w.x + math.cos(b.angleOnWorld) * r
      b.y = w.y + math.sin(b.angleOnWorld) * r
      b.cryTimer = b.cryTimer - dt
      if b.cryTimer <= 0 then
        if audio.sfxBabyCry then audio.sfxBabyCry:stop(); audio.sfxBabyCry:play() end
        b.cryTimer = 2.0 + math.random() * 2.5
      end
    elseif b.state == "following" then
      local idx = b.followIndex or 1
      local orbitR = 28 + 6 * ((idx - 1) % 4)
      local angle = game.time * 1.6 + (idx - 1) * 0.9
      local targetX = player.x + math.cos(angle) * orbitR
      local targetY = player.y + math.sin(angle) * orbitR
      b.x = lerp(b.x, targetX, 1 - math.exp(-8 * dt))
      b.y = lerp(b.y, targetY, 1 - math.exp(-8 * dt))
    end
  end

  -- Powerups drifting visuals on their worlds
  for _, p in ipairs(powerups) do
    if not p.picked then
      p.bob = p.bob + dt
      local r = p.world.radius + 14 + math.sin(p.bob * 2.3) * 1.0
      p.x = p.world.x + math.cos(p.angleOnWorld) * r
      p.y = p.world.y + math.sin(p.angleOnWorld) * r
    end
  end

  if game.state ~= "playing" then
    -- camera continue to follow slowly
    camera.x = lerp(camera.x, player.x, 1 - math.exp(-camera.smoothing * dt))
    camera.y = lerp(camera.y, player.y, 1 - math.exp(-camera.smoothing * dt))
    return
  end

  -- Movement input (disabled -> 0)
  local move = getMoveInput()

  if player.grounded and player.currentWorld then
    -- Local frame on the current world
    local w = player.currentWorld
    local dx = player.x - w.x
    local dy = player.y - w.y
    local dist = math.max(1e-6, length(dx, dy))
    local nx, ny = dx / dist, dy / dist
    local tx, ty = perpendicular(nx, ny)

    -- Decompose velocity into tangent only
    local tanSpeed = dot(player.vx, player.vy, tx, ty)

    -- No manual input acceleration; friction to rest
    local sign = (tanSpeed >= 0) and 1 or -1
    local mag = math.max(0, math.abs(tanSpeed) - player.frictionTangent * dt)
    tanSpeed = mag * sign

    -- Reconstruct velocity and advance position along the surface by angle
    player.vx = tx * tanSpeed
    player.vy = ty * tanSpeed
    local surfaceDist = w.radius + player.radius
    local angleOnWorld = math.atan2(player.y - w.y, player.x - w.x)
    local angularSpeed = tanSpeed / surfaceDist
    angleOnWorld = angleOnWorld + angularSpeed * dt
    nx, ny = math.cos(angleOnWorld), math.sin(angleOnWorld)
    player.x = w.x + nx * surfaceDist
    player.y = w.y + ny * surfaceDist

    -- Orient star to face outward normal (fix upside-down)
    local outwardAngle = math.atan2(ny, nx)
    player.angle = angleLerp(player.angle, outwardAngle + STAR_VISUAL_OFFSET, 1 - math.exp(-10 * dt))

  else
    -- In space: apply gravity from nearest world and black hole
    local gx1, gy1 = gravityFromBlackHole(player.x, player.y)
    local gx2, gy2, nearest, _ = gravityFromNearestWorld(player.x, player.y)
    -- If shield active, reduce planet gravity influence
    if player.hasShield then gx2, gy2 = gx2 * 0.35, gy2 * 0.35 end
    local gx = gx1 + gx2
    local gy = gy1 + gy2

    -- Air control relative to nearest world tangent
    do
      local tx, ty, nx, ny
      if nearest then
        local ndx = nearest.x - player.x
        local ndy = nearest.y - player.y
        local d = math.max(1e-6, length(ndx, ndy))
        nx, ny = ndx / d, ndy / d
      else
        local ndx = blackHole.x - player.x
        local ndy = blackHole.y - player.y
        local d = math.max(1e-6, length(ndx, ndy))
        nx, ny = ndx / d, ndy / d
      end
      tx, ty = perpendicular(nx, ny)

      local tanSpeed = dot(player.vx, player.vy, tx, ty)
      local radialSpeed = dot(player.vx, player.vy, nx, ny)

      -- No manual input in air; apply drag only
      local sign = (tanSpeed >= 0) and 1 or -1
      local mag = math.max(0, math.abs(tanSpeed) - player.airDrag * dt)
      tanSpeed = mag * sign

      player.vx = tx * tanSpeed + nx * radialSpeed
      player.vy = ty * tanSpeed + ny * radialSpeed
    end

    player.vx = player.vx + gx * dt
    player.vy = player.vy + gy * dt

    player.x = player.x + player.vx * dt
    player.y = player.y + player.vy * dt

    -- Grapple rope update: extend, attach, pull, retract
    if hook.active then
      if hook.phase == "extending" then
        -- move tip forward
        hook.length = math.min(hook.maxLength, hook.length + hook.speed * dt)
        hook.tipx = hook.startx + hook.dirx * hook.length
        hook.tipy = hook.starty + hook.diry * hook.length
        -- check attach if target reached
        local reachedAx = length(hook.tipx - hook.ax, hook.tipy - hook.ay) <= 8
        if hook.hasAnchor and reachedAx then
          hook.phase = "attached"
          hook.attached = true
        elseif hook.length >= hook.maxLength then
          hook.phase = "retracting"
        end
      elseif hook.phase == "attached" then
        -- Pull towards anchor while preserving momentum; simple springy pull
        local dx = hook.ax - player.x
        local dy = hook.ay - player.y
        local dist = math.max(1e-6, length(dx, dy))
        local dirx, diry = dx / dist, dy / dist
        local pull = 850
        player.vx = player.vx + dirx * pull * dt
        player.vy = player.vy + diry * pull * dt
        -- rope line from player to anchor
        hook.tipx, hook.tipy = hook.ax, hook.ay
        -- auto detach if we land or get very close
        if player.grounded or dist < player.radius + 4 then
          hook.phase = "retracting"
          hook.attached = false
        end
      elseif hook.phase == "retracting" then
        -- retract tip back to player
        local dx = player.x - hook.tipx
        local dy = player.y - hook.tipy
        local d = length(dx, dy)
        if d < 6 then
          hook.active = false
          hook.phase = "idle"
        else
          local dirx, diry = dx / d, dy / d
          local step = hook.retractSpeed * dt
          hook.tipx = hook.tipx + dirx * step
          hook.tipy = hook.tipy + diry * step
        end
      end
    end

    -- Try to land if we touched a world
    local landed, landingWorld = tryLandOnWorld()
    if landed then
      -- Shield is lost on touching ground
      if player.hasShield then player.hasShield = false end
      -- Detach rope if anchored to a different world surface point
      hook.active = false
      if audio.sfxLand then audio.sfxLand:stop(); audio.sfxLand:play() end
      -- landed logic handled inside
    end

    -- Orient star to velocity direction, fallback to last angle if very slow (fix orientation)
    local speed = length(player.vx, player.vy)
    if speed > 8 then
      player.angle = angleLerp(player.angle, math.atan2(player.vy, player.vx) + STAR_VISUAL_OFFSET, 1 - math.exp(-8 * dt))
    end
  end

  -- No jump input

  -- Win / interactions
  -- Win only if all babies collected and touching black hole
  local dxBH = player.x - blackHole.x
  local dyBH = player.y - blackHole.y
  if collectedBabies == totalBabies and length(dxBH, dyBH) <= blackHole.radius - 6 then
    game.state = "win"
  end

  -- Collect babies
  -- Collect babies
  for _, b in ipairs(babies) do
    if b.state == "home" then
      local d = length(player.x - b.x, player.y - b.y)
      if d <= player.radius + b.radius + 6 then
        b.state = "following"
        collectedBabies = collectedBabies + 1
        b.followIndex = collectedBabies
        if audio.sfxCollect then audio.sfxCollect:stop(); audio.sfxCollect:play() end
      end
    end
  end

  -- Collide with asteroids
  for ai = #asteroids, 1, -1 do
    local a = asteroids[ai]
    local ax, ay
    if a.capturedBy then
      ax, ay = a.x, a.y
    else
      ax = blackHole.x + math.cos(a.angle) * a.orbitRadius
      ay = blackHole.y + math.sin(a.angle) * a.orbitRadius
      -- wobble
      ax = ax + math.cos(a.angle * 2.3) * a.wobble * 28
      ay = ay + math.sin(a.angle * 1.7) * a.wobble * 28
    end

    local d = length(player.x - ax, player.y - ay)
    if d <= player.radius + a.size then
      if player.hasShield then
        -- destroy asteroid
        spawnExplosion(ax, ay)
        table.remove(asteroids, ai)
      else
        -- Explosion and reset babies, continue playing; also lose grapple
        spawnExplosion(player.x, player.y)
        for _, b in ipairs(babies) do
          if b.state == "following" then
            b.state = "home"
            b.followIndex = nil
            -- snap back near home world
            local w = b.homeWorld
            local angle = math.random() * TAU
            b.angleOnWorld = angle
            b.x = w.x + math.cos(angle) * (w.radius + 10)
            b.y = w.y + math.sin(angle) * (w.radius + 10)
          end
        end
        collectedBabies = 0
        -- lose grappling hook power
        if player.hasGrapple then player.hasGrapple = false end
        hook.active = false
        -- slight knockback away from asteroid
        local kx, ky = normalize(player.x - ax, player.y - ay)
        player.vx = player.vx + kx * 240
        player.vy = player.vy + ky * 240
        player.grounded = false
        player.currentWorld = nil
        break
      end
    end

    -- Check if asteroid gets captured by an attracting planet
    if not a.capturedBy then
      for _, w in ipairs(worlds) do
        if w.attractAsteroids then
          local dx = ax - w.x
          local dy = ay - w.y
          local d = length(dx, dy)
          if d < w.radius + 140 then
            a.capturedBy = w
            -- set angle based on current position
            a.angle = math.atan2(ay - w.y, ax - w.x)
            a.angularSpeed = (a.angularSpeed >= 0) and 0.9 or -0.9
            a.orbitRadius = math.max(w.radius + 40, d)
            a.prevAngle = a.angle
            a.lapsProgress = 0
            break
          end
        end
      end
    end
  end

  -- Camera follow
  camera.x = lerp(camera.x, player.x, 1 - math.exp(-camera.smoothing * dt))
  camera.y = lerp(camera.y, player.y, 1 - math.exp(-camera.smoothing * dt))

  -- Powerup pickups
  for _, p in ipairs(powerups) do
    if not p.picked then
      local d = length(player.x - p.x, player.y - p.y)
      if d <= player.radius + 10 then
        p.picked = true
        if p.type == "shield" then
          player.hasShield = true
        elseif p.type == "grapple" then
          player.hasGrapple = true
        elseif p.type == "pizza" then
          player.isFat = true
          player.radius = player.baseRadius * 1.5
        end
        if audio.sfxCollect then audio.sfxCollect:stop(); audio.sfxCollect:play() end
      end
    end
  end
end

function love.keypressed(key)
  if key == "r" then
    game.state = "playing"
    generateWorlds()
    generateBabies()
    generatePowerups()
    generateAsteroids()
    resetPlayer()
    player.hasShield = false
    player.hasGrapple = true
    player.isFat = false
    player.radius = player.baseRadius
    hook.active = false
    return
  end

  if game.state ~= "playing" then return end

  -- Jump disabled: only grappling hook
end

-- Mouse handling for grappling hook
local function getMouseWorld()
  local mx, my = love.mouse.getPosition()
  local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
  local wx = mx - sw / 2 + camera.x
  local wy = my - sh / 2 + camera.y
  return wx, wy
end

local function rayCircleIntersection(px, py, dx, dy, cx, cy, r)
  -- returns smallest t >= 0 if intersects, else nil
  local rx = px - cx
  local ry = py - cy
  local a = dx*dx + dy*dy
  local b = 2 * (dx*rx + dy*ry)
  local c = rx*rx + ry*ry - r*r
  local disc = b*b - 4*a*c
  if disc < 0 then return nil end
  local sqrt_disc = math.sqrt(disc)
  local t1 = (-b - sqrt_disc) / (2*a)
  local t2 = (-b + sqrt_disc) / (2*a)
  local t = nil
  if t1 and t1 >= 0 then t = t1 end
  if t2 and t2 >= 0 then t = (t and math.min(t, t2) or t2) end
  return t
end

local function tryStartHook()
  if not player.hasGrapple then return end
  local wx, wy = getMouseWorld()
  local dirx, diry = normalize(wx - player.x, wy - player.y)
  if dirx == 0 and diry == 0 then return end
  -- compute max rope length in world units using star units based on base radius
  local starUnit = player.baseRadius * 2
  local maxLen = (HOOK_BASE_STARS + collectedBabies * HOOK_PER_BABY_STARS) * starUnit

  hook.active = true
  hook.phase = "extending"
  hook.attached = false
  hook.hasAnchor = false
  hook.dirx, hook.diry = dirx, diry
  hook.startx, hook.starty = player.x, player.y
  hook.tipx, hook.tipy = player.x, player.y
  hook.length = 0
  hook.maxLength = maxLen

  -- Precompute first valid intersection within maxLen
  local bestT, bestAx, bestAy = nil, nil, nil
  for _, w in ipairs(worlds) do
    local t = rayCircleIntersection(player.x, player.y, dirx, diry, w.x, w.y, w.radius)
    if t and t <= maxLen then
      if not bestT or t < bestT then
        bestT = t
        bestAx = player.x + dirx * t
        bestAy = player.y + diry * t
      end
    end
  end
  if bestT then
    hook.ax, hook.ay = bestAx, bestAy
    hook.hasAnchor = true
  else
    hook.ax, hook.ay = player.x + dirx * maxLen, player.y + diry * maxLen
    hook.hasAnchor = false
  end
end

local function endHook()
  hook.active = false
end

function love.mousepressed(x, y, button)
  if button == 1 then
    tryStartHook()
  elseif button == 2 then
    endHook()
  end
end

function love.mousereleased(x, y, button)
  if button == 1 then
    endHook()
  end
end

function love.draw()
  -- Parallax starfield in screen space
  drawStarfield()

  love.graphics.push()
  -- World to screen transform
  local cx, cy = camera.x, camera.y
  local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
  love.graphics.translate(sw / 2 - cx, sh / 2 - cy)

  -- Worlds
  for _, w in ipairs(worlds) do
    drawWorld(w)
  end

  -- Black hole
  drawBlackHole()

  -- Asteroids with comet trails and rockier shape
  for _, a in ipairs(asteroids) do
    local ax, ay
    if a.capturedBy then
      local w = a.capturedBy
      local r = (a.orbitRadius or (w.radius + 100 + (a.size or 16)))
      local ang = a.angle or 0
      ax = w.x + math.cos(ang) * r
      ay = w.y + math.sin(ang) * r
    else
      ax = blackHole.x + math.cos(a.angle) * a.orbitRadius
      ay = blackHole.y + math.sin(a.angle) * a.orbitRadius
      ax = ax + math.cos(a.angle * 2.3) * a.wobble * 28
      ay = ay + math.sin(a.angle * 1.7) * a.wobble * 28
    end

    -- Trail history
    a.trail = a.trail or {}
    table.insert(a.trail, 1, {x=ax, y=ay})
    if #a.trail > 20 then table.remove(a.trail) end
    for i = #a.trail, 2, -1 do
      local p1, p2 = a.trail[i], a.trail[i-1]
      local alpha = (i / #a.trail) * 0.35
      love.graphics.setColor(0.7, 0.8, 1.0, alpha)
      love.graphics.setLineWidth(2)
      love.graphics.line(p1.x, p1.y, p2.x, p2.y)
    end

    love.graphics.push()
    love.graphics.translate(ax, ay)
    love.graphics.rotate(a.angle * 2)
    love.graphics.setColor(0.45, 0.43, 0.40)
    -- jagged rock polygon (precomputed shape)
    love.graphics.polygon("fill", a.rockShape)
    love.graphics.setColor(0.2, 0.2, 0.22)
    love.graphics.setLineWidth(2)
    love.graphics.polygon("line", a.rockShape)
    love.graphics.pop()
  end

  -- Explosions
  for _, e in ipairs(explosions) do
    local t = e.t / e.duration
    local r = 20 + t * 120
    love.graphics.setColor(1, 0.9, 0.6, 0.5 * (1 - t))
    love.graphics.circle("fill", e.x, e.y, r * 0.6)
    love.graphics.setColor(1, 0.6, 0.2, 0.8 * (1 - t))
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", e.x, e.y, r)
  end

  -- Babies
  for _, b in ipairs(babies) do
    drawBaby(b)
  end

  -- Grapple rope
  if hook.active then
    love.graphics.setColor(0.85, 0.85, 0.3, 0.9)
    love.graphics.setLineWidth(2)
    local hx = (hook.phase == "attached") and hook.ax or hook.tipx
    local hy = (hook.phase == "attached") and hook.ay or hook.tipy
    love.graphics.line(player.x, player.y, hx, hy)
    love.graphics.push()
    love.graphics.translate(hx, hy)
    local da = math.atan2(hy - player.y, hx - player.x)
    love.graphics.rotate(da)
    love.graphics.setColor(0.95, 0.95, 0.5)
    love.graphics.polygon("fill", -6, -3, -6, 3, 0, 0)
    love.graphics.pop()
  end

  -- Powerups
  for _, p in ipairs(powerups) do
    if not p.picked then
      love.graphics.push()
      love.graphics.translate(p.x, p.y)
      love.graphics.rotate(p.bob * 0.5)
      if p.type == "shield" then
        love.graphics.setColor(0.4, 0.7, 1.0)
        love.graphics.circle("fill", 0, 0, 8)
        love.graphics.setColor(0.2, 0.3, 0.5, 0.7)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", 0, 0, 10)
      elseif p.type == "grapple" then
        love.graphics.setColor(0.9, 0.9, 0.3)
        love.graphics.setLineWidth(3)
        love.graphics.line(-8, 0, 8, 0)
        love.graphics.line(8, 0, 4, -4)
        love.graphics.line(8, 0, 4, 4)
        love.graphics.setColor(0.9, 0.9, 0.3, 0.4)
        love.graphics.circle("line", 0, 0, 12)
      elseif p.type == "pizza" then
        love.graphics.setColor(1.0, 0.85, 0.4)
        love.graphics.polygon("fill", -8, 8, 0, -10, 8, 8)
        love.graphics.setColor(1.0, 0.3, 0.2)
        love.graphics.circle("fill", -2, 0, 1.6)
        love.graphics.circle("fill", 2, 2, 1.6)
        love.graphics.circle("fill", 1, -2, 1.6)
        love.graphics.setColor(0.5, 0.3, 0.1)
        love.graphics.setLineWidth(2)
        love.graphics.polygon("line", -8, 8, 0, -10, 8, 8)
      end
      love.graphics.pop()
    end
  end

  -- Player
  drawPlayer()

  love.graphics.pop()

  -- UI
  local uiY = 16
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("Hook: Left Mouse    Reset: R", 16, uiY)
  love.graphics.print(string.format("Babies: %d / %d", collectedBabies, totalBabies), 16, uiY + 22)
  local status = {}
  if player.hasShield then status[#status+1] = "Shield" end
  if player.hasGrapple then status[#status+1] = "Hook" end
  if player.isFat then status[#status+1] = "Pizza" end
  if #status > 0 then
    love.graphics.print("Power-ups: " .. table.concat(status, ", "), 16, uiY + 44)
  end

  if game.state == "win" then
    love.graphics.setColor(0.9, 1, 0.9)
    love.graphics.printf("All babies safe! Into the black hole you go.", 0, uiY + 24, love.graphics.getWidth(), "center")
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.printf("Press R to play again", 0, uiY + 48, love.graphics.getWidth(), "center")
  else
    if collectedBabies < totalBabies then
      love.graphics.setColor(1, 1, 1, 0.7)
      love.graphics.printf("Collect all baby stars and take them to the black hole!", 0, uiY + 48, love.graphics.getWidth(), "center")
    end
    if game.state == "dead" then
      love.graphics.setColor(1, 0.8, 0.8)
      love.graphics.printf("You died! Press R to retry", 0, uiY + 70, love.graphics.getWidth(), "center")
    end
  end
end
