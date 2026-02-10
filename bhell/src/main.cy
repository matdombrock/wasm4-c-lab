#include "wasm4.h"
#include <math.h>

typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef int8_t i8;
typedef int16_t i16;
typedef int32_t i32;
typedef uint8_t bool;

#define TRAIL_LEN 8
#define PROJ_MAX 32
#define ENEMY_MAX 16
#define PLAY_H 140
#define PLAY_W 160
#define NULL_COORD -256
#define PARTICLES_MAX 128
#define HP_MAX 48

//
// Sprites
//

const uint8_t smiley[] = {
  0b11111111,
  0b11011011,
  0b10100101,
  0b11000011,
  0b11000011,
  0b10100101,
  0b11011011,
  0b11111111,
};

const uint8_t enemy_a[] = {
  0b11111111,
  0b11111111,
  0b11100111,
  0b11000011,
  0b11000011,
  0b11011011,
  0b11111111,
  0b11111111,
};

// const u32 PAL_OG[] = {0x001105, 0x506655, 0xA0FFA5, 0xB0FFB5};
const u32 PAL_OG[] = {0x001000, 0x88b088, 0xaaffaa, 0xaabaff};

//
// RNG
//

// Xorshift32 RNG for WASM-4 in C
static unsigned int rng_state = 1;

void srand(unsigned int seed) {
    rng_state = seed ? seed : 1; // Avoid zero seed
}

unsigned int rand() {
    unsigned int x = rng_state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    rng_state = x;
    return x;
}

//
// Pos
//

typedef struct {
  float x;
  float y;
} PosF;

typedef struct {
  i16 x;
  i16 y;
} PosI;

float distanceF(PosF a, PosF b) {
  float dx = a.x - b.x;
  float dy = a.y - b.y;
  return sqrtf(dx * dx + dy * dy);
}

int distanceI(PosI a, PosI b) {
  int dx = a.x - b.x;
  int dy = a.y - b.y;
  return (int)sqrtf((float)(dx * dx + dy * dy));
}

PosI pos_addI(PosI a, PosI b) {
  PosI result;
  result.x = a.x + b.x;
  result.y = a.y + b.y;
  return result;
}

PosF pos_addF(PosF a, PosF b) {
  PosF result;
  result.x = a.x + b.x;
  result.y = a.y + b.y;
  return result;
}

PosF pos_multF(PosF a, float scalar) {
  PosF result;
  result.x = a.x * scalar;
  result.y = a.y * scalar;
  return result;
}

PosI posf_to_posi(PosF pf) {
  PosI pi;
  pi.x = (i16)pf.x;
  pi.y = (i16)pf.y;
  return pi;
}

bool pos_in_boundsI(PosI p) {
  return p.x >= 0 && p.x < PLAY_W && p.y >= 0 && p.y < PLAY_H;
}

bool pos_in_boundsF(PosF p) {
  return p.x >= 0 && p.x < PLAY_W && p.y >= 0 && p.y < PLAY_H;
}

// Return a random out of bounds position
// dist: distance from bounds
PosF pos_random_oobF(u8 dist) {
  PosF p;
  u8 side = rand() % 4;
  switch (side) {
    case 0: // Top
      p.x = (float)(rand() % PLAY_W);
      p.y = -dist;
      break;
    case 1: // Right
      p.x = PLAY_W + dist;
      p.y = (float)(rand() % PLAY_H);
      break;
    case 2: // Bottom
      p.x = (float)(rand() % PLAY_W);
      p.y = PLAY_H + dist;
      break;
    case 3: // Left
      p.x = -dist;
      p.y = (float)(rand() % PLAY_H);
      break;
  }
  return p;
} 

PosF velocity_towards(PosF from, PosF to, float speed, bool lerp) {
  float dx = to.x - from.x;
  float dy = to.y - from.y;
  float dist = sqrtf(dx * dx + dy * dy);
  PosF vel;
  if (lerp) {
    vel.x = (dx / dist) * speed;
    vel.y = (dy / dist) * speed;
  }
  else {
    vel.x = dx * speed;
    vel.y = dy * speed;
  }
  return vel;
}

//
// Projectiles
//

typedef enum {
  PROJ_BASIC,
  PROJ_BEAM,
  PROJ_DIR,
} PROJ_FIRE;

typedef enum {
  PROJ_HOMING,
  PROJ_LINEAR,
} PROJ_MOVE;

typedef struct {
  float speed;
  u8 fire_rate;
  u16 targeting_max;
  PROJ_FIRE fire_type;
  PROJ_MOVE move_type;
} ProjAttr;

ProjAttr proj_attr_random() {
  ProjAttr attr;
  attr.speed = 0.5f + (float)(rand() % 150) / 100.0f;
  attr.fire_rate = 4 + (rand() % 32);
  attr.targeting_max = 40 + (rand() % 120);
  attr.fire_type = (PROJ_FIRE)(rand() % 3);
  attr.move_type = (PROJ_MOVE)(rand() % 2);
  // Most fire types use linear movement
  if (attr.fire_type == PROJ_BEAM || attr.fire_type == PROJ_DIR) {
    attr.move_type = PROJ_LINEAR;
  }
  return attr;
}

// const ProjAttr proj_list[] = {
//   {
//     .speed = 0.5f,
//     .fire_rate = 16,
//     .targeting_max = 80,
//     .fire_type = PROJ_BASIC,
//     .move_type = PROJ_HOMING,
//   },
//   {
//     .speed = 1.0f,
//     .fire_rate = 8,
//     .targeting_max = 80,
//     .fire_type = PROJ_BASIC,
//     .move_type = PROJ_LINEAR,
//   },
//   {
//     .speed = 1.0f,
//     .fire_rate = 32,
//     .targeting_max = 80,
//     .fire_type = PROJ_BEAM,
//     .move_type = PROJ_LINEAR,
//   },
//   {
//     .speed = 2.0f,
//     .fire_rate = 2,
//     .targeting_max = 120,
//     .fire_type = PROJ_DIR,
//     .move_type = PROJ_LINEAR,
//   },
// };

typedef struct {
  PosF pos;
  PosF vel;
  PosF target;
  ProjAttr attr;
} Proj;

void proj_update(Proj* projectiles) {
  for (i8 i = 0; i < PROJ_MAX; i++) {
    Proj* proj = &projectiles[i];
    if (proj->pos.x == NULL_COORD) {
      continue;
    }
    ProjAttr pdata = proj->attr;
    if (pdata.move_type == PROJ_HOMING) {
      // Move towards target
      if (proj->target.x != NULL_COORD) {
        float dist = distanceF(proj->pos, proj->target);
        if (dist < 1.0f) {
          // Reached target
          proj->pos.x = NULL_COORD;
          proj->pos.y = NULL_COORD;
          continue;
        }
        proj->vel = velocity_towards(proj->pos, proj->target, pdata.speed, 1);
      }
      proj->pos.x += proj->vel.x;
      proj->pos.y += proj->vel.y;
    }
    else if (pdata.move_type == PROJ_LINEAR) {
      // Move linearly
      proj->pos.x += proj->vel.x;
      proj->pos.y += proj->vel.y;
    }
    // Check for out of bounds
    if (!pos_in_boundsF(proj->pos)) {
      proj->pos.x = NULL_COORD;
      proj->pos.y = NULL_COORD;
    }
  }
}

//
// Player
//

typedef struct {
  u8 hp;
  u16 score;
  PosF pos;
  PosF vel;
  float friction;
  float speed;
  PosF target;
  u8 proj_slot;
  ProjAttr proj_a;
  ProjAttr proj_b;
  u8 last_proj_dir; // URDL
  bool b1_released;
  PosI trail[TRAIL_LEN];
} Player;

void player_init(Player* p) {
  p->hp = 32;
  p->score = 0;
  p->pos.x = 76;
  p->pos.y = 76;
  p->vel.x = 0;
  p->vel.y = 0;
  p->friction = 0.97f;
  p->speed = 0.1f;
  p->target.x = NULL_COORD;
  p->target.y = NULL_COORD;
  p->proj_slot = 3;
  p->proj_a = proj_attr_random();
  p->proj_b = proj_attr_random();
  p->last_proj_dir = 0;
  p->b1_released = 1;
  for (i8 i = 0; i < 16; i++) {
    p->trail[i].x = 76;
    p->trail[i].y = 76;
  }
}

void player_hp_change(Player* p, i8 delta) {
  trace("HP change");
  // Saturating sub
  if (delta < 0 && p->hp < -delta) {
    trace("HP zeroed");
    p->hp = 0;
    return;
  }
  p->hp += delta;
  if (p->hp > HP_MAX) {
    p->hp = HP_MAX;
  }
}

ProjAttr player_get_proj(Player* p) {
  return p->proj_slot == 0 ? p->proj_a : p->proj_b;
}

//
// Enemy
//

typedef struct {
  PosF pos;
  PosF vel;
  u8 hp;
  u8 hit_frames;
} Enemy;

void enemy_wave(Enemy* enemies, u8 wave) {
  for (i16 i = 0; i < ENEMY_MAX; i++) {
    enemies[i].pos.x = NULL_COORD;
    enemies[i].pos.y = NULL_COORD;
    enemies[i].vel.x = 0;
    enemies[i].vel.y = 0;
    enemies[i].hp = 3;
    enemies[i].hit_frames = 0;
  }
  switch (wave) {
    case 1:
      // Spawn 4 enemies
      for (i16 i = 0; i < 4; i++) {
        Enemy* e = &enemies[i];
        e->pos.x = (i * 40) + 20;
        e->pos.y = 0;
        e->vel.x = 0;
        e->vel.y = 0;
        e->hp = 3;
        e->hit_frames = 0;
      }
      break;
    case 2:
      // Spawn 8 enemies
      for (i16 i = 0; i < 8; i++) {
        Enemy* e = &enemies[i];
        e->pos.x = (i * 20) + 10;
        e->pos.y = 0;
        e->vel.x = 0;
        e->vel.y = 0;
        e->hp = 3;
        e->hit_frames = 0;
      }
      break;
    case 3:
      // Spawn 12 enemies at random x,y positions
      for (i16 i = 0; i < 12; i++) {
        Enemy* e = &enemies[i];
        PosF pos_random = pos_random_oobF(8);
        e->pos = pos_random;
        e->vel.x = 0;
        e->vel.y = 0;
        e->hp = 3;
        e->hit_frames = 0;
      }
      break;
    default:
      break;
  }
}

void enemy_update(Enemy* enemy, PosF p1_center) {
  for (i16 i = 0; i < ENEMY_MAX; i++) {
    Enemy* en = &enemy[i];
    if (en->pos.x == NULL_COORD) {
      continue;
    }
    PosF en_center = pos_addF(en->pos, (PosF){4,4});
    // Move towards player
    float speed = 0.5f;
    float dist = distanceF(en_center, p1_center); 
    en->vel = velocity_towards(en_center, p1_center, speed, 1);
    PosF pos_cache = en->pos;
    en->pos.x += en->vel.x;
    en->pos.y += en->vel.y;
    // Update center
    en_center = pos_addF(en->pos, (PosF){4,4});
    // Check for collision with other enemies
    for (i16 j = 0; j < ENEMY_MAX; j++) {
      if (i == j) {
        continue;
      }
      Enemy* other = &enemy[j];
      if (other->pos.x == NULL_COORD) {
        continue;
      }
      PosF other_center = pos_addF(other->pos, (PosF){4,4});
      if (distanceF(en_center, other_center) < 8.0f) {
        // Collision, revert position
        en->pos = pos_cache;
        // If OOB go to random oob location
        // Protects against enemies getting stuck OOB
        if (!pos_in_boundsF(other->pos)) {
          other->pos = pos_random_oobF(8);
        }
      }
    } 
    // Update hit frames
    for (i16 j = 0; j < ENEMY_MAX; j++) {
      Enemy* en = &enemy[j];
      if (en->hit_frames > 0) {
        en->hit_frames--;
      }
    }
  }
}

//
// Particle
//

typedef struct {
  PosF pos;
  PosF vel;
  u16 life;
} Particle;

// TODO: Remove amt?
void particle_add(Particle* particles, u8 amt, PosF pos, PosF vel) {
  trace("Add particle");
  u8 added = 0;
  for (i16 i = 0; i < PARTICLES_MAX; i++) {
    if (particles[i].life == 0) {
      particles[i].pos = pos;
      particles[i].vel = vel;
      particles[i].life = 512;
      added++;
      if (added == amt) {
        break;
      }
    }
  }
}

void particle_update(Particle* particles) {
  for (i16 i = 0; i < PARTICLES_MAX; i++) {
    Particle* part = &particles[i];
    // Check for out of bounds
    if (!pos_in_boundsF(part->pos)) {
      part->life = 0;
    }
    if (part->life > 0) {
      part->pos.x += part->vel.x;
      part->pos.y += part->vel.y;
      part->life--;
    }
    else {
      part->pos.x = NULL_COORD;
      part->pos.y = NULL_COORD;
    }
  }
}

//
// State
//

typedef struct {
  Player p1;
  u16 frame;
  u16 enemies_alive;
  Proj projectiles[PROJ_MAX];
  Enemy enemies[ENEMY_MAX];
  Particle particles[PARTICLES_MAX];
} State;

static State state;

void state_init(State* st) {
  st->frame = 0;
  st->enemies_alive = 0;
  player_init(&st->p1);
  enemy_wave(st->enemies, 3);
  // Initialize projectiles
  ProjAttr proj_r = proj_attr_random();
  for (i8 i = 0; i < PROJ_MAX; i++) {
    st->projectiles[i].pos.x = NULL_COORD;
    st->projectiles[i].pos.y = NULL_COORD;
    st->projectiles[i].vel.x = 0;
    st->projectiles[i].vel.y = 0;
    st->projectiles[i].target.x = 0;
    st->projectiles[i].target.y = 0;
    st->projectiles[i].attr = proj_r;
  }
}

//
// Engine
//

// Set the palette colors
void palette_set(const u32 pal[4]) {
  PALETTE[0] = pal[0];
  PALETTE[1] = pal[1];
  PALETTE[2] = pal[2];
  PALETTE[3] = pal[3];
}

void line_rect(i16 ox, i16 oy, u16 w, u16 h) {
  line(ox, oy, ox + w, oy);
  line(ox + w, oy, ox + w, oy + h);
  line(ox + w, oy + h, ox, oy + h);
  line(ox, oy + h, ox, oy);
}

void color_flash(u8 ca, u8 cb, u8 frames) {
  if ((state.frame / frames) % 2 == 0) {
    *DRAW_COLORS = ca;
  } else {
    *DRAW_COLORS = cb;
  }
}

// Integer to ASCII conversion
// Sprintf does not work in wasm4
void itoa(u32 value, char *buffer) {
  char temp[12]; // Enough for 32-bit int
  int i = 0, j = 0;
  int is_negative = 0;

  if (value == 0) {
    buffer[0] = '0';
    buffer[1] = '\0';
    return;
  }

  if (value < 0) {
    is_negative = 1;
    value = -value;
  }

  while (value != 0) {
    temp[i++] = (value % 10) + '0';
    value /= 10;
  }

  if (is_negative)
    temp[i++] = '-';

  // Reverse the string
  while (i > 0)
    buffer[j++] = temp[--i];

  buffer[j] = '\0';
}

//
// Game functions
//

void input() {
  u8 gamepad = *GAMEPAD1;
  if (gamepad & BUTTON_RIGHT) {
    state.p1.vel.x += state.p1.speed;
  }
  if (gamepad & BUTTON_LEFT) {
    state.p1.vel.x -= state.p1.speed;
  }
  if (gamepad & BUTTON_DOWN) {
    state.p1.vel.y += state.p1.speed;
  }
  if (gamepad & BUTTON_UP) {
    state.p1.vel.y -= state.p1.speed;
  }
  if (gamepad & BUTTON_1) {
    if (state.p1.b1_released) {
      // Swap projectile slots
      state.p1.proj_slot = state.p1.proj_slot == 0 ? 1 : 0;
      //
    }
    state.p1.b1_released = 0;
  }
  else {
    state.p1.b1_released = 1;
  }
}

void player_update() {
  // Move
  state.p1.pos.x += state.p1.vel.x;
  state.p1.pos.y += state.p1.vel.y;
  // Wrap around screen
  PosF center = pos_addF(state.p1.pos, (PosF){4,4});
  if (center.x > PLAY_W) {
    state.p1.pos.x = 4;
  }
  if (center.x < 0) {
    state.p1.pos.x = PLAY_W - 4;
  }
  if (center.y > PLAY_H) {
    state.p1.pos.y = 4;
  }
  if (center.y < 0) {
    state.p1.pos.y = PLAY_H - 4;
  }
  // Friction
  state.p1.vel.x *= state.p1.friction;
  state.p1.vel.y *= state.p1.friction;
  // Trail
  for (i32 i = TRAIL_LEN - 1; i > 0; i--) {
    state.p1.trail[i] = state.p1.trail[i - 1];
  }
  state.p1.trail[0] = posf_to_posi(state.p1.pos);
  // Update target to the enemy closest to the player
  float closest_dist = 9999.0f;
  PosF closest_enemy_pos = {NULL_COORD, NULL_COORD};
  for (i16 i = 0; i < ENEMY_MAX; i++) {
    Enemy* e = &state.enemies[i];
    if (e->pos.x == NULL_COORD) {
      continue;
    }
    float dist = distanceF(center, pos_addF(e->pos, (PosF){2,2}));
    if (dist < closest_dist) {
      closest_dist = dist;
      closest_enemy_pos = e->pos;
    }
  }
  state.p1.target = closest_enemy_pos;
  // Projectiles
  ProjAttr pdata = player_get_proj(&state.p1); 
  u8 fire_frame = state.frame % pdata.fire_rate == 0;
  u8 in_range = distanceF(state.p1.pos, state.p1.target) < pdata.targeting_max;
  if (fire_frame && in_range) {
    for (i8 i = 0; i < PROJ_MAX; i++) {
      if (state.projectiles[i].pos.x == NULL_COORD) {
        state.projectiles[i].attr = player_get_proj(&state.p1);
        state.projectiles[i].target = state.p1.target;
        if (pdata.fire_type == PROJ_BASIC) {
          state.projectiles[i].pos = state.p1.pos;
          state.projectiles[i].vel = velocity_towards(state.projectiles[i].pos, state.projectiles[i].target, pdata.speed, 1);
          break;
        }
        else if (pdata.fire_type == PROJ_BEAM) {
          state.projectiles[i].pos = state.p1.target;
          state.projectiles[i].vel = (PosF){0,0};
          break;
        }
        else if (pdata.fire_type == PROJ_DIR) {
          state.projectiles[i].pos = state.p1.pos;
          switch(state.p1.last_proj_dir) {
          case 0: // Up
            state.projectiles[i].vel = (PosF){0, -pdata.speed};
            break;
          case 1: // Right
            state.projectiles[i].vel = (PosF){pdata.speed, 0};
            break;
          case 2: // Down
            state.projectiles[i].vel = (PosF){0, pdata.speed};
            break;
          case 3: // Left
            state.projectiles[i].vel = (PosF){-pdata.speed, 0};
            break;
          }
          state.p1.last_proj_dir = (state.p1.last_proj_dir + 1) % 4;
          break;
        }
      }
    }
  }
}

void render() {
  *DRAW_COLORS = 4;
  PosI p1_pos = posf_to_posi(state.p1.pos);
  blit(smiley, p1_pos.x, p1_pos.y, 8, 8, BLIT_1BPP);
  // Draw trail
  *DRAW_COLORS = 4;
  for (i8 i = 0; i < TRAIL_LEN; i++) {
    PosI trail_pos = state.p1.trail[i];
    PosI trail_pos_last = {0,0};
    if (i > 0) {
      trail_pos_last = state.p1.trail[i - 1];
    } else {
      trail_pos_last = p1_pos;
    }
    // Center on sprite
    trail_pos = pos_addI(trail_pos, (PosI){4,4});
    trail_pos_last = pos_addI(trail_pos_last, (PosI){4,4});
    if (distanceI(trail_pos, trail_pos_last) > 100) {
      continue;
    }
    if (i > 8) {
      *DRAW_COLORS = 2;
    } else if (i > 4) {
      *DRAW_COLORS = 2;
    } else {
      *DRAW_COLORS = 3;
    }

    line(trail_pos.x, trail_pos.y, trail_pos_last.x, trail_pos_last.y);
    // line(trail_pos.x + 4, trail_pos.y + 4, p1_pos.x + 4, p1_pos.y + 4);
  }

  ProjAttr pdata = player_get_proj(&state.p1);
  u8 in_range = distanceF(state.p1.pos, state.p1.target) < pdata.targeting_max;

  // Draw targeting
  if (pdata.fire_type != PROJ_DIR) {
    if (in_range) {
      PosI target_i = posf_to_posi(state.p1.target);
      // PosI target_center = pos_addI(target_i, (PosI){4,4});
      color_flash(1, 3, 8);
      // line(target_center.x, target_center.y, p1_pos.x + 4, p1_pos.y + 4);
      line_rect(target_i.x + 2, target_i.y + 2, 4, 4);
    }
  }
  // Draw projectiles
  *DRAW_COLORS = 3;
  for (i8 i = 0; i < PROJ_MAX; i++) {
    if (state.projectiles[i].pos.x != NULL_COORD) { PosI proj_pos = posf_to_posi(state.projectiles[i].pos);
      rect(proj_pos.x + 4, proj_pos.y + 4, 1, 1);
    }
  }
  // Render beam projectiles
  if (pdata.fire_type == PROJ_BEAM) {
    u8 fire_frame = state.frame % pdata.fire_rate < 4;
    if (fire_frame && in_range) {
      *DRAW_COLORS = 3;
      PosI p1_center = pos_addI(p1_pos, (PosI){4,4});
      PosI target_center = pos_addI(posf_to_posi(state.p1.target), (PosI){4,4});
      line(p1_center.x, p1_center.y, target_center.x, target_center.y);
    }
  }
  // Draw enemies
  for (i16 i = 0; i < ENEMY_MAX; i++) {
    *DRAW_COLORS = 2;
    if (state.enemies[i].hit_frames > 0) {
      color_flash(4, 3, 24);
    }
    if (state.enemies[i].pos.x != NULL_COORD) {
      PosI enemy_pos = posf_to_posi(state.enemies[i].pos);
      // rect(enemy_pos.x, enemy_pos.y, 4, 4);
      blit(enemy_a, enemy_pos.x, enemy_pos.y, 8, 8, BLIT_1BPP);
    }
  }
  // Draw particles
  color_flash(4, 2, 8);
  for (i16 i = 0; i < PARTICLES_MAX; i++) {
    Particle* part = &state.particles[i];
    if (part->life > 0) {
      PosI part_pos = posf_to_posi(part->pos);
      rect(part_pos.x, part_pos.y, 1, 1);
    }
  }
  // Bottom bar
  *DRAW_COLORS = 2;
  rect(0, PLAY_H, PLAY_W, 20);
  *DRAW_COLORS = 1;
  // Slots
  bool is_slot_a = state.p1.proj_slot == 0;
  line_rect(2, PLAY_H + 2, 20, 7);
  *DRAW_COLORS = is_slot_a ? 3 : 1;
  rect(4, PLAY_H + 4, 8, 4);
  *DRAW_COLORS = is_slot_a ? 1 : 3;
  rect(13, PLAY_H + 4, 8, 4);
  // Health bar
  *DRAW_COLORS = 1;
  line_rect(24, PLAY_H + 2, 51, 7);
  rect(26, PLAY_H + 4, HP_MAX, 4);
  *DRAW_COLORS = 3;
  rect(26, PLAY_H + 4, state.p1.hp, 4);

  // 
  char buffer[12];
  itoa(state.p1.score, buffer);
  *DRAW_COLORS = 1;
  text("> ", 2, 151);
  text(buffer, 10, 151);

  // Debug info
  char dbg_buffer[32];
  itoa(state.enemies_alive, dbg_buffer);
  *DRAW_COLORS = 2;
  text(dbg_buffer, 0, 0);
  ProjAttr pdata_dbg = player_get_proj(&state.p1);
  itoa((u32)(pdata_dbg.speed * 100.0f), dbg_buffer);
  text(dbg_buffer, 0, 8);
  itoa(pdata_dbg.fire_rate, dbg_buffer);
  text(dbg_buffer, 0, 16);
  itoa(pdata_dbg.targeting_max, dbg_buffer);
  text(dbg_buffer, 0, 24);
  itoa((u32)pdata_dbg.fire_type, dbg_buffer);
  text(dbg_buffer, 0, 32);
  itoa((u32)pdata_dbg.move_type, dbg_buffer);
  text(dbg_buffer, 0, 40);
  // last dir
  itoa((u32)state.p1.last_proj_dir, dbg_buffer);
  text(dbg_buffer, 0, 48);
}

void collisions_update() {
  // Enemy vs Projectiles
  for (i16 i = 0; i < ENEMY_MAX; i++) {
    Enemy* en = &state.enemies[i];
    if (en->pos.x == NULL_COORD) {
      continue;
    }
    for (i8 j = 0; j < PROJ_MAX; j++) {
      Proj* proj = &state.projectiles[j];
      if (proj->pos.x == NULL_COORD) {
        continue;
      }
      if (distanceF(en->pos, proj->pos) < 4.0f) {
        // Hit
        particle_add(state.particles, 1, en->pos, pos_multF(proj->vel, 0.1f));
        en->hp--;
        en->hit_frames = 30;
        if (en->hp == 0) {
          en->pos.x = NULL_COORD;
          en->pos.y = NULL_COORD;
        }
        proj->pos.x = NULL_COORD;
        proj->pos.y = NULL_COORD;
      }
    }
  }
  PosF p1_center = pos_addF(state.p1.pos, (PosF){4,4});
  // Enemy vs Player
  for (i16 i = 0; i < ENEMY_MAX; i++) {
    Enemy* en = &state.enemies[i];
    if (en->pos.x == NULL_COORD) {
      continue;
    }
    if (distanceF(p1_center, pos_addF(en->pos, (PosF){4,4})) < 6.0f) {
      // Hit
      trace("Player hit by enemy");
      en->pos.x = NULL_COORD;
      en->pos.y = NULL_COORD;
      player_hp_change(&state.p1, -4);
    }
  }
  // Player vs Particles
  for (i16 i = 0; i < PARTICLES_MAX; i++) {
    Particle* part = &state.particles[i];
    if (part->life > 0) {
      if (distanceF(p1_center, part->pos) < 4.0f) {
        // Hit
        trace("Player hit by particle");
        part->life = 0;
        player_hp_change(&state.p1, 1);
        state.p1.score += 1;
      }
    }
  }
}

// 
// WASM-4 entry points
//

void start() { 
  palette_set(PAL_OG); 
  srand(3001);
  state_init(&state);
}

void update() {
  state.frame++;
  input();
  player_update();
  enemy_update(state.enemies, pos_addF(state.p1.pos, (PosF){4,4}));
  proj_update(state.projectiles);
  collisions_update();
  particle_update(state.particles);
  render();
  // 
  state.enemies_alive = 0;
  for (i16 i = 0; i < ENEMY_MAX; i++) {
    if (state.enemies[i].pos.x != NULL_COORD) {
      state.enemies_alive++;
    }
  }
  if (!state.enemies_alive) {
    enemy_wave(state.enemies, 2);
  }
}
